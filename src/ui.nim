import std/[dom, strutils, strformat, tables, sets, sequtils, algorithm, math, json]
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

proc getStorageItem(key: cstring): cstring =
  var res: cstring = nil
  {.emit: """
    try {
      `res` = window.localStorage ? window.localStorage.getItem(`key`) : null;
    } catch(e) {
      `res` = null;
    }
  """.}
  return res

proc setStorageItem(key: cstring, val: cstring) =
  {.emit: """
    try {
      if (window.localStorage) {
        window.localStorage.setItem(`key`, `val`);
      }
    } catch(e) {}
  """.}

proc generateFactoryId(): string =
  var res: cstring
  {.emit: """
    `res` = "factory-" + Date.now().toString(36) + "-" + Math.random().toString(36).substring(2, 6);
  """.}
  return $res

var
  factories: seq[Factory] = @[]
  activeFactoryId: string = ""
  currentPlan: FactoryPlan
  currentTab: string = "production" # "production", "graph", "alternates", "database"
  graphViewMode: string = "svg"     # "svg" or "board"
  altSearchQuery: string = ""
  dbSearchQuery: string = ""
  eventsBound = false

proc escapeHtml(s: string): string =
  result = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

proc getActiveFactoryIdx(): int =
  for i in 0 ..< factories.len:
    if factories[i].id == activeFactoryId:
      return i
  return 0

proc getActiveFactory(): ptr Factory =
  if factories.len == 0: return nil
  let idx = getActiveFactoryIdx()
  return addr factories[idx]

proc saveFactories() =
  try:
    let jsonNode = %factories
    setStorageItem(cstring("satisfactory_factories_v2"), cstring($jsonNode))
    setStorageItem(cstring("satisfactory_active_factory_v2"), cstring(activeFactoryId))
  except Exception:
    discard

proc getAllRawResourceIds(): seq[string] =
  result = @[]
  for r in rawResourceIds:
    result.add(r)
  result.sort(proc(a, b: string): int = cmp(getItemName(a), getItemName(b)))

proc createDefaultFactory(idStr, nameStr: string): Factory =
  return Factory(
    id: idStr,
    name: nameStr,
    targets: @[
      FactoryTarget(itemId: "rotor", rate: 10.0),
      FactoryTarget(itemId: "smart-plating", rate: 2.0)
    ],
    allowedRaw: getAllRawResourceIds(),
    enabledAlts: @[],
    disabledRecipes: @[]
  )

proc loadFactories(): bool =
  let raw = getStorageItem(cstring("satisfactory_factories_v2"))
  if raw != nil and $raw != "":
    try:
      let parsed = parseJson($raw)
      factories = to(parsed, seq[Factory])
      let act = getStorageItem(cstring("satisfactory_active_factory_v2"))
      if act != nil and $act != "":
        activeFactoryId = $act
      if factories.len > 0:
        if activeFactoryId == "" or not factories.anyIt(it.id == activeFactoryId):
          activeFactoryId = factories[0].id
        return true
    except Exception:
      discard
  return false

proc updatePlan*() =
  if factories.len == 0:
    currentPlan = FactoryPlan()
    return
  let idx = getActiveFactoryIdx()
  let f = factories[idx]
  currentPlan = planProduction(
    f.targets,
    f.allowedRaw.toHashSet(),
    f.enabledAlts.toHashSet(),
    f.disabledRecipes.toHashSet()
  )

# Forward declarations
proc renderApp*()
proc initGraphInteractions()

