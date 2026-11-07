import std/[tables, sets, math, strutils, strformat]
import types, dataset

const
  WorldMinX* = -324600.0
  WorldMaxX* = 425300.0
  WorldMinY* = -375000.0
  WorldMaxY* = 375000.0
  WorldWidth* = WorldMaxX - WorldMinX  # 749900.0 cm (~7.5 km)
  WorldHeight* = WorldMaxY - WorldMinY # 750000.0 cm (~7.5 km)

proc projectCoords*(ueX, ueY: float, svgWidth: float = 1000.0, svgHeight: float = 1000.0): tuple[x: float, y: float] =
  ## Projects Unreal Engine coordinates (in cm) to 2D SVG canvas pixels.
  let px = ((ueX - WorldMinX) / WorldWidth) * svgWidth
  let py = ((ueY - WorldMinY) / WorldHeight) * svgHeight
  return (px, py)

proc escapeHtml(s: string): string =
  result = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

proc getMineralColor*(resourceId: string): string =
  case resourceId
  of "iron-ore": "#5dade2"       # Steel Blue
  of "copper-ore": "#e67e22"     # Copper Orange
  of "limestone": "#ecf0f1"      # Stone White
  of "coal": "#95a5a6"           # Slate Gray
  of "crude-oil": "#9b59b6"      # Deep Purple
  of "raw-quartz": "#fd79a8"     # Quartz Pink
  of "caterium-ore": "#f1c40f"   # Caterium Gold
  of "bauxite": "#e17055"        # Bauxite Terracotta
  of "sulfur": "#f9ca24"         # Sulfur Yellow
  of "uranium": "#00b894"        # Uranium Emerald/Neon
  of "nitrogen-gas": "#00cec9"   # Nitrogen Cyan
  of "sam-ore": "#6c5ce7"        # SAM Purple
  of "water": "#0984e3"          # Water Blue
  else: "#bdc3c7"

proc getEffectiveRec*(sub: SubFactoryModule, selectedOptions: Table[string, int]): LocationRecommendation =
  if sub.recommendations.len == 0:
    return LocationRecommendation()
  let optIdx = min(sub.recommendations.len - 1, max(0, selectedOptions.getOrDefault(sub.id, 0)))
  return sub.recommendations[optIdx]

