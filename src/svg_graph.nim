import std/[tables, sequtils, algorithm, math, strutils, strformat]
import types

proc escapeHtml(s: string): string =
  result = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

proc renderSvgGraph*(plan: FactoryPlan): string =
  if plan.nodes.len == 0:
    return "<div class='empty-placeholder'>No nodes to display. Add product targets above to generate the factory flowchart!</div>"

  # Group nodes by tier
  var tierGroups = initTable[int, seq[FlowNode]]()
  var maxTier = 0
  for n in plan.nodes:
    var list = tierGroups.getOrDefault(n.tier, @[])
    list.add(n)
    tierGroups[n.tier] = list
    if n.tier > maxTier:
      maxTier = n.tier

  var sortedTiers: seq[int] = @[]
  for t in tierGroups.keys:
    sortedTiers.add(t)
  sortedTiers.sort()

  let colWidth = 320.0
  let rowHeight = 110.0
  let nodeW = 240.0
  let nodeH = 76.0
  let marginX = 60.0
  let marginY = 60.0

  var maxRows = 1
  for _, list in tierGroups:
    if list.len > maxRows:
      maxRows = list.len

  let totalWidth = max(1000.0, marginX * 2.0 + float(sortedTiers.len) * colWidth)
  let totalHeight = max(560.0, marginY * 2.0 + float(maxRows) * rowHeight + 40.0)

  # Calculate (x, y) for each node
  type NodePos = object
    x: float
    y: float

  var positions = initTable[string, NodePos]()

  for colIdx, t in sortedTiers:
    let list = tierGroups[t]
    # Center rows vertically in each column
    let colHeight = float(list.len) * rowHeight
    let startY = marginY + (totalHeight - marginY * 2.0 - colHeight) / 2.0

    for rowIdx, n in list:
      let nx = marginX + float(colIdx) * colWidth
      let ny = max(marginY, startY + float(rowIdx) * rowHeight)
      positions[n.id] = NodePos(x: nx, y: ny)

  var svg = ""
  svg.add(fmt"<svg id='ficsit-dag-svg' viewBox='0 0 {totalWidth:.0f} {totalHeight:.0f}' class='flowchart-svg' data-width='{totalWidth:.0f}' data-height='{totalHeight:.0f}' xmlns='http://www.w3.org/2000/svg'>")
  
  # Defs: Arrow markers & filters
  svg.add("<defs>")
  svg.add("<marker id='arrow' viewBox='0 0 10 10' refX='8' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'>")
  svg.add("<path d='M 0 1.5 L 8 5 L 0 8.5 z' fill='#FA9549' />")
  svg.add("</marker>")
  svg.add("<marker id='arrow-hl' viewBox='0 0 10 10' refX='8' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'>")
  svg.add("<path d='M 0 1.5 L 8 5 L 0 8.5 z' fill='#ffb86c' />")
  svg.add("</marker>")
  svg.add("<filter id='node-shadow' x='-10%' y='-10%' width='125%' height='125%'>")
  svg.add("<feDropShadow dx='0' dy='4' stdDeviation='5' flood-color='#000000' flood-opacity='0.45'/>")
  svg.add("</filter>")
  svg.add("<filter id='glow-hl' x='-20%' y='-20%' width='140%' height='140%'>")
  svg.add("<feDropShadow dx='0' dy='0' stdDeviation='6' flood-color='#FA9549' flood-opacity='0.6'/>")
  svg.add("</filter>")
  svg.add("</defs>")

  # Background grid
  svg.add(fmt"<rect width='{totalWidth:.0f}' height='{totalHeight:.0f}' fill='#14161a' />")

  # Render Column Tier Headers & subtle divider guidelines
  for colIdx, t in sortedTiers:
    let tx = marginX + float(colIdx) * colWidth + nodeW / 2.0
    let label = if t == 0: "RAW RESOURCES"
                elif colIdx == sortedTiers.len - 1: "FINAL TARGETS"
                elif t == 1: "STAGE 1 (SMELTING/REFINING)"
                elif t == 2: "STAGE 2 (BASIC COMPONENTS)"
                elif t == 3: "STAGE 3 (INTERMEDIATE)"
                elif t == 4: "STAGE 4 (ADVANCED ASSEMBLY)"
                else: fmt"STAGE {t}"

    svg.add(fmt"<line x1='{tx - nodeW/2.0:.0f}' y1='{marginY - 10.0:.0f}' x2='{tx + nodeW/2.0:.0f}' y2='{marginY - 10.0:.0f}' stroke='#2b2f38' stroke-width='2' />")
    svg.add(fmt"<text x='{tx:.0f}' y='{marginY - 20.0:.0f}' text-anchor='middle' class='tier-label' stroke='none'>{label}</text>")

  # Render Edges Container
  svg.add("<g id='dag-edges-layer'>")
  var edgeIdx = 0
  for e in plan.edges:
    if positions.hasKey(e.fromNode) and positions.hasKey(e.toNode):
      let pFrom = positions[e.fromNode]
      let pTo = positions[e.toNode]

      let x1 = pFrom.x + nodeW
      let y1 = pFrom.y + nodeH / 2.0
      let x2 = pTo.x
      let y2 = pTo.y + nodeH / 2.0

      var pathD = ""
      if x2 >= x1 - 10.0:
        let dx = max(45.0, (x2 - x1) * 0.5)
        pathD = fmt"M {x1:.1f} {y1:.1f} C {x1 + dx:.1f} {y1:.1f}, {x2 - dx:.1f} {y2:.1f}, {x2:.1f} {y2:.1f}"
      else:
        # Loopback edge (byproducts recycling back)
        let loopY = max(y1, y2) + 50.0
        pathD = fmt"M {x1:.1f} {y1:.1f} C {x1 + 60.0:.1f} {loopY:.1f}, {x2 - 60.0:.1f} {loopY:.1f}, {x2:.1f} {y2:.1f}"

      svg.add(fmt"<path id='edge-{edgeIdx}' data-edge-idx='{edgeIdx}' data-from='{e.fromNode}' data-to='{e.toNode}' data-x1='{x1:.1f}' data-y1='{y1:.1f}' data-x2='{x2:.1f}' data-y2='{y2:.1f}' d='{pathD}' class='flow-edge' marker-end='url(#arrow)' stroke='#474b54' stroke-width='2' fill='none' />")

      # Midpoint label badge
      let midX = (x1 + x2) / 2.0
      let midY = (y1 + y2) / 2.0
      let labelText = fmt"{e.rate:.1f}/m {e.itemName}"
      let badgeW = max(70.0, float(labelText.len) * 6.5 + 14.0)
      let badgeH = 20.0

      svg.add(fmt"<g id='label-{edgeIdx}' class='edge-label' data-edge-idx='{edgeIdx}' data-from='{e.fromNode}' data-to='{e.toNode}' data-w='{badgeW:.1f}' data-h='{badgeH:.1f}' transform='translate({midX - badgeW/2.0:.1f}, {midY - badgeH/2.0:.1f})'>")
      svg.add(fmt"<rect width='{badgeW:.1f}' height='{badgeH:.1f}' rx='4' fill='#1b1e23' stroke='#363a44' stroke-width='1' />")
      svg.add(fmt"<text x='{badgeW/2.0:.1f}' y='14' text-anchor='middle' class='edge-text' stroke='none'>{escapeHtml(labelText)}</text>")
      svg.add("</g>")

      inc edgeIdx
  svg.add("</g>") # dag-edges-layer

  # Render Nodes Container
  svg.add("<g id='dag-nodes-layer'>")
  for n in plan.nodes:
    if positions.hasKey(n.id):
      let pos = positions[n.id]
      let borderCol = if n.kind == "raw": "#2ecc71"
                      elif n.kind == "target": "#FA9549"
                      else: "#5865F2"
      let bgCol = "#1f2228"
      let accentCol = if n.color != "": n.color else: borderCol

      svg.add(fmt"<g id='node-{n.id}' class='flow-node node-{n.kind}' data-id='{n.id}' data-x='{pos.x:.1f}' data-y='{pos.y:.1f}' data-orig-x='{pos.x:.1f}' data-orig-y='{pos.y:.1f}' transform='translate({pos.x:.1f}, {pos.y:.1f})' filter='url(#node-shadow)' style='cursor: grab;'>")
      # Background card
      svg.add(fmt"<rect width='{nodeW:.1f}' height='{nodeH:.1f}' rx='8' fill='{bgCol}' stroke='{borderCol}' stroke-width='1.5' class='node-bg' />")
      # Left accent stripe
      svg.add(fmt"<rect width='6' height='{nodeH:.1f}' rx='3' fill='{accentCol}' />")
      # Kind badge top right
      let kindBadge = case n.kind
                      of "raw": "EXTRACTOR"
                      of "target": "OUTPUT"
                      else: "CRAFTING"
      svg.add(fmt"<text x='{nodeW - 12.0:.1f}' y='18' text-anchor='end' class='node-badge' stroke='none'>{kindBadge}</text>")
      # Title
      svg.add(fmt"<text x='16' y='32' class='node-title' stroke='none'>{escapeHtml(n.title)}</text>")
      # Subtitle / rate / machines
      svg.add(fmt"<text x='16' y='54' class='node-subtitle' stroke='none'>{escapeHtml(n.subtitle)}</text>")
      svg.add("</g>")
  svg.add("</g>") # dag-nodes-layer

  svg.add("</svg>")
  return svg

