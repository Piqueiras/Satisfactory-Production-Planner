import std/[tables, sets, sequtils, algorithm, math, strutils, strformat]
import dataset, types, planner, locator, svg_map

echo "=== TESTING SVG MAP GENERATOR (STAGE 4) ==="

# 1. Test coordinate projection
let (p0x, p0y) = projectCoords(WorldMinX, WorldMinY, 1000.0, 1000.0)
let (p1x, p1y) = projectCoords(WorldMaxX, WorldMaxY, 1000.0, 1000.0)
let (pmx, pmy) = projectCoords(0.0, 0.0, 1000.0, 1000.0)

echo fmt"Projection Min: ({p0x:.1f}, {p0y:.1f})"
echo fmt"Projection Max: ({p1x:.1f}, {p1y:.1f})"
echo fmt"Projection Mid: ({pmx:.1f}, {pmy:.1f})"

doAssert abs(p0x - 0.0) < 0.001 and abs(p0y - 0.0) < 0.001
doAssert abs(p1x - 1000.0) < 0.001 and abs(p1y - 1000.0) < 0.001
doAssert abs(pmx - 432.857) < 0.1 and abs(pmy - 500.0) < 0.001
echo "✅ Coordinate projection tests passed!"

# 2. Test Plan 1 (Encased Beam + Quartz)
let targets1 = @[
  FactoryTarget(itemId: "encased-industrial-beam", rate: 10.0),
  FactoryTarget(itemId: "quartz-crystal", rate: 20.0),
  FactoryTarget(itemId: "silica", rate: 30.0)
]
let plan1 = planProduction(targets1, rawResourceIds, initHashSet[string]())

let svg1 = renderSvgMap(plan1, allMapNodes, 1000.0, 1000.0)
echo "\nSVG 1 rendered length: ", svg1.len, " bytes"
echo "SVG 1 prefix: ", svg1[0..120]
doAssert svg1.contains("<svg id='ficsit-world-map-svg'"), "Missing root svg element"
doAssert svg1.contains("viewBox='0 0 1000 1000'"), "Missing viewBox"
doAssert svg1.contains("id='map-pan-zoom-layer'"), "Missing pan-zoom layer"
doAssert svg1.contains("map_bg.jpg") or svg1.contains("map_bg.webp"), "Missing optional map background image element"
doAssert svg1.contains("FICSIT RADAR SYS 1.0"), "Missing FICSIT HUD"
doAssert svg1.contains("Sub-fábrica Siderúrgica"), "Missing sub-factory marker badge"
doAssert svg1.contains("Sub-fábrica de Cuarzo"), "Missing quartz sub-factory marker"

echo "✅ SVG 1 content assertions passed!"

# Test Option Selection Switch:
var customOpts = initTable[string, int]()
customOpts["subfac_primary_1"] = 1 # Pick Option #2 (Titan Forest)
let svg1Opt2 = renderSvgMap(plan1, allMapNodes, customOpts, 1000.0, 1000.0)
doAssert svg1Opt2.contains("Titan Forest"), "Map should reflect Option #2 (Titan Forest) when selected!"
echo "✅ Dynamic option selection on SVG map verified!"

# 3. Test Plan 2 (Modular Engine with Logistics routes between modules)
let targets2 = @[
  FactoryTarget(itemId: "modular-engine", rate: 5.0)
]
let plan2 = planProduction(targets2, rawResourceIds, initHashSet[string]())
let svg2 = renderSvgMap(plan2, allMapNodes, 1000.0, 1000.0)

echo "\nSVG 2 rendered length: ", svg2.len, " bytes"
doAssert svg2.contains("id='logistics-routes'"), "Missing logistics routes group"
doAssert svg2.contains("RUTA LOGÍSTICA"), "Expected inter-module logistics routes in SVG"

echo "✅ SVG 2 logistics routes assertions passed!"
echo "\n🎉 ALL SVG MAP RENDERER TESTS PASSED!"
