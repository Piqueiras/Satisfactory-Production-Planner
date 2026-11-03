import std/[dom, strutils, strformat, tables, sets, sequtils, algorithm, math]
import types, dataset, planner, presets, svg_graph

type
  SelectElement* {.importc.} = ref object of Element
    value*: cstring
    selectedIndex*: int

proc findClosest(target: Node, selector: cstring): Element =
  var res: Element
  {.emit: """
    var el = `target`;
    var sel = `selector`;
    `res` = (el && el.closest) ? el.closest(sel) : ((el && el.parentElement) ? el.parentElement.closest(sel) : null);
  """.}
  return res

var
  currentTargets: seq[FactoryTarget] = @[]
  enabledAlternates: HashSet[string] = initHashSet[string]()
  allowAllAlternates: bool = false
  currentTab: string = "overview"
  graphViewMode: string = "svg"
  currentPlan: FactoryPlan
  altSearchQuery: string = ""
  dbSearchQuery: string = ""

proc escapeHtml(s: string): string =
  result = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

proc setHtml(idStr: string, htmlStr: string) =
  let el = document.getElementById(cstring(idStr))
  if el != nil:
    el.innerHTML = cstring(htmlStr)

proc getInputValue(idStr: string): string =
  let el = document.getElementById(cstring(idStr))
  if el != nil:
    return $cast[InputElement](el).value
  return ""

proc setInputValue(idStr: string, valStr: string) =
  let el = document.getElementById(cstring(idStr))
  if el != nil:
    cast[InputElement](el).value = cstring(valStr)

# Forward declarations
proc renderApp*()
proc updatePlan*()
proc bindGlobalEvents*()

proc renderTargetsBar(): string =
  var html = "<div class='targets-container'>"
  html.add("<div class='targets-input-row'>")
  
  # Select item dropdown
  html.add("<div class='input-group'>")
  html.add("<label for='target-item-select'>Select Product:</label>")
  html.add("<select id='target-item-select' class='ficsit-select'>")
  for idStr in craftableItemIds:
    let item = allItems[idStr]
    html.add(fmt"<option value='{idStr}'>{escapeHtml(item.name)} ({item.category})</option>")
  html.add("</select>")
  html.add("</div>")

  # Target rate input
  html.add("<div class='input-group rate-group'>")
  html.add("<label for='target-rate-input'>Target Rate (items/min):</label>")
  html.add("<div class='rate-input-wrapper'>")
  html.add("<input id='target-rate-input' type='number' min='0.1' step='1' value='10' class='ficsit-input' />")
  html.add("<span class='rate-unit'>/ min</span>")
  html.add("</div>")
  html.add("</div>")

  # Add Button
  html.add("<button id='btn-add-target' class='ficsit-btn btn-primary'>+ Add Product</button>")

  # Presets dropdown
  html.add("<div class='input-group presets-group'>")
  html.add("<label for='preset-select'>Factory Presets:</label>")
  html.add("<select id='preset-select' class='ficsit-select preset-select'>")
  html.add("<option value=''>-- Load Preset Factory --</option>")
  for p in getPresets():
    html.add(fmt"<option value='{p.id}'>{escapeHtml(p.name)}</option>")
  html.add("</select>")
  html.add("</div>")

  html.add("</div>") # targets-input-row

  # Active target chips
  html.add("<div class='active-targets-list'>")
  if currentTargets.len == 0:
    html.add("<div class='no-targets-hint'>No active production targets. Select a product and click <strong>+ Add Product</strong> or choose a <strong>Preset</strong> above!</div>")
  else:
    for idx, t in currentTargets:
      let item = allItems.getOrDefault(t.itemId, Item(name: t.itemId, color: "#FA9549"))
      html.add("<div class='target-chip'>")
      html.add(fmt"<span class='chip-color' style='background-color: {item.color};'></span>")
      html.add(fmt"<span class='chip-name'>{escapeHtml(item.name)}:</span>")
      html.add(fmt"<span class='chip-rate'>{t.rate:.1f} / min</span>")
      html.add(fmt"<button class='chip-step-btn' data-action='dec' data-idx='{idx}' title='-5/min'>-5</button>")
      html.add(fmt"<button class='chip-step-btn' data-action='inc' data-idx='{idx}' title='+5/min'>+5</button>")
      html.add(fmt"<button class='chip-remove-btn' data-idx='{idx}' title='Remove'>✕</button>")
      html.add("</div>")
    html.add("<button id='btn-clear-targets' class='ficsit-btn btn-danger btn-sm'>Clear All</button>")

  html.add("</div>") # active-targets-list
  html.add("</div>") # targets-container
  return html