proc renderFactoryBar(): string =
  var html = "<div class='factory-bar'>"
  
  # 1. Factory Tabs
  html.add("<div class='factory-tabs-container'>")
  html.add("<div class='factory-tabs'>")
  for f in factories:
    let isActive = f.id == activeFactoryId
    let actClass = if isActive: "factory-tab active" else: "factory-tab"
    html.add(fmt"<div class='{actClass}' data-factory-id='{f.id}'>")
    html.add(fmt"<span class='factory-tab-name'>{escapeHtml(f.name)}</span>")
    if factories.len > 1:
      html.add(fmt"<button class='btn-tab-close' data-factory-id='{f.id}' title='Eliminar fábrica'>✕</button>")
    html.add("</div>")
  
  html.add("<button id='btn-new-factory' class='btn-new-factory' title='Crear nueva fábrica independiente'>+ Nueva Fábrica</button>")
  html.add("</div>") # factory-tabs
  html.add("</div>") # factory-tabs-container

  # 2. Active Factory Toolbar Actions
  let fPtr = getActiveFactory()
  if fPtr != nil:
    let f = fPtr[]
    html.add("<div class='factory-meta-row'>")
    
    # Inline rename input
    html.add("<div class='factory-name-field'>")
    html.add("<label for='factory-name-input'>Fábrica:</label>")
    html.add(fmt"<input id='factory-name-input' type='text' value='{escapeHtml(f.name)}' class='ficsit-input name-input' placeholder='Nombre de la fábrica...' />")
    html.add("</div>")

    # Action buttons: Duplicate, Delete, Presets
    html.add("<div class='factory-actions-group'>")
    html.add("<button id='btn-duplicate-factory' class='ficsit-btn btn-sm btn-secondary' title='Duplicar esta fábrica con su configuración actual'>📋 Duplicar</button>")
    if factories.len > 1:
      html.add("<button id='btn-delete-factory' class='ficsit-btn btn-sm btn-danger' title='Eliminar esta fábrica'>🗑️ Eliminar</button>")
    
    # Presets dropdown
    html.add("<select id='preset-select' class='ficsit-select select-sm preset-picker'>")
    html.add("<option value=''>-- Cargar Plantilla --</option>")
    for p in getPresets():
      html.add(fmt"<option value='{p.id}'>{escapeHtml(p.name)}</option>")
    html.add("</select>")

    html.add("</div>") # factory-actions-group
    html.add("</div>") # factory-meta-row

  html.add("</div>") # factory-bar
  return html

proc renderFactoryConfig(): string =
  let fPtr = getActiveFactory()
  if fPtr == nil: return ""
  let f = fPtr[]

  var html = "<div class='factory-config-panel'>"

  # Column 1: Production Targets
  html.add("<div class='config-section targets-section'>")
  html.add("<div class='section-header'>")
  html.add("<h4>🎯 Objetivos de Producción</h4>")
  html.add(fmt"<span class='section-subtitle'>{f.targets.len} producto(s) en demanda</span>")
  html.add("</div>")

  # Add product row
  html.add("<div class='target-add-row'>")
  html.add("<select id='target-item-select' class='ficsit-select select-item'>")
  for idStr in craftableItemIds:
    let item = allItems[idStr]
    html.add(fmt"<option value='{idStr}'>{escapeHtml(item.name)} ({item.category})</option>")
  html.add("</select>")
  
  html.add("<div class='rate-input-wrap'>")
  html.add("<input id='target-rate-input' type='number' min='0.1' step='1' value='10' class='ficsit-input rate-input' />")
  html.add("<span class='rate-unit'>/ min</span>")
  html.add("</div>")

  html.add("<button id='btn-add-target' class='ficsit-btn btn-primary btn-sm'>+ Añadir</button>")
  html.add("</div>") # target-add-row

  # Active targets table / chips
  html.add("<div class='active-targets-wrap'>")
  if f.targets.len == 0:
    html.add("<div class='targets-empty-hint'>Sin objetivos. Selecciona un producto arriba y pulsa <strong>+ Añadir</strong> o carga una plantilla.</div>")
  else:
    html.add("<div class='targets-chips-grid'>")
    for idx, t in f.targets:
      let item = allItems.getOrDefault(t.itemId, Item(name: t.itemId, color: "#FA9549"))
      html.add("<div class='target-chip'>")
      html.add(fmt"<span class='chip-stripe' style='background-color: {item.color};'></span>")
      html.add(fmt"<span class='chip-name'>{escapeHtml(item.name)}</span>")
      html.add(fmt"<span class='chip-rate'>{t.rate:.1f} <small>/m</small></span>")
      html.add(fmt"<button class='chip-step-btn' data-action='dec' data-idx='{idx}' title='-5/min'>-5</button>")
      html.add(fmt"<button class='chip-step-btn' data-action='inc' data-idx='{idx}' title='+5/min'>+5</button>")
      html.add(fmt"<button class='chip-remove-btn' data-idx='{idx}' title='Eliminar objetivo'>✕</button>")
      html.add("</div>")
    html.add("</div>")
  html.add("</div>") # active-targets-wrap
  html.add("</div>") # targets-section

  # Column 2: Available Raw Resources at this location
  html.add("<div class='config-section resources-section'>")
  html.add("<div class='section-header'>")
  html.add("<div>")
  html.add("<h4>⛏️ Recursos Naturales Disponibles en esta Ubicación</h4>")
  html.add("<span class='section-subtitle'>Haz clic para deshabilitar recursos que no existan cerca de esta fábrica</span>")
  html.add("</div>")
  html.add("<div class='raw-quick-actions'>")
  html.add("<button id='btn-raw-all' class='btn-text-action'>Todos</button>")
  html.add("<button id='btn-raw-none' class='btn-text-action'>Ninguno</button>")
  html.add("</div>")
  html.add("</div>") # section-header

  # Raw resource pills
  html.add("<div class='raw-pills-grid'>")
  let allRaws = getAllRawResourceIds()
  for rId in allRaws:
    let isAllowed = f.allowedRaw.contains(rId)
    let pillClass = if isAllowed: "raw-pill active" else: "raw-pill disabled"
    let checkSymbol = if isAllowed: "✓" else: "✕"
    let rName = getItemName(rId)
    html.add(fmt"<button class='{pillClass}' data-raw-id='{rId}' title='Alternar disponibilidad de {escapeHtml(rName)}'>")
    html.add(fmt"<span class='raw-pill-icon'>{checkSymbol}</span> ")
    html.add(fmt"<span class='raw-pill-text'>{escapeHtml(rName)}</span>")
    html.add("</button>")
  html.add("</div>") # raw-pills-grid
  html.add("</div>") # resources-section

  html.add("</div>") # factory-config-panel
  return html