proc renderStageBreakdown*(plan: FactoryPlan): string =
  if plan.nodes.len == 0:
    return "<div class='empty-placeholder'>No nodes to display. Add product targets above!</div>"

  # Group nodes by tier
  var tierGroups = initTable[int, seq[FlowNode]]()
  var maxTier = 0
  for n in plan.nodes:
    var list = tierGroups.getOrDefault(n.tier, @[])
    list.add(n)
    tierGroups[n.tier] = list
    if n.tier > maxTier:
      maxTier = n.tier

  var sortedTiers: seq[int] = @[]
  for t in tierGroups.keys:
    sortedTiers.add(t)
  sortedTiers.sort()

  # Map incoming and outgoing edges per node
  var incomingMap = initTable[string, seq[FlowEdge]]()
  var outgoingMap = initTable[string, seq[FlowEdge]]()
  for e in plan.edges:
    var inList = incomingMap.getOrDefault(e.toNode, @[])
    inList.add(e)
    incomingMap[e.toNode] = inList

    var outList = outgoingMap.getOrDefault(e.fromNode, @[])
    outList.add(e)
    outgoingMap[e.fromNode] = outList

  var html = "<div class='stages-board'>"
  for colIdx, t in sortedTiers:
    let list = tierGroups[t]
    let label = if t == 0: "⛏️ Raw Resources"
                elif colIdx == sortedTiers.len - 1: "🚀 Final Targets"
                elif t == 1: "🔥 Stage 1: Smelting / Refining"
                elif t == 2: "⚙️ Stage 2: Basic Components"
                elif t == 3: "🔩 Stage 3: Intermediate"
                elif t == 4: "🏗️ Stage 4: Advanced Assemblies"
                else: fmt"🏭 Stage {t}"

    html.add("<div class='stage-column'>")
    html.add(fmt"<div class='stage-column-header'><h4>{label}</h4><span class='stage-count'>{list.len} items</span></div>")
    html.add("<div class='stage-cards-container'>")

    for n in list:
      let inEdges = incomingMap.getOrDefault(n.id, @[])
      let outEdges = outgoingMap.getOrDefault(n.id, @[])
      let borderCol = if n.kind == "raw": "#2ecc71"
                      elif n.kind == "target": "#FA9549"
                      else: "#5865F2"

      html.add(fmt"<div class='stage-card' style='border-left: 4px solid {borderCol};'>")
      html.add("<div class='stage-card-title'>")
      html.add(fmt"<strong>{escapeHtml(n.title)}</strong>")
      html.add(fmt"<span class='stage-card-badge'>{n.kind}</span>")
      html.add("</div>")
      html.add(fmt"<div class='stage-card-sub'>{escapeHtml(n.subtitle)}</div>")

      # Incoming flows
      if inEdges.len > 0:
        html.add("<div class='stage-io-section'><span class='io-tag io-in'>IN:</span>")
        for ie in inEdges:
          html.add(fmt"<span class='io-chip in-chip'>← {ie.rate:.1f}/m {escapeHtml(ie.itemName)}</span>")
        html.add("</div>")

      # Outgoing flows
      if outEdges.len > 0:
        html.add("<div class='stage-io-section'><span class='io-tag io-out'>OUT:</span>")
        for oe in outEdges:
          html.add(fmt"<span class='io-chip out-chip'>→ {oe.rate:.1f}/m {escapeHtml(oe.itemName)}</span>")
        html.add("</div>")

      html.add("</div>") # stage-card

    html.add("</div>") # stage-cards-container
    html.add("</div>") # stage-column

  html.add("</div>") # stages-board
  return html