proc renderOverviewTab(): string =
  var html = "<div class='tab-content overview-tab'>"

  if not currentPlan.success:
    html.add(fmt"<div class='ficsit-alert alert-error'>⚠️ <strong>Calculation Error:</strong> {escapeHtml(currentPlan.errorMessage)}</div>")
    return html & "</div>"

  if currentTargets.len == 0:
    html.add("<div class='empty-placeholder'>Select at least one product target above to calculate factory requirements.</div>")
    return html & "</div>"

  # Metrics Cards Grid
  html.add("<div class='metrics-grid'>")
  
  # Metric 1: Total Power
  html.add("<div class='metric-card card-power'>")
  html.add("<div class='metric-icon'>⚡</div>")
  html.add("<div class='metric-info'>")
  html.add("<span class='metric-title'>TOTAL FACTORY POWER</span>")
  html.add(fmt"<span class='metric-value'>{currentPlan.totalPowerMW:.1f} <small>MW</small></span>")
  html.add(fmt"<span class='metric-sub'>~{(currentPlan.totalPowerMW / 75.0):.1f} Coal Generators</span>")
  html.add("</div>")
  html.add("</div>")

  # Metric 2: Total Buildings
  html.add("<div class='metric-card card-buildings'>")
  html.add("<div class='metric-icon'>🏭</div>")
  html.add("<div class='metric-info'>")
  html.add("<span class='metric-title'>PRODUCTION BUILDINGS</span>")
  html.add(fmt"<span class='metric-value'>{currentPlan.totalBuildings:.1f} <small>machines</small></span>")
  html.add(fmt"<span class='metric-sub'>{currentPlan.steps.len} unique recipe stages</span>")
  html.add("</div>")
  html.add("</div>")

  # Metric 3: Raw Resources
  html.add("<div class='metric-card card-resources'>")
  html.add("<div class='metric-icon'>⛏️</div>")
  html.add("<div class='metric-info'>")
  html.add("<span class='metric-title'>RAW RESOURCE TYPES</span>")
  html.add(fmt"<span class='metric-value'>{currentPlan.rawResources.len} <small>resources</small></span>")
  html.add("<span class='metric-sub'>Extracted from world nodes</span>")
  html.add("</div>")
  html.add("</div>")

  # Metric 4: Byproducts
  html.add("<div class='metric-card card-byproducts'>")
  html.add("<div class='metric-icon'>♻️</div>")
  html.add("<div class='metric-info'>")
  html.add("<span class='metric-title'>BYPRODUCTS & SURPLUS</span>")
  if currentPlan.byproducts.len == 0:
    html.add("<span class='metric-value'>0 <small>waste</small></span>")
    html.add("<span class='metric-sub'>100% Balanced Factory</span>")
  else:
    html.add(fmt"<span class='metric-value'>{currentPlan.byproducts.len} <small>items</small></span>")
    html.add("<span class='metric-sub'>Recycled or Sinkable</span>")
  html.add("</div>")
  html.add("</div>")

  html.add("</div>") # metrics-grid

  # Two-column layout: Raw Resources & Machine Breakdown
  html.add("<div class='overview-columns'>")

  # Left Column: Raw Resources Shopping List
  html.add("<div class='column-box'>")
  html.add("<h3 class='column-title'>⛏️ Raw Materials Required (per minute)</h3>")
  html.add("<table class='ficsit-table'>")
  html.add("<thead><tr><th>Resource</th><th>Rate Required</th><th>Suggested Miners / Extractors</th></tr></thead>")
  html.add("<tbody>")
  for req in currentPlan.rawResources:
    let color = getItemColor(req.itemId)
    html.add("<tr>")
    html.add(fmt"<td><span class='table-badge' style='border-left: 4px solid {color};'>{escapeHtml(req.itemName)}</span></td>")
    html.add(fmt"<td class='text-bold'>{req.rate:.1f} / min</td>")
    html.add(fmt"<td><span class='miner-tag'>{escapeHtml(req.suggestedMiners)}</span></td>")
    html.add("</tr>")
  html.add("</tbody></table>")
  html.add("</div>")

  # Right Column: Machine Type Summary
  var machineCounts = initTable[string, float]()
  var machinePower = initTable[string, float]()
  for st in currentPlan.steps:
    machineCounts[st.machineName] = machineCounts.getOrDefault(st.machineName, 0.0) + st.buildingCount
    machinePower[st.machineName] = machinePower.getOrDefault(st.machineName, 0.0) + st.powerMW

  html.add("<div class='column-box'>")
  html.add("<h3 class='column-title'>🏭 Machine Inventory Required</h3>")
  html.add("<table class='ficsit-table'>")
  html.add("<thead><tr><th>Machine Type</th><th>Count</th><th>Power</th></tr></thead>")
  html.add("<tbody>")
  for mName, count in machineCounts:
    let mw = machinePower.getOrDefault(mName, 0.0)
    html.add("<tr>")
    html.add(fmt"<td><strong>{escapeHtml(mName)}</strong></td>")
    html.add(fmt"<td class='text-bold'>{count:.2f} (⌈{int(ceil(count))}⌉)</td>")
    html.add(fmt"<td>{mw:.1f} MW</td>")
    html.add("</tr>")
  html.add("</tbody></table>")
  html.add("</div>")

  html.add("</div>") # overview-columns
  html.add("</div>") # tab-content
  return html