proc renderTabBar(): string =
  let fPtr = getActiveFactory()
  let altCount = if fPtr != nil: fPtr[].enabledAlts.len else: 0

  var html = "<div class='ficsit-tabs main-tabs'>"
  proc addTabBtn(tabId, icon, label: string) =
    let activeClass = if currentTab == tabId: "tab-btn active" else: "tab-btn"
    html.add(fmt"<button class='{activeClass}' data-tab='{tabId}'>{icon} {label}</button>")

  addTabBtn("production", "📋", "Plan de Producción")
  addTabBtn("graph", "📈", "Diagrama de Flujo")
  addTabBtn("alternates", "🛠️", "Recetas Alternativas (" & $altCount & ")")
  addTabBtn("database", "📖", "Enciclopedia 1.0")
  html.add("</div>")
  return html

proc renderProductionTab(): string =
  var html = "<div class='tab-content production-tab'>"

  if not currentPlan.success:
    html.add(fmt"<div class='ficsit-alert alert-error'>⚠️ <strong>No se pudo calcular el plan:</strong> {escapeHtml(currentPlan.errorMessage)}</div>")
    return html & "</div>"

  let fPtr = getActiveFactory()
  if fPtr == nil or fPtr[].targets.len == 0:
    html.add("<div class='empty-placeholder'>Esta fábrica no tiene objetivos de producción. Añade productos arriba para calcular las materias primas y las máquinas necesarias.</div>")
    return html & "</div>"

  # Power consumption summary badge
  html.add("<div class='production-summary-strip'>")
  html.add(fmt"<span class='power-summary'>⚡ Potencia requerida: <strong>{currentPlan.totalPowerMW:.1f} MW</strong></span>")
  html.add("</div>")

  # Table 1: Raw Materials Required
  html.add("<div class='content-card'>")
  html.add("<div class='card-header'>")
  html.add("<h3>⛏️ Materias Primas Requeridas (por minuto)</h3>")
  html.add("</div>")
  html.add("<div class='table-responsive'>")
  html.add("<table class='ficsit-table'>")
  html.add("<thead><tr><th>Recurso</th><th>Extracción Requerida</th><th>Sugerencia de Mineros / Extractores</th></tr></thead>")
  html.add("<tbody>")
  for req in currentPlan.rawResources:
    let color = getItemColor(req.itemId)
    html.add("<tr>")
    html.add(fmt"<td><span class='table-badge' style='border-left: 4px solid {color};'>{escapeHtml(req.itemName)}</span></td>")
    html.add(fmt"<td class='text-bold'>{req.rate:.1f} / min</td>")
    html.add(fmt"<td><span class='miner-tag'>{escapeHtml(req.suggestedMiners)}</span></td>")
    html.add("</tr>")
  html.add("</tbody></table></div>")
  html.add("</div>") # content-card

  # Table 2: Production Lines & Machines
  html.add("<div class='content-card' style='margin-top: 18px;'>")
  html.add("<div class='card-header'>")
  html.add("<h3>🏭 Líneas de Producción y Máquinas</h3>")
  html.add("</div>")
  html.add("<div class='table-responsive'>")
  html.add("<table class='ficsit-table'>")
  html.add("<thead><tr>")
  html.add("<th>Receta</th>")
  html.add("<th>Edificio</th>")
  html.add("<th>Cantidad</th>")
  html.add("<th>Ajuste de Reloj</th>")
  html.add("<th>Potencia</th>")
  html.add("<th>Entradas (por min)</th>")
  html.add("<th>Salidas (por min)</th>")
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
  html.add("</div>") # content-card

  # Table 3: Byproducts & Surplus (only rendered if there are byproducts!)
  if currentPlan.byproducts.len > 0:
    html.add("<div class='content-card' style='margin-top: 18px;'>")
    html.add("<div class='card-header'>")
    html.add("<h3>♻️ Subproductos y Excedentes de Producción</h3>")
    html.add("</div>")
    html.add("<div class='table-responsive'>")
    html.add("<table class='ficsit-table'>")
    html.add("<thead><tr><th>Subproducto</th><th>Tasa Sobrante</th><th>Directriz de Manejo</th></tr></thead>")
    html.add("<tbody>")
    for sur in currentPlan.byproducts:
      html.add("<tr>")
      html.add(fmt"<td><strong>{escapeHtml(sur.itemName)}</strong></td>")
      html.add(fmt"<td class='text-bold text-highlight'>+{sur.rate:.2f} / min</td>")
      let directive = if sur.itemId == "water":
                        "Recircular al inicio del proceso (Alúmina) mediante unión en T o purgar a Generador de Carbón."
                      elif sur.itemId == "polymer-resin":
                        "Convertir en Plástico/Goma en una refinería secundaria o enviar a AWESOME Sink."
                      elif sur.itemId == "heavy-oil-residue":
                        "Procesar a Coque de Petróleo o Combustible Diluido, o empaquetar y hundir."
                      else:
                        "Derivar excedente mediante Divisor Inteligente (Desbordamiento) a Triturador AWESOME."
      html.add(fmt"<td>{escapeHtml(directive)}</td>")
      html.add("</tr>")
    html.add("</tbody></table></div>")
    html.add("</div>")

  html.add("</div>") # tab-content
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
    html.add("<span>💡 <strong>Interacción:</strong> Arrastra cualquier nodo con el ratón para ordenar el diagrama libremente. Pasa el cursor sobre un nodo para iluminar sus conexiones.</span>")
    html.add("</div>")
    html.add("<div class='svg-viewport' id='svg-container'>")
    html.add(renderSvgGraph(currentPlan))
    html.add("</div>")
  else:
    html.add(renderStageBreakdown(currentPlan))

  html.add("</div>") # tab-content
  return html