proc renderSvgMap*(plan: FactoryPlan,
                   allNodes: seq[ResourceNode],
                   selectedOptions: Table[string, int] = initTable[string, int](),
                   svgW: float = 1000.0,
                   svgH: float = 1000.0): string =
  ## Generates a high-contrast, tactical FICSIT Radar vector SVG map of the Satisfactory 1.0 world.
  ## Displays background grid, all world resource nodes, selected module nodes,
  ## sub-factory beacons, inter-module logistics routes, and interactive pan-zoom controls.
  let wInt = int(svgW)
  let hInt = int(svgH)
  var svg = ""
  svg.add(fmt"<svg id='ficsit-world-map-svg' viewBox='0 0 {wInt} {hInt}' width='100%' height='100%' ")
  svg.add("xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' class='ficsit-map-canvas' style='cursor: grab; user-select: none;'>\n")

  # 1. Defs: Glow filters, Gradients, Arrow markers
  svg.add("<defs>\n")
  svg.add("""
    <!-- Glow filter for active nodes & beacons -->
    <filter id="radar-glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="3.5" result="blur" />
      <feMerge>
        <feMergeNode in="blur" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
    <filter id="strong-glow" x="-100%" y="-100%" width="300%" height="300%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="6" result="blur1" />
      <feGaussianBlur in="SourceGraphic" stdDeviation="12" result="blur2" />
      <feMerge>
        <feMergeNode in="blur2" />
        <feMergeNode in="blur1" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>

    <!-- Arrow markers for logistics routes -->
    <marker id="logistics-arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M 0 2 L 8 5 L 0 8 z" fill="#FA9549" />
    </marker>
    <marker id="logistics-arrow-alt" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M 0 2 L 8 5 L 0 8 z" fill="#00cec9" />
    </marker>

    <!-- Beacon pulses -->
    <radialGradient id="beacon-pulse-orange" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#FA9549" stop-opacity="0.9" />
      <stop offset="60%" stop-color="#FA9549" stop-opacity="0.25" />
      <stop offset="100%" stop-color="#FA9549" stop-opacity="0" />
    </radialGradient>
    <radialGradient id="beacon-pulse-cyan" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#00cec9" stop-opacity="0.9" />
      <stop offset="60%" stop-color="#00cec9" stop-opacity="0.25" />
      <stop offset="100%" stop-color="#00cec9" stop-opacity="0" />
    </radialGradient>
  </defs>
  """)

  # 2. Main Pan-Zoom Layer Group
  svg.add("<g id='map-pan-zoom-layer' transform='translate(0, 0) scale(1)'>\n")

  # 2.1 Base background (Dark tactical radar surface)
  svg.add(fmt"<rect width='{wInt}' height='{hInt}' fill='#0c111a' />\n")

  # High-resolution satellite / topographical map image
  svg.add(fmt"<image id='map-satellite-img' href='map_bg.jpg' width='{wInt}' height='{hInt}' ")
  svg.add("preserveAspectRatio='none' opacity='0.82' style='display: block;' />\n")

  # 2.2 FICSIT Tactical Radar Grid
  svg.add("<g id='radar-grid' class='radar-tactical-grid'>\n")

  # Concentric radar range rings from map center (0, 0 in UE)
  let (midPx, midPy) = projectCoords(0.0, 0.0, svgW, svgH)
  for rRing in [100.0, 200.0, 300.0, 420.0]:
    svg.add(fmt"  <circle cx='{midPx:.1f}' cy='{midPy:.1f}' r='{rRing:.1f}' fill='none' stroke='#1b283d' stroke-width='1.2' stroke-dasharray='4,6' opacity='0.7' />\n")

  # Coordinate Grid Lines every 1000 meters (100,000 cm)
  var currUeX = -300000.0
  while currUeX <= 400000.0:
    let (px, _) = projectCoords(currUeX, 0.0, svgW, svgH)
    svg.add(fmt"  <line x1='{px:.1f}' y1='0' x2='{px:.1f}' y2='{hInt}' stroke='#162235' stroke-width='1' stroke-dasharray='2,4' />\n")
    let km = int(currUeX / 100000.0)
    svg.add(fmt"  <text x='{px + 3.0:.1f}' y='14' fill='#3a506b' font-size='9' font-family='monospace'>X:{km}km</text>\n")
    currUeX += 100000.0

  var currUeY = -300000.0
  while currUeY <= 300000.0:
    let (_, py) = projectCoords(0.0, currUeY, svgW, svgH)
    svg.add(fmt"  <line x1='0' y1='{py:.1f}' x2='{wInt}' y2='{py:.1f}' stroke='#162235' stroke-width='1' stroke-dasharray='2,4' />\n")
    let km = int(currUeY / 100000.0)
    svg.add(fmt"  <text x='6' y='{py - 3.0:.1f}' fill='#3a506b' font-size='9' font-family='monospace'>Y:{km}km</text>\n")
    currUeY += 100000.0

  # Crosshair at map center
  svg.add(fmt"  <line x1='{midPx - 15.0:.1f}' y1='{midPy:.1f}' x2='{midPx + 15.0:.1f}' y2='{midPy:.1f}' stroke='#00cec9' stroke-width='1.5' opacity='0.8' />\n")
  svg.add(fmt"  <line x1='{midPx:.1f}' y1='{midPy - 15.0:.1f}' x2='{midPx:.1f}' y2='{midPy + 15.0:.1f}' stroke='#00cec9' stroke-width='1.5' opacity='0.8' />\n")
  svg.add(fmt"  <circle cx='{midPx:.1f}' cy='{midPy:.1f}' r='3' fill='none' stroke='#00cec9' stroke-width='1' />\n")
  svg.add("</g>\n") # end radar-grid

  # 2.3 Biome Landmark Labels (automatically calculated from node clusters)
  svg.add("<g id='biome-landmarks' class='biome-labels' opacity='0.65'>\n")
  for bName, bNodes in nodesByBiome:
    if bNodes.len >= 3:
      var sumX = 0.0
      var sumY = 0.0
      for n in bNodes:
        sumX += n.x
        sumY += n.y
      let avgX = sumX / float(bNodes.len)
      let avgY = sumY / float(bNodes.len)
      let (bx, by) = projectCoords(avgX, avgY, svgW, svgH)
      svg.add(fmt"  <text x='{bx:.1f}' y='{by:.1f}' text-anchor='middle' fill='#4b6584' font-size='11' font-weight='600' letter-spacing='1.5' font-family='sans-serif' style='user-select: none;'>{escapeHtml(bName.toUpperAscii())}</text>\n")
  svg.add("</g>\n")

  # 2.4 Inactive Background Resource Nodes (608 nodes)
  var activeNodeIds = initHashSet[string]()
  for sub in plan.subFactories:
    let r = getEffectiveRec(sub, selectedOptions)
    for n in r.matchedNodes:
      activeNodeIds.incl(n.id)

  svg.add("<g id='inactive-map-nodes' class='background-nodes'>\n")
  for n in allNodes:
    if not activeNodeIds.contains(n.id):
      let (nx, ny) = projectCoords(n.x, n.y, svgW, svgH)
      let color = getMineralColor(n.resourceId)
      let rName = getItemName(n.resourceId)
      let tip = fmt"{rName} ({n.purity.capitalizeAscii()}) - {n.biome}&#10;UE: ({n.x:.0f}, {n.y:.0f})"
      svg.add(fmt"  <g class='map-node-point' data-type='node' data-status='inactive' data-id='{n.id}' data-res-id='{n.resourceId}' data-name='{escapeHtml(rName)}' data-purity='{n.purity}' data-biome='{escapeHtml(n.biome)}' data-x='{n.x:.0f}' data-y='{n.y:.0f}' data-color='{color}'>\n")
      svg.add(fmt"    <circle cx='{nx:.1f}' cy='{ny:.1f}' r='6' fill='transparent' cursor='pointer' />\n")
      svg.add(fmt"    <circle class='node-dot' cx='{nx:.1f}' cy='{ny:.1f}' r='2.8' fill='{color}' fill-opacity='0.6' stroke='#0c111a' stroke-width='0.5' pointer-events='none' />\n")
      svg.add(fmt"    <title>{escapeHtml(tip)}</title>\n")
      svg.add("  </g>\n")
  svg.add("</g>\n")

  # 2.5 Active Matched Nodes & Feeder Lines to Sub-Factory Centroids
  svg.add("<g id='active-subfactory-nodes' class='active-nodes'>\n")
  for sub in plan.subFactories:
    let topRec = getEffectiveRec(sub, selectedOptions)
    if topRec.matchedNodes.len > 0:
      let (subPx, subPy) = projectCoords(topRec.centerX, topRec.centerY, svgW, svgH)

      for n in topRec.matchedNodes:
        let (nx, ny) = projectCoords(n.x, n.y, svgW, svgH)
        let color = getMineralColor(n.resourceId)
        let rName = getItemName(n.resourceId)

        # Dashed logistical feeder line from node to subfactory beacon
        svg.add(fmt"  <line x1='{nx:.1f}' y1='{ny:.1f}' x2='{subPx:.1f}' y2='{subPy:.1f}' stroke='{color}' stroke-width='1.8' stroke-dasharray='3,3' opacity='0.8' />\n")

        # Purity indicator badge (P = Pure, N = Normal, I = Impure)
        let badgeChar = case n.purity
          of "pure": "P"
          of "impure": "I"
          else: "N"

        let tip = fmt"RECURSO ACTIVO: {rName} ({n.purity.capitalizeAscii()})&#10;Asignado a: {sub.name}&#10;Bioma: {n.biome}&#10;UE: ({n.x:.0f}, {n.y:.0f})"
        svg.add(fmt"  <g class='map-node-point map-active-node' data-type='node' data-status='active' data-id='{n.id}' data-res-id='{n.resourceId}' data-name='{escapeHtml(rName)}' data-purity='{n.purity}' data-biome='{escapeHtml(n.biome)}' data-subfactory='{escapeHtml(sub.name)}' data-x='{n.x:.0f}' data-y='{n.y:.0f}' data-color='{color}'>\n")
        svg.add(fmt"    <circle cx='{nx:.1f}' cy='{ny:.1f}' r='14' fill='transparent' cursor='pointer' />\n")
        svg.add(fmt"    <circle cx='{nx:.1f}' cy='{ny:.1f}' r='9' fill='{color}' fill-opacity='0.35' filter='url(#radar-glow)' pointer-events='none' />\n")
        svg.add(fmt"    <circle class='node-dot' cx='{nx:.1f}' cy='{ny:.1f}' r='5.5' fill='{color}' stroke='#ffffff' stroke-width='1.8' pointer-events='none' />\n")
        svg.add(fmt"    <text x='{nx:.1f}' y='{ny + 3.0:.1f}' text-anchor='middle' fill='#0c111a' font-size='7.5' font-weight='bold' font-family='sans-serif' pointer-events='none'>{badgeChar}</text>\n")
        svg.add(fmt"    <title>{escapeHtml(tip)}</title>\n")
        svg.add("  </g>\n")
  svg.add("</g>\n")

  # 2.6 Inter-Factory Logistics Transport Lines
  svg.add("<g id='logistics-routes' class='logistics-lines'>\n")
  for sup in plan.subFactories:
    if sup.recommendations.len == 0: continue
    let supRec = getEffectiveRec(sup, selectedOptions)
    let (supX, supY) = projectCoords(supRec.centerX, supRec.centerY, svgW, svgH)

    for consumer in plan.subFactories:
      if consumer.id == sup.id or consumer.recommendations.len == 0: continue
      let conRec = getEffectiveRec(consumer, selectedOptions)
      let (conX, conY) = projectCoords(conRec.centerX, conRec.centerY, svgW, svgH)

      var carriedItems: seq[string] = @[]
      var carriedRate = 0.0
      for prod in sup.producedItems:
        for st in consumer.steps:
          if st.inputs.hasKey(prod.itemId):
            let flow = min(prod.rate, st.inputs[prod.itemId])
            carriedRate += flow
            carriedItems.add(fmt"{getItemName(prod.itemId)}: {flow:.1f}/m")

      if carriedRate > 0.001:
        let dxM = (conRec.centerX - supRec.centerX) / 100.0
        let dyM = (conRec.centerY - supRec.centerY) / 100.0
        let distMeters = sqrt(dxM * dxM + dyM * dyM)

        if distMeters > 30.0:
          let (transportIcon, routeColor) = if distMeters < 400.0:
                                              ("📦 Cinta Mk.5", "#FA9549")
                                            elif distMeters < 1500.0:
                                              ("🚜 Camión", "#f39c12")
                                            else:
                                              ("🚂 Tren / 🛸 Dron", "#00cec9")

          let carriedStr = carriedItems.join(", ")
          let tip = fmt"RUTA LOGÍSTICA: {sup.name} ➔ {consumer.name}&#10;Transporte: {transportIcon}&#10;Distancia: {distMeters:.0f}m&#10;Carga: {carriedStr}"
          svg.add(fmt"  <g class='map-route-line' data-type='route' data-from='{escapeHtml(sup.name)}' data-to='{escapeHtml(consumer.name)}' data-type-label='{escapeHtml(transportIcon)}' data-dist='{distMeters:.0f}' data-load='{escapeHtml(carriedStr)}' cursor='pointer'>\n")
          svg.add(fmt"    <line x1='{supX:.1f}' y1='{supY:.1f}' x2='{conX:.1f}' y2='{conY:.1f}' stroke='transparent' stroke-width='16' />\n")
          svg.add(fmt"    <line x1='{supX:.1f}' y1='{supY:.1f}' x2='{conX:.1f}' y2='{conY:.1f}' stroke='{routeColor}' stroke-width='2.5' stroke-dasharray='6,4' marker-end='url(#logistics-arrow)' opacity='0.85' pointer-events='none' />\n")

          let midX = (supX + conX) / 2.0
          let midY = (supY + conY) / 2.0
          svg.add(fmt"    <rect x='{midX - 45.0:.1f}' y='{midY - 10.0:.1f}' width='90' height='18' rx='4' fill='#121824' fill-opacity='0.9' stroke='{routeColor}' stroke-width='1' />\n")
          svg.add(fmt"    <text x='{midX:.1f}' y='{midY + 2.5:.1f}' text-anchor='middle' fill='#ffffff' font-size='8.5' font-weight='600' font-family='sans-serif'>{escapeHtml(transportIcon)} ({distMeters:.0f}m)</text>\n")
          svg.add(fmt"    <title>{escapeHtml(tip)}</title>\n")
          svg.add("  </g>\n")
  svg.add("</g>\n")

  # 2.7 Sub-Factory Beacons and Telemetry Cards
  svg.add("<g id='subfactory-beacons' class='subfactory-markers'>\n")
  for idx, sub in plan.subFactories:
    if sub.recommendations.len > 0:
      let rec = getEffectiveRec(sub, selectedOptions)
      let (bx, by) = projectCoords(rec.centerX, rec.centerY, svgW, svgH)
      let isAssembly = sub.requiredRaw.len == 0
      let beaconColor = if isAssembly: "#a29bfe" else: "#FA9549"
      let beaconPulseGrad = if isAssembly: "url(#beacon-pulse-cyan)" else: "url(#beacon-pulse-orange)"

      var prodsParts: seq[string] = @[]
      for p in sub.producedItems:
        prodsParts.add(fmt"{getItemName(p.itemId)} ({p.rate:.1f}/m)")
      let prodJoined = if prodsParts.len > 0: prodsParts.join(", ") else: "Ninguno"

      var rawParts: seq[string] = @[]
      for rId, rRate in sub.requiredRaw:
        rawParts.add(fmt"{getItemName(rId)} ({rRate:.1f}/m)")
      let rawJoined = if rawParts.len > 0: rawParts.join(", ") else: "Ensamblaje sin minería directa"

      let coordStr = fmt"({rec.centerX/100.0:.0f}m, {rec.centerY/100.0:.0f}m)"

      svg.add(fmt"  <g class='map-beacon-point subfactory-beacon-target' data-type='beacon' data-cx='{bx:.1f}' data-cy='{by:.1f}' data-id='{sub.id}' data-name='{escapeHtml(sub.name)}' data-biome='{escapeHtml(rec.biome)}' data-prods='{escapeHtml(prodJoined)}' data-raw='{escapeHtml(rawJoined)}' data-ue='{escapeHtml(coordStr)}' cursor='pointer'>\n")

      # Sonar pulse ring
      svg.add(fmt"    <circle cx='{bx:.1f}' cy='{by:.1f}' r='30' fill='{beaconPulseGrad}' pointer-events='none' />\n")
      svg.add(fmt"    <circle cx='{bx:.1f}' cy='{by:.1f}' r='18' fill='none' stroke='{beaconColor}' stroke-width='1.5' stroke-dasharray='4,4' opacity='0.8' pointer-events='none' />\n")

      # Outer beacon diamond
      let d = 11.0
      svg.add(fmt"    <polygon points='{bx},{by-d} {bx+d},{by} {bx},{by+d} {bx-d},{by}' fill='{beaconColor}' stroke='#ffffff' stroke-width='2' filter='url(#radar-glow)' />\n")
      svg.add(fmt"    <circle cx='{bx:.1f}' cy='{by:.1f}' r='3.5' fill='#ffffff' pointer-events='none' />\n")

      # Badge Card for Sub-Factory
      let cardW = 160.0
      let cardH = 46.0
      let cardX = min(svgW - cardW - 10.0, max(10.0, bx - cardW / 2.0))
      let cardY = if by < 100.0: by + 22.0 else: by - cardH - 18.0

      svg.add(fmt"    <rect x='{cardX:.1f}' y='{cardY:.1f}' width='{cardW:.1f}' height='{cardH:.1f}' rx='6' fill='#101726' fill-opacity='0.92' stroke='{beaconColor}' stroke-width='1.5' filter='url(#radar-glow)' />\n")

      let shortName = if sub.name.len > 24: sub.name[0..21] & "..." else: sub.name
      svg.add(fmt"    <text x='{cardX + 8.0:.1f}' y='{cardY + 15.0:.1f}' fill='#ffffff' font-size='10' font-weight='bold' font-family='sans-serif'>{escapeHtml(shortName)}</text>\n")

      var outputDesc = ""
      if sub.producedItems.len > 0:
        outputDesc = fmt"📦 {getItemName(sub.producedItems[0].itemId)}: {sub.producedItems[0].rate:.1f}/m"
      else:
        outputDesc = "⚙️ En proceso"
      svg.add(fmt"    <text x='{cardX + 8.0:.1f}' y='{cardY + 28.0:.1f}' fill='{beaconColor}' font-size='8.5' font-weight='600' font-family='sans-serif'>{escapeHtml(outputDesc)}</text>\n")

      let coordDesc = fmt"📍 {rec.biome} | {coordStr}"
      svg.add(fmt"    <text x='{cardX + 8.0:.1f}' y='{cardY + 39.0:.1f}' fill='#7f8fa6' font-size='7.5' font-family='monospace'>{escapeHtml(coordDesc)}</text>\n")
      svg.add("  </g>\n")
  svg.add("</g>\n")

  svg.add("</g>\n") # end map-pan-zoom-layer

  # 3. HUD Overlay (Fixed corner telemetry & compass)
  svg.add("<g id='radar-hud-overlay' class='ficsit-hud' style='pointer-events: none;'>\n")
  # Header Badge
  svg.add("  <rect x='16' y='16' width='210' height='36' rx='4' fill='#0e1522' fill-opacity='0.85' stroke='#FA9549' stroke-width='1.2' />\n")
  svg.add("  <text x='26' y='32' fill='#FA9549' font-size='10.5' font-weight='bold' letter-spacing='1' font-family='monospace'>FICSIT RADAR SYS 1.0</text>\n")
  svg.add(fmt"  <text x='26' y='44' fill='#7f8c8d' font-size='8' font-family='monospace'>MAP: MASSAGE-2(A-B) | NODES: {allNodes.len}</text>\n")

  # Compass Rose (Top Right)
  svg.add(fmt"  <g transform='translate({svgW - 40.0:.1f}, 40)'>\n")
  svg.add("    <circle cx='0' cy='0' r='18' fill='#0e1522' fill-opacity='0.85' stroke='#34495e' stroke-width='1' />\n")
  svg.add("    <line x1='0' y1='-14' x2='0' y2='14' stroke='#e74c3c' stroke-width='1.5' />\n")
  svg.add("    <line x1='-14' y1='0' x2='14' y2='0' stroke='#34495e' stroke-width='1' />\n")
  svg.add("    <polygon points='0,-14 -3,-5 3,-5' fill='#e74c3c' />\n")
  svg.add("    <text x='0' y='-16' text-anchor='middle' fill='#e74c3c' font-size='9' font-weight='bold' font-family='monospace'>N</text>\n")
  svg.add("  </g>\n")
  svg.add("</g>\n")

  # 4. Interactive Pan & Zoom Controls inside SVG
  let ctrlX = svgW - 198.0
  svg.add(fmt"<g id='map-controls-hud' class='ficsit-map-controls' transform='translate({ctrlX:.1f}, 70)'>\n")
  svg.add("  <rect width='192' height='32' rx='4' fill='#0e1522' fill-opacity='0.9' stroke='#34495e' stroke-width='1.2' />\n")
  svg.add("  <g id='ctrl-btn-in' cursor='pointer' transform='translate(6, 4)'>\n")
  svg.add("    <rect width='24' height='24' rx='3' fill='#1a2538' stroke='#3a506b' />\n")
  svg.add("    <text x='12' y='17' text-anchor='middle' fill='#FA9549' font-size='16' font-weight='bold'>+</text>\n")
  svg.add("    <title>Acercar zoom (+)</title>\n")
  svg.add("  </g>\n")
  svg.add("  <g id='ctrl-btn-out' cursor='pointer' transform='translate(34, 4)'>\n")
  svg.add("    <rect width='24' height='24' rx='3' fill='#1a2538' stroke='#3a506b' />\n")
  svg.add("    <text x='12' y='16' text-anchor='middle' fill='#FA9549' font-size='16' font-weight='bold'>−</text>\n")
  svg.add("    <title>Alejar zoom (−)</title>\n")
  svg.add("  </g>\n")
  svg.add("  <g id='ctrl-btn-reset' cursor='pointer' transform='translate(62, 4)'>\n")
  svg.add("    <rect width='38' height='24' rx='3' fill='#1a2538' stroke='#3a506b' />\n")
  svg.add("    <text x='19' y='16' text-anchor='middle' fill='#ffffff' font-size='9.5' font-weight='bold'>100%</text>\n")
  svg.add("    <title>Restablecer zoom al 100%</title>\n")
  svg.add("  </g>\n")
  svg.add("  <g id='ctrl-btn-nodes' cursor='pointer' transform='translate(104, 4)'>\n")
  svg.add("    <rect width='26' height='24' rx='3' fill='#1a2538' stroke='#3a506b' />\n")
  svg.add("    <text x='13' y='16' text-anchor='middle' fill='#00cec9' font-size='11'>👁️</text>\n")
  svg.add("    <title>Alternar nodos inactivos</title>\n")
  svg.add("  </g>\n")
  svg.add("  <g id='ctrl-btn-fit' cursor='pointer' transform='translate(134, 4)'>\n")
  svg.add("    <rect width='26' height='24' rx='3' fill='#1a2538' stroke='#3a506b' />\n")
  svg.add("    <text x='13' y='16' text-anchor='middle' fill='#00cec9' font-size='11'>🎯</text>\n")
  svg.add("    <title>Centrar en sub-fábricas</title>\n")
  svg.add("  </g>\n")
  svg.add("  <g id='ctrl-btn-satellite' cursor='pointer' transform='translate(164, 4)'>\n")
  svg.add("    <rect width='24' height='24' rx='3' fill='#1a2538' stroke='#3a506b' />\n")
  svg.add("    <text x='12' y='16' text-anchor='middle' fill='#FA9549' font-size='11'>🗺️</text>\n")
  svg.add("    <title>Alternar Fondo Satélite / Radar</title>\n")
  svg.add("  </g>\n")
  svg.add("</g>\n")

  svg.add("</svg>\n")
  return svg

proc renderSvgMap*(plan: FactoryPlan,
                   allNodes: seq[ResourceNode],
                   svgW: float,
                   svgH: float): string =
  return renderSvgMap(plan, allNodes, initTable[string, int](), svgW, svgH)

proc renderSvgMap*(plan: FactoryPlan, allNodes: seq[ResourceNode]): string =
  return renderSvgMap(plan, allNodes, initTable[string, int](), 1000.0, 1000.0)