proc renderStepsTab(): string =
  var html = "<div class='tab-content steps-tab'>"
  if not currentPlan.success or currentPlan.steps.len == 0:
    html.add("<div class='empty-placeholder'>No production steps to display. Add targets above to calculate the factory plan.</div>")
    return html & "</div>"

  html.add("<div class='table-header-info'>")
  html.add(fmt"<span>Showing <strong>{currentPlan.steps.len}</strong> production stages. Machines can be underclocked or balanced.</span>")
  html.add("</div>")

  html.add("<div class='table-responsive'>")
  html.add("<table class='ficsit-table steps-table'>")
  html.add("<thead><tr>")
  html.add("<th>Recipe</th>")
  html.add("<th>Machine</th>")
  html.add("<th>Quantity</th>")
  html.add("<th>Clock Speed Recommendation</th>")
  html.add("<th>Power</th>")
  html.add("<th>Inputs (per min)</th>")
  html.add("<th>Outputs (per min)</th>")
  html.add("</tr></thead>")
  html.add("<tbody>")

  for st in currentPlan.steps:
    html.add("<tr>")
    html.add(fmt"<td><strong>{escapeHtml(st.recipeName)}</strong></td>")
    html.add(fmt"<td><span class='machine-badge'>{escapeHtml(st.machineName)}</span></td>")
    html.add(fmt"<td class='text-highlight'>{st.buildingCount:.2f}</td>")
    html.add(fmt"<td><span class='clock-badge'>{escapeHtml(st.clockConfig)}</span></td>")
    html.add(fmt"<td>{st.powerMW:.1f} MW</td>")

    # Inputs
    var inList: seq[string] = @[]
    for inIt, amt in st.inputs:
      inList.add(fmt"{amt:.1f} {getItemName(inIt)}")
    let inText = inList.join(", ")
    html.add(fmt"<td class='in-col'>{escapeHtml(inText)}</td>")

    # Outputs
    var outList: seq[string] = @[]
    for outIt, amt in st.outputs:
      outList.add(fmt"{amt:.1f} {getItemName(outIt)}")
    let outText = outList.join(", ")
    html.add(fmt"<td class='out-col'>{escapeHtml(outText)}</td>")

    html.add("</tr>")

  html.add("</tbody></table></div>")
  html.add("</div>")
  return html

proc renderGraphTab(): string =
  var html = "<div class='tab-content graph-tab'>"

  # Graph Toolbar
  html.add("<div class='graph-toolbar'>")
  html.add("<div class='graph-view-switches'>")
  let svgActive = if graphViewMode == "svg": "active btn-primary" else: "btn-secondary"
  let boardActive = if graphViewMode == "board": "active btn-primary" else: "btn-secondary"
  html.add(fmt"<button id='btn-view-svg' class='ficsit-btn btn-sm {svgActive}'>🌿 Diagrama DAG</button>")
  html.add(fmt"<button id='btn-view-board' class='ficsit-btn btn-sm {boardActive}'>📋 Columnas por Etapas</button>")
  html.add("</div>")

  if graphViewMode == "svg":
    html.add("<div class='graph-action-btns'>")
    html.add("<button id='btn-reset-layout' class='ficsit-btn btn-secondary btn-sm' title='Restablecer posiciones originales'>🔄 Reset Layout</button>")
    html.add("<button id='btn-zoom-in' class='ficsit-btn btn-secondary btn-sm' title='Acercar'>🔍 +</button>")
    html.add("<button id='btn-zoom-out' class='ficsit-btn btn-secondary btn-sm' title='Alejar'>🔍 -</button>")
    html.add("<button id='btn-zoom-reset' class='ficsit-btn btn-secondary btn-sm' title='Restablecer zoom al 100%'>100%</button>")
    html.add("</div>")

  html.add("</div>") # graph-toolbar

  if graphViewMode == "svg":
    html.add("<div class='graph-hint' style='margin-bottom: 12px;'>")
    html.add("<span>💡 <strong>Interacción FICSIT:</strong> Arrastra cualquier nodo con el ratón para ordenar el diagrama libremente. Pasa el cursor sobre un nodo para iluminar sus conexiones.</span>")
    html.add("</div>")
    html.add("<div class='svg-viewport' id='svg-container'>")
    html.add(renderSvgGraph(currentPlan))
    html.add("</div>")
  else:
    html.add(renderStageBreakdown(currentPlan))

  html.add("</div>") # tab-content
  return html

proc renderByproductsTab(): string =
  var html = "<div class='tab-content byproducts-tab'>"
  html.add("<div class='byproduct-header'>")
  html.add("<h3>♻️ Byproducts, Recycling Loops & AWESOME Sink Analysis</h3>")
  html.add("<p>Satisfactory has complex multi-output recipes (such as Aluminum scrap water loops, Oil refining Heavy Oil Residue / Polymer Resin, Nuclear waste, and Rocket fuel). The linear programming solver automatically prioritizes feeding byproducts back into production before mining fresh raw resources.</p>")
  html.add("</div>")

  if currentPlan.byproducts.len == 0:
    html.add("<div class='ficsit-alert alert-success'>✅ <strong>Zero Waste Factory:</strong> All intermediate byproducts are 100% consumed and recycled internally within the production line!</div>")
  else:
    html.add("<table class='ficsit-table'>")
    html.add("<thead><tr><th>Surplus Item</th><th>Surplus Rate (per min)</th><th>Handling Status</th><th>FICSIT Directive</th></tr></thead>")
    html.add("<tbody>")
    for sur in currentPlan.byproducts:
      html.add("<tr>")
      html.add(fmt"<td><strong>{escapeHtml(sur.itemName)}</strong></td>")
      html.add(fmt"<td class='text-bold text-highlight'>+{sur.rate:.2f} / min</td>")
      html.add(fmt"<td><span class='status-pill'>{escapeHtml(sur.status)}</span></td>")
      let directive = if sur.itemId == "water":
                        "Loop water back into Alumina Solution with VIP junction or flush excess into Coal Power."
                      elif sur.itemId == "polymer-resin":
                        "Convert into Plastic/Rubber in a secondary Refinery or route to AWESOME Sink."
                      elif sur.itemId == "heavy-oil-residue":
                        "Refine into Petroleum Coke or Diluted Fuel, or package and sink."
                      else:
                        "Send overflow via Smart Splitter (Overflow) to AWESOME Sink for FICSIT coupons."
      html.add(fmt"<td>{escapeHtml(directive)}</td>")
      html.add("</tr>")
    html.add("</tbody></table>")

  html.add("</div>")
  return html