proc renderAlternatesTab(): string =
  let fPtr = getActiveFactory()
  let enabledAlts = if fPtr != nil: fPtr[].enabledAlts.toHashSet() else: initHashSet[string]()

  var html = "<div class='tab-content alternates-tab'>"
  html.add("<div class='alternates-header'>")
  html.add("<div>")
  html.add("<h3>🛠️ Recetas Alternativas para esta Fábrica</h3>")
  html.add("<span class='section-subtitle'>Activa las recetas de discos duros permitidas en esta fábrica. El optimizador las utilizará si reducen recursos o máquinas.</span>")
  html.add("</div>")
  html.add("<div class='alts-actions'>")
  html.add("<button id='btn-enable-all-alts' class='ficsit-btn btn-secondary btn-sm'>Activar Todas</button>")
  html.add("<button id='btn-disable-all-alts' class='ficsit-btn btn-secondary btn-sm'>Solo Estándar</button>")
  html.add("</div>")
  html.add("</div>")

  # Search box
  html.add("<div class='search-bar'>")
  html.add(fmt"<input id='alt-search-input' type='text' placeholder='Buscar receta alternativa...' value='{escapeHtml(altSearchQuery)}' class='ficsit-input' />")
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

    let isEnabled = enabledAlts.contains(r.id)
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
  html.add("<div>")
  html.add("<h3>📖 Enciclopedia Satisfactory 1.0</h3>")
  html.add("<span class='section-subtitle'>Consulta instantánea de recetas, máquinas y proporciones del juego completo</span>")
  html.add("</div>")
  html.add("<input id='db-search-input' type='text' placeholder='Buscar producto o categoría...' value='" & escapeHtml(dbSearchQuery) & "' class='ficsit-input db-search' />")
  html.add("</div>")

  html.add("<div class='table-responsive'>")
  html.add("<table class='ficsit-table'>")
  html.add("<thead><tr><th>Producto</th><th>Categoría</th><th>Recetas para fabricarlo</th><th>Máquinas</th></tr></thead>")
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
    html.add(fmt"<div class='empty-placeholder' style='padding: 10px; margin-top: 10px; font-size: 12px;'>Mostrando primeros {maxDisplay} elementos. Usa el buscador para filtrar.</div>")
  html.add("</div>")
  return html

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
  
  # Top Header (Clean, minimalist engineering aesthetic)
  html.add("<header class='planner-header'>")
  html.add("<div class='header-title-box'>")
  html.add("<span class='app-icon'>⚡</span>")
  html.add("<div class='app-titles'>")
  html.add("<h1 class='app-title'>Satisfactory Factory Planner</h1>")
  html.add("<span class='app-subtitle'>Planificación multindustrial independiente // Optimización lineal Simplex</span>")
  html.add("</div>")
  html.add("</div>")
  html.add("</header>")

  # Main Content
  html.add("<main class='planner-main'>")
  
  # 1. Multi-factory switcher and toolbar
  html.add(renderFactoryBar())

  # 2. Factory configuration (Targets & Available Raw Resources)
  html.add(renderFactoryConfig())

  # 3. Main tab navigation
  html.add(renderTabBar())

  # 4. Tab contents
  case currentTab
  of "production": html.add(renderProductionTab())
  of "graph": html.add(renderGraphTab())
  of "alternates": html.add(renderAlternatesTab())
  of "database": html.add(renderDatabaseTab())
  else: html.add(renderProductionTab())

  html.add("</main>")

  app.innerHTML = cstring(html)

  if currentTab == "graph" and graphViewMode == "svg":
    initGraphInteractions()