proc renderAlternatesTab(): string =
  var html = "<div class='tab-content alternates-tab'>"
  html.add("<div class='alternates-header'>")
  html.add("<div>")
  html.add("<h3>🛠️ Satisfactory 1.0 Alternate Recipes Manager</h3>")
  html.add("<p>Toggle alternate recipes discovered from Hard Drives in Crash Sites. The optimizer automatically incorporates enabled recipes to minimize machines and raw resources.</p>")
  html.add("</div>")
  html.add("<div class='alts-actions'>")
  html.add("<button id='btn-enable-all-alts' class='ficsit-btn btn-secondary'>Enable All Alternates</button>")
  html.add("<button id='btn-disable-all-alts' class='ficsit-btn btn-secondary'>Disable All Alternates (Standard Only)</button>")
  html.add("</div>")
  html.add("</div>")

  # Search box
  html.add("<div class='search-bar'>")
  html.add(fmt"<input id='alt-search-input' type='text' placeholder='Search alternate recipes by name or product...' value='{escapeHtml(altSearchQuery)}' class='ficsit-input' />")
  html.add("</div>")

  # Grid of alternate recipe cards
  html.add("<div class='alts-grid'>")
  var altList: seq[Recipe] = @[]
  for idStr in alternateRecipeIds:
    if allRecipes.hasKey(idStr):
      altList.add(allRecipes[idStr])

  altList.sort(proc(a, b: Recipe): int = cmp(a.name, b.name))

  for r in altList:
    let q = altSearchQuery.toLowerAscii()
    if q != "" and not r.name.toLowerAscii().contains(q) and not r.id.toLowerAscii().contains(q):
      continue

    let isEnabled = enabledAlternates.contains(r.id)
    let checkedStr = if isEnabled: "checked" else: ""

    let cardClass = if isEnabled: "alt-card active" else: "alt-card"
    html.add("<div class='" & cardClass & "'>")
    html.add("<div class='alt-card-header'>")
    html.add(fmt"<label class='checkbox-container'><input type='checkbox' class='alt-checkbox' data-recipe-id='{r.id}' {checkedStr} /><span class='checkmark'></span> <strong>{escapeHtml(r.name)}</strong></label>")
    let mach = if r.producers.len > 0: getMachineName(r.producers[0]) else: "Assembler"
    html.add(fmt"<span class='alt-machine'>{escapeHtml(mach)}</span>")
    html.add("</div>")

    # Inputs & outputs
    html.add("<div class='alt-details'>")
    var inList: seq[string] = @[]
    for inIt, amt in r.inputs:
      inList.add(fmt"{amt:.0f}x {getItemName(inIt)}")
    var outList: seq[string] = @[]
    for outIt, amt in r.outputs:
      outList.add(fmt"{amt:.0f}x {getItemName(outIt)}")

    let inText = inList.join(", ")
    let outText = outList.join(", ")
    let outRate = if r.outputs.len > 0: 60.0 / r.time * r.outputs.values().toSeq()[0] else: 60.0 / r.time

    html.add("<div class='alt-io'><span class='io-label'>IN:</span> " & escapeHtml(inText) & "</div>")
    html.add(fmt"<div class='alt-io'><span class='io-label'>OUT:</span> {escapeHtml(outText)} ({outRate:.1f}/m)</div>")
    html.add("</div>")
    html.add("</div>")

  html.add("</div>") # alts-grid
  html.add("</div>") # tab-content
  return html

proc renderDatabaseTab(): string =
  var html = "<div class='tab-content db-tab'>"
  html.add("<div class='db-header'>")
  html.add("<h3>📖 Satisfactory 1.0 Item & Recipe Encyclopedia</h3>")
  html.add("<p>Full dataset extracted from Satisfactory 1.0 community resources (including Phase 5 quantum items, converter recipes, and power shards).</p>")
  html.add("<input id='db-search-input' type='text' placeholder='Search items and recipes...' value='" & escapeHtml(dbSearchQuery) & "' class='ficsit-input db-search' />")
  html.add("</div>")

  html.add("<div class='table-responsive'>")
  html.add("<table class='ficsit-table'>")
  html.add("<thead><tr><th>Item</th><th>Category</th><th>Craft Recipes</th><th>Producers</th></tr></thead>")
  html.add("<tbody>")

  var count = 0
  let maxDisplay = if dbSearchQuery != "": 100 else: 40

  for idStr in craftableItemIds:
    let it = allItems[idStr]
    let q = dbSearchQuery.toLowerAscii()
    if q != "" and not it.name.toLowerAscii().contains(q) and not it.category.toLowerAscii().contains(q):
      continue

    inc count
    if count > maxDisplay:
      break

    # Instant O(1) lookup
    let recs = getRecipesForItem(idStr)
    var recNames: seq[string] = @[]
    var prods: seq[string] = @[]
    for r in recs:
      let altTag = if r.isAlternate: " (Alt)" else: ""
      recNames.add(r.name & altTag)
      for p in r.producers:
        let mName = getMachineName(p)
        if not prods.contains(mName):
          prods.add(mName)

    let recText = recNames.join(" • ")
    let prodText = prods.join(", ")
    html.add("<tr>")
    html.add(fmt"<td><span class='table-badge' style='border-left: 4px solid {it.color};'>{escapeHtml(it.name)}</span></td>")
    html.add(fmt"<td><span class='cat-tag'>{escapeHtml(it.category)}</span></td>")
    html.add("<td>" & escapeHtml(recText) & "</td>")
    html.add("<td>" & escapeHtml(prodText) & "</td>")
    html.add("</tr>")

  html.add("</tbody></table></div>")
  if count > maxDisplay:
    html.add(fmt"<div class='empty-placeholder' style='padding: 12px; margin-top: 10px; font-size: 13px;'>Showing first {maxDisplay} items. Use the search bar above to filter by item name or category.</div>")
  html.add("</div>")
  return html

proc renderTabBar(): string =
  var html = "<div class='ficsit-tabs'>"
  proc addTabBtn(tabId, icon, label: string) =
    let activeClass = if currentTab == tabId: "active" else: ""
    html.add(fmt"<button class='tab-btn {activeClass}' data-tab='{tabId}'>{icon} {label}</button>")

  addTabBtn("overview", "📊", "Factory Overview")
  addTabBtn("steps", "🏭", "Production Steps")
  addTabBtn("graph", "🌿", "Flowchart (DAG)")
  addTabBtn("byproducts", "♻️", "Byproducts & Sinks")
  addTabBtn("alternates", "🛠️", "Alternate Recipes (" & $enabledAlternates.len & ")")
  addTabBtn("database", "📖", "1.0 Encyclopedia")
  html.add("</div>")
  return html

proc updatePlan*() =
  currentPlan = planProduction(currentTargets, enabledAlternates)