proc bindGlobalEvents*() =
  if eventsBound: return
  eventsBound = true

  # 1. Global Click Delegation
  document.addEventListener(cstring("click"), proc(e: Event) =
    let target = e.target
    if target == nil: return

    # Switch factory tab
    let factTab = findClosest(target, cstring(".factory-tab"))
    if factTab != nil and findClosest(target, cstring(".btn-tab-close")) == nil:
      let fid = factTab.getAttribute(cstring("data-factory-id"))
      if fid != nil and $fid != activeFactoryId:
        activeFactoryId = $fid
        saveFactories()
        updatePlan()
        renderApp()
        return

    # Delete factory button (from tab or toolbar)
    let closeTabBtn = findClosest(target, cstring(".btn-tab-close"))
    let delFactBtn = findClosest(target, cstring("#btn-delete-factory"))
    if (closeTabBtn != nil or delFactBtn != nil) and factories.len > 1:
      let targetFid = if closeTabBtn != nil: $closeTabBtn.getAttribute(cstring("data-factory-id")) else: activeFactoryId
      var delIdx = -1
      for i in 0 ..< factories.len:
        if factories[i].id == targetFid:
          delIdx = i
          break
      if delIdx >= 0:
        factories.delete(delIdx)
        if activeFactoryId == targetFid:
          activeFactoryId = factories[0].id
        saveFactories()
        updatePlan()
        renderApp()
        return

    # New factory button
    let newFactBtn = findClosest(target, cstring("#btn-new-factory"))
    if newFactBtn != nil:
      let newId = generateFactoryId()
      let newName = fmt"Fábrica {factories.len + 1}"
      let newFactory = createDefaultFactory(newId, newName)
      factories.add(newFactory)
      activeFactoryId = newId
      saveFactories()
      updatePlan()
      renderApp()
      return

    # Duplicate factory button
    let dupBtn = findClosest(target, cstring("#btn-duplicate-factory"))
    if dupBtn != nil:
      let fPtr = getActiveFactory()
      if fPtr != nil:
        let newId = generateFactoryId()
        var cloned = fPtr[]
        cloned.id = newId
        cloned.name = fPtr[].name & " (Copia)"
        factories.add(cloned)
        activeFactoryId = newId
        saveFactories()
        updatePlan()
        renderApp()
        return

    # Raw resource pill toggle
    let rawPill = findClosest(target, cstring(".raw-pill"))
    if rawPill != nil:
      let rId = rawPill.getAttribute(cstring("data-raw-id"))
      let fPtr = getActiveFactory()
      if rId != nil and fPtr != nil:
        let rStr = $rId
        let foundIdx = fPtr[].allowedRaw.find(rStr)
        if foundIdx >= 0:
          fPtr[].allowedRaw.delete(foundIdx)
        else:
          fPtr[].allowedRaw.add(rStr)
        saveFactories()
        updatePlan()
        renderApp()
        return

    # Raw quick buttons: All / None
    let rawAllBtn = findClosest(target, cstring("#btn-raw-all"))
    if rawAllBtn != nil:
      let fPtr = getActiveFactory()
      if fPtr != nil:
        fPtr[].allowedRaw = getAllRawResourceIds()
        saveFactories()
        updatePlan()
        renderApp()
        return

    let rawNoneBtn = findClosest(target, cstring("#btn-raw-none"))
    if rawNoneBtn != nil:
      let fPtr = getActiveFactory()
      if fPtr != nil:
        fPtr[].allowedRaw = @[]
        saveFactories()
        updatePlan()
        renderApp()
        return

    # Main Tab Buttons
    let tabBtn = findClosest(target, cstring(".main-tabs .tab-btn"))
    if tabBtn != nil:
      let tabId = tabBtn.getAttribute(cstring("data-tab"))
      if tabId != nil and $tabId != "":
        currentTab = $tabId
        renderApp()
        return

    # Graph view mode switches
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

    # Add Target button
    let addBtn = findClosest(target, cstring("#btn-add-target"))
    if addBtn != nil:
      let sel = cast[SelectElement](document.getElementById(cstring("target-item-select")))
      let rateIn = cast[InputElement](document.getElementById(cstring("target-rate-input")))
      let fPtr = getActiveFactory()
      if sel != nil and rateIn != nil and fPtr != nil:
        let itemId = $sel.value
        let rateVal = parseFloat($rateIn.value)
        if rateVal > 0.0 and itemId != "":
          var found = false
          for i in 0 ..< fPtr[].targets.len:
            if fPtr[].targets[i].itemId == itemId:
              fPtr[].targets[i].rate = rateVal
              found = true
              break
          if not found:
            fPtr[].targets.add(FactoryTarget(itemId: itemId, rate: rateVal))
          saveFactories()
          updatePlan()
          renderApp()
          return

    # Remove target chip
    let removeBtn = findClosest(target, cstring(".chip-remove-btn"))
    if removeBtn != nil:
      let idxStr = removeBtn.getAttribute(cstring("data-idx"))
      let fPtr = getActiveFactory()
      if idxStr != nil and fPtr != nil:
        let idx = parseInt($idxStr)
        if idx >= 0 and idx < fPtr[].targets.len:
          fPtr[].targets.delete(idx)
          saveFactories()
          updatePlan()
          renderApp()
          return

    # Step chip rate (+5 / -5)
    let stepBtn = findClosest(target, cstring(".chip-step-btn"))
    if stepBtn != nil:
      let idxStr = stepBtn.getAttribute(cstring("data-idx"))
      let actStr = stepBtn.getAttribute(cstring("data-action"))
      let fPtr = getActiveFactory()
      if idxStr != nil and fPtr != nil:
        let idx = parseInt($idxStr)
        if idx >= 0 and idx < fPtr[].targets.len:
          if $actStr == "inc":
            fPtr[].targets[idx].rate += 5.0
          elif $actStr == "dec":
            fPtr[].targets[idx].rate = max(1.0, fPtr[].targets[idx].rate - 5.0)
          saveFactories()
          updatePlan()
          renderApp()
          return

    # Enable / Disable all alternates
    let enableAllBtn = findClosest(target, cstring("#btn-enable-all-alts"))
    if enableAllBtn != nil:
      let fPtr = getActiveFactory()
      if fPtr != nil:
        fPtr[].enabledAlts = @[]
        for idStr in alternateRecipeIds:
          fPtr[].enabledAlts.add(idStr)
        saveFactories()
        updatePlan()
        renderApp()
        return

    let disableAllBtn = findClosest(target, cstring("#btn-disable-all-alts"))
    if disableAllBtn != nil:
      let fPtr = getActiveFactory()
      if fPtr != nil:
        fPtr[].enabledAlts = @[]
        saveFactories()
        updatePlan()
        renderApp()
        return
  )

  # 2. Global Change Delegation
  document.addEventListener(cstring("change"), proc(e: Event) =
    let target = e.target
    if target == nil: return

    # Alternate recipe checkbox toggle
    let altBox = findClosest(target, cstring(".alt-checkbox"))
    if altBox != nil:
      let box = cast[InputElement](altBox)
      let rId = box.getAttribute(cstring("data-recipe-id"))
      let fPtr = getActiveFactory()
      if rId != nil and fPtr != nil:
        let rStr = $rId
        let foundIdx = fPtr[].enabledAlts.find(rStr)
        if box.checked:
          if foundIdx < 0: fPtr[].enabledAlts.add(rStr)
        else:
          if foundIdx >= 0: fPtr[].enabledAlts.delete(foundIdx)
        saveFactories()
        updatePlan()
        renderApp()
        return

    # Preset selector
    let presetSel = findClosest(target, cstring("#preset-select"))
    if presetSel != nil:
      let sel = cast[SelectElement](presetSel)
      let pid = $sel.value
      let fPtr = getActiveFactory()
      if pid != "" and fPtr != nil:
        for p in getPresets():
          if p.id == pid:
            fPtr[].targets = p.targets
            if p.enableAlternates:
              for a in p.enabledAlts:
                if not fPtr[].enabledAlts.contains(a):
                  fPtr[].enabledAlts.add(a)
            saveFactories()
            updatePlan()
            renderApp()
            return
  )

  # 3. Global Input Delegation
  document.addEventListener(cstring("input"), proc(e: Event) =
    let target = e.target
    if target == nil: return

    # Factory name live edit
    let nameInput = findClosest(target, cstring("#factory-name-input"))
    if nameInput != nil:
      let fPtr = getActiveFactory()
      if fPtr != nil:
        fPtr[].name = $cast[InputElement](nameInput).value
        saveFactories()
        # Update tab label without full app re-render
        let tabEl = document.querySelector(cstring(".factory-tab.active .factory-tab-name"))
        if tabEl != nil:
          tabEl.textContent = cstring(fPtr[].name)
      return

    # Alternate recipes search query
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

    # Database search query
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
  let loaded = loadFactories()
  if not loaded or factories.len == 0:
    let defFact = createDefaultFactory("factory-1", "Base Principal")
    factories = @[defFact]
    activeFactoryId = defFact.id
    saveFactories()

  bindGlobalEvents()
  updatePlan()
  renderApp()