proc initGraphInteractions() =
  {.emit: """
  var svg = document.getElementById("ficsit-dag-svg");
  if (!svg) return;

  var currentScale = 1.0;
  var origWidth = parseFloat(svg.getAttribute("data-width") || "1200");

  function addCls(el, cls) {
    if (!el) return;
    if (el.classList) el.classList.add(cls);
    else {
      var c = el.getAttribute("class") || "";
      if (c.indexOf(cls) === -1) el.setAttribute("class", (c + " " + cls).trim());
    }
  }

  function remCls(el, cls) {
    if (!el) return;
    if (el.classList) el.classList.remove(cls);
    else {
      var c = el.getAttribute("class") || "";
      el.setAttribute("class", c.replace(new RegExp("(^|\\s+)" + cls + "(\\s+|$)", "g"), " ").trim());
    }
  }

  function updateEdge(edge, isOutgoing, nx, ny) {
    var x1, y1, x2, y2;
    if (isOutgoing) {
      x1 = nx + 240.0;
      y1 = ny + 38.0;
      x2 = parseFloat(edge.getAttribute("data-x2") || "0");
      y2 = parseFloat(edge.getAttribute("data-y2") || "0");
      edge.setAttribute("data-x1", x1.toFixed(1));
      edge.setAttribute("data-y1", y1.toFixed(1));
    } else {
      x1 = parseFloat(edge.getAttribute("data-x1") || "0");
      y1 = parseFloat(edge.getAttribute("data-y1") || "0");
      x2 = nx;
      y2 = ny + 38.0;
      edge.setAttribute("data-x2", x2.toFixed(1));
      edge.setAttribute("data-y2", y2.toFixed(1));
    }

    var d;
    if (x2 >= x1 - 10.0) {
      var dx = Math.max(45.0, (x2 - x1) * 0.5);
      d = "M " + x1.toFixed(1) + " " + y1.toFixed(1) + " C " + (x1 + dx).toFixed(1) + " " + y1.toFixed(1) + ", " + (x2 - dx).toFixed(1) + " " + y2.toFixed(1) + ", " + x2.toFixed(1) + " " + y2.toFixed(1);
    } else {
      var loopY = Math.max(y1, y2) + 50.0;
      d = "M " + x1.toFixed(1) + " " + y1.toFixed(1) + " C " + (x1 + 60.0).toFixed(1) + " " + loopY.toFixed(1) + ", " + (x2 - 60.0).toFixed(1) + " " + loopY.toFixed(1) + ", " + x2.toFixed(1) + " " + y2.toFixed(1);
    }
    edge.setAttribute("d", d);

    var eIdx = edge.getAttribute("data-edge-idx");
    var lbl = svg.querySelector("#label-" + eIdx);
    if (lbl) {
      var bw = parseFloat(lbl.getAttribute("data-w") || "60");
      var bh = parseFloat(lbl.getAttribute("data-h") || "20");
      var mx = (x1 + x2) / 2.0 - bw / 2.0;
      var my = (y1 + y2) / 2.0 - bh / 2.0;
      lbl.setAttribute("transform", "translate(" + mx.toFixed(1) + ", " + my.toFixed(1) + ")");
    }
  }

  function updateNodeEdges(nodeId, nx, ny) {
    var outEdges = svg.querySelectorAll("path.flow-edge[data-from='" + nodeId + "']");
    for (var i = 0; i < outEdges.length; i++) {
      updateEdge(outEdges[i], true, nx, ny);
    }
    var inEdges = svg.querySelectorAll("path.flow-edge[data-to='" + nodeId + "']");
    for (var j = 0; j < inEdges.length; j++) {
      updateEdge(inEdges[j], false, nx, ny);
    }
  }

  // Setup Global Window Drag Listeners once
  if (!window.__ficsit_window_listeners_bound) {
    window.__ficsit_window_listeners_bound = true;
    window.addEventListener("mousemove", function(e) {
      if (!window.__ficsit_active_drag) return;
      var d = window.__ficsit_active_drag;
      var ctm = d.svg.getScreenCTM();
      if (!ctm) return;
      var pt = d.svg.createSVGPoint();
      pt.x = e.clientX;
      pt.y = e.clientY;
      var svgPt = pt.matrixTransform(ctm.inverse());
      var dx = svgPt.x - d.startSvgX;
      var dy = svgPt.y - d.startSvgY;
      var nx = d.startNodeX + dx;
      var ny = d.startNodeY + dy;
      d.node.setAttribute("transform", "translate(" + nx.toFixed(1) + ", " + ny.toFixed(1) + ")");
      d.node.setAttribute("data-x", nx.toFixed(1));
      d.node.setAttribute("data-y", ny.toFixed(1));
      if (d.updateNodeEdges) {
        d.updateNodeEdges(d.nodeId, nx, ny);
      }
    });

    window.addEventListener("mouseup", function() {
      if (window.__ficsit_active_drag && window.__ficsit_active_drag.node) {
        window.__ficsit_active_drag.node.style.cursor = "grab";
      }
      window.__ficsit_active_drag = null;
    });
  }

  // Node Drag Start on current SVG
  svg.addEventListener("mousedown", function(e) {
    var target = e.target;
    var node = target.closest ? target.closest(".flow-node") : ((target.parentElement && target.parentElement.closest) ? target.parentElement.closest(".flow-node") : null);
    if (!node) return;
    e.preventDefault();
    var ctm = svg.getScreenCTM();
    if (!ctm) return;
    var pt = svg.createSVGPoint();
    pt.x = e.clientX;
    pt.y = e.clientY;
    var svgPt = pt.matrixTransform(ctm.inverse());
    var startNodeX = parseFloat(node.getAttribute("data-x") || "0");
    var startNodeY = parseFloat(node.getAttribute("data-y") || "0");
    var nodeId = node.getAttribute("data-id");
    node.style.cursor = "grabbing";

    window.__ficsit_active_drag = {
      svg: svg,
      node: node,
      nodeId: nodeId,
      startSvgX: svgPt.x,
      startSvgY: svgPt.y,
      startNodeX: startNodeX,
      startNodeY: startNodeY,
      updateNodeEdges: updateNodeEdges
    };
  });

  // Hover Highlighting
  var nodes = svg.querySelectorAll(".flow-node");
  for (var k = 0; k < nodes.length; k++) {
    (function(n) {
      n.addEventListener("mouseenter", function() {
        if (window.__ficsit_active_drag) return;
        var nId = n.getAttribute("data-id");
        addCls(svg, "ficsit-dimmed");
        addCls(n, "ficsit-highlight");

        var outs = svg.querySelectorAll("path.flow-edge[data-from='" + nId + "']");
        for (var o = 0; o < outs.length; o++) {
          addCls(outs[o], "ficsit-edge-highlight");
          var eIdx = outs[o].getAttribute("data-edge-idx");
          var lbl = svg.querySelector("#label-" + eIdx);
          if (lbl) addCls(lbl, "ficsit-edge-highlight");
          var toId = outs[o].getAttribute("data-to");
          var partner = svg.querySelector("#node-" + toId);
          if (partner) addCls(partner, "ficsit-partner-highlight");
        }

        var ins = svg.querySelectorAll("path.flow-edge[data-to='" + nId + "']");
        for (var p = 0; p < ins.length; p++) {
          addCls(ins[p], "ficsit-edge-highlight");
          var eIdx2 = ins[p].getAttribute("data-edge-idx");
          var lbl2 = svg.querySelector("#label-" + eIdx2);
          if (lbl2) addCls(lbl2, "ficsit-edge-highlight");
          var fromId = ins[p].getAttribute("data-from");
          var partner2 = svg.querySelector("#node-" + fromId);
          if (partner2) addCls(partner2, "ficsit-partner-highlight");
        }
      });

      n.addEventListener("mouseleave", function() {
        if (window.__ficsit_active_drag) return;
        remCls(svg, "ficsit-dimmed");
        var highlighted = svg.querySelectorAll(".ficsit-highlight, .ficsit-partner-highlight, .ficsit-edge-highlight");
        for (var h = 0; h < highlighted.length; h++) {
          remCls(highlighted[h], "ficsit-highlight");
          remCls(highlighted[h], "ficsit-partner-highlight");
          remCls(highlighted[h], "ficsit-edge-highlight");
        }
      });
    })(nodes[k]);
  }

  // Zoom controls
  function applyZoom(scale) {
    currentScale = Math.max(0.35, Math.min(2.5, scale));
    svg.style.width = (origWidth * currentScale).toFixed(0) + "px";
    svg.style.minWidth = (origWidth * currentScale).toFixed(0) + "px";
    var resetBtn = document.getElementById("btn-zoom-reset");
    if (resetBtn) {
      resetBtn.textContent = Math.round(currentScale * 100) + "%";
    }
  }

  var btnIn = document.getElementById("btn-zoom-in");
  if (btnIn) {
    btnIn.onclick = function(e) { e.preventDefault(); applyZoom(currentScale + 0.15); };
  }
  var btnOut = document.getElementById("btn-zoom-out");
  if (btnOut) {
    btnOut.onclick = function(e) { e.preventDefault(); applyZoom(currentScale - 0.15); };
  }
  var btnResetZoom = document.getElementById("btn-zoom-reset");
  if (btnResetZoom) {
    btnResetZoom.onclick = function(e) { e.preventDefault(); applyZoom(1.0); };
  }

  // Reset layout button
  var btnResetLayout = document.getElementById("btn-reset-layout");
  if (btnResetLayout) {
    btnResetLayout.onclick = function(e) {
      e.preventDefault();
      for (var r = 0; r < nodes.length; r++) {
        var nd = nodes[r];
        var ox = parseFloat(nd.getAttribute("data-orig-x") || "0");
        var oy = parseFloat(nd.getAttribute("data-orig-y") || "0");
        nd.setAttribute("transform", "translate(" + ox.toFixed(1) + ", " + oy.toFixed(1) + ")");
        nd.setAttribute("data-x", ox.toFixed(1));
        nd.setAttribute("data-y", oy.toFixed(1));
        var nId = nd.getAttribute("data-id");
        updateNodeEdges(nId, ox, oy);
      }
    };
  }
  """.}

proc renderApp*() =
  let app = document.getElementById(cstring("app"))
  if app == nil: return

  var html = ""
  
  # FICSIT Navigation Header
  html.add("<header class='ficsit-header'>")
  html.add("<div class='header-brand'>")
  html.add("<div class='ficsit-stripe'></div>")
  html.add("<div class='brand-text'>")
  html.add("<h1 class='brand-title'>FICSIT PRODUCTION OPTIMIZER</h1>")
  html.add("<span class='brand-subtitle'>SATISFACTORY 1.0 FACTORY PLANNER & LINEAR SOLVER</span>")
  html.add("</div>")
  html.add("</div>")

  # Live top stats
  html.add("<div class='header-stats'>")
  let pwrText = if currentPlan.success: fmt"⚡ {currentPlan.totalPowerMW:.1f} MW" else: "⚡ -- MW"
  let bldText = if currentPlan.success: fmt"🏭 {currentPlan.totalBuildings:.1f} Bldgs" else: "🏭 -- Bldgs"
  html.add(fmt"<div class='stat-badge badge-pwr'>{pwrText}</div>")
  html.add(fmt"<div class='stat-badge badge-bld'>{bldText}</div>")
  html.add("</div>")
  html.add("</header>")

  # Main Content Wrapper
  html.add("<main class='ficsit-main'>")
  
  # Target Builder Section
  html.add(renderTargetsBar())

  # Tab Bar Navigation
  html.add(renderTabBar())

  # Active Tab Content
  case currentTab
  of "overview": html.add(renderOverviewTab())
  of "steps": html.add(renderStepsTab())
  of "graph": html.add(renderGraphTab())
  of "byproducts": html.add(renderByproductsTab())
  of "alternates": html.add(renderAlternatesTab())
  of "database": html.add(renderDatabaseTab())
  else: html.add(renderOverviewTab())

  html.add("</main>")

  # Footer
  html.add("<footer class='ficsit-footer'>")
  html.add("<span>FICSIT Inc. Property • Compiling Nim ➔ JavaScript • Satisfactory 1.0 Linear Programming Simplex Engine</span>")
  html.add("</footer>")

  app.innerHTML = cstring(html)

  if currentTab == "graph" and graphViewMode == "svg":
    initGraphInteractions()

var eventsBound = false

proc bindGlobalEvents*() =
  if eventsBound: return
  eventsBound = true

  # 1. Global Click delegation
  document.addEventListener(cstring("click"), proc(e: Event) =
    let target = e.target
    if target == nil: return

    # A. Tab button click
    let tabBtn = findClosest(target, cstring(".tab-btn"))
    if tabBtn != nil:
      let tabId = tabBtn.getAttribute(cstring("data-tab"))
      if tabId != nil and $tabId != "":
        currentTab = $tabId
        renderApp()
        return

    # A2. Graph view mode switches
    let viewSvgBtn = findClosest(target, cstring("#btn-view-svg"))
    if viewSvgBtn != nil:
      graphViewMode = "svg"
      renderApp()
      return

    let viewBoardBtn = findClosest(target, cstring("#btn-view-board"))
    if viewBoardBtn != nil:
      graphViewMode = "board"
      renderApp()
      return

    # B. Add Target button
    let addBtn = findClosest(target, cstring("#btn-add-target"))
    if addBtn != nil:
      let sel = cast[SelectElement](document.getElementById(cstring("target-item-select")))
      let rateIn = cast[InputElement](document.getElementById(cstring("target-rate-input")))
      if sel != nil and rateIn != nil:
        let itemId = $sel.value
        let rateVal = parseFloat($rateIn.value)
        if rateVal > 0.0 and itemId != "":
          var found = false
          for i in 0 ..< currentTargets.len:
            if currentTargets[i].itemId == itemId:
              currentTargets[i].rate = rateVal
              found = true
              break
          if not found:
            currentTargets.add(FactoryTarget(itemId: itemId, rate: rateVal))
          updatePlan()
          renderApp()
          return

    # C. Clear All targets
    let clearBtn = findClosest(target, cstring("#btn-clear-targets"))
    if clearBtn != nil:
      currentTargets = @[]
      updatePlan()
      renderApp()
      return

    # D. Remove chip
    let removeBtn = findClosest(target, cstring(".chip-remove-btn"))
    if removeBtn != nil:
      let idxStr = removeBtn.getAttribute(cstring("data-idx"))
      if idxStr != nil:
        let idx = parseInt($idxStr)
        if idx >= 0 and idx < currentTargets.len:
          currentTargets.delete(idx)
          updatePlan()
          renderApp()
          return

    # E. Step chip rate (+5 / -5)
    let stepBtn = findClosest(target, cstring(".chip-step-btn"))
    if stepBtn != nil:
      let idxStr = stepBtn.getAttribute(cstring("data-idx"))
      let actStr = stepBtn.getAttribute(cstring("data-action"))
      if idxStr != nil:
        let idx = parseInt($idxStr)
        if idx >= 0 and idx < currentTargets.len:
          if $actStr == "inc":
            currentTargets[idx].rate += 5.0
          elif $actStr == "dec":
            currentTargets[idx].rate = max(1.0, currentTargets[idx].rate - 5.0)
          updatePlan()
          renderApp()
          return

    # F. Enable all alternates
    let enableAllBtn = findClosest(target, cstring("#btn-enable-all-alts"))
    if enableAllBtn != nil:
      for idStr in alternateRecipeIds:
        enabledAlternates.incl(idStr)
      updatePlan()
      renderApp()
      return

    # G. Disable all alternates
    let disableAllBtn = findClosest(target, cstring("#btn-disable-all-alts"))
    if disableAllBtn != nil:
      enabledAlternates.clear()
      updatePlan()
      renderApp()
      return
  )

  # 2. Global Change delegation
  document.addEventListener(cstring("change"), proc(e: Event) =
    let target = e.target
    if target == nil: return

    # A. Alternate recipe checkbox
    let altBox = findClosest(target, cstring(".alt-checkbox"))
    if altBox != nil:
      let box = cast[InputElement](altBox)
      let rId = box.getAttribute(cstring("data-recipe-id"))
      if rId != nil:
        if box.checked:
          enabledAlternates.incl($rId)
        else:
          enabledAlternates.excl($rId)
        updatePlan()
        renderApp()
        return

    # B. Preset selector
    let presetSel = findClosest(target, cstring("#preset-select"))
    if presetSel != nil:
      let sel = cast[SelectElement](presetSel)
      let pid = $sel.value
      if pid != "":
        for p in getPresets():
          if p.id == pid:
            currentTargets = p.targets
            if p.enableAlternates:
              for a in p.enabledAlts:
                enabledAlternates.incl(a)
            updatePlan()
            renderApp()
            return
  )

  # 3. Global Input delegation
  document.addEventListener(cstring("input"), proc(e: Event) =
    let target = e.target
    if target == nil: return

    let altSearch = findClosest(target, cstring("#alt-search-input"))
    if altSearch != nil:
      altSearchQuery = $cast[InputElement](altSearch).value
      renderApp()
      let refocused = document.getElementById(cstring("alt-search-input"))
      if refocused != nil:
        let inp = cast[InputElement](refocused)
        inp.focus()
        inp.setSelectionRange(altSearchQuery.len, altSearchQuery.len)
      return

    let dbSearch = findClosest(target, cstring("#db-search-input"))
    if dbSearch != nil:
      dbSearchQuery = $cast[InputElement](dbSearch).value
      renderApp()
      let refocused = document.getElementById(cstring("db-search-input"))
      if refocused != nil:
        let inp = cast[InputElement](refocused)
        inp.focus()
        inp.setSelectionRange(dbSearchQuery.len, dbSearchQuery.len)
      return
  )

proc initUI*() =
  let p = getPresets()[0]
  currentTargets = p.targets
  bindGlobalEvents()
  updatePlan()
  renderApp()
