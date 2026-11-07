import std/[tables, sets, sequtils, algorithm, math, strutils, strformat]
import dataset, types, planner, locator

echo "=== TESTING SPATIAL LOCATOR ENGINE (STAGE 3) ==="

# 1. Test getNodeExtractionRate
let sampleIronNormal = allMapNodes.filterIt(it.resourceId == "iron-ore" and it.purity == "normal")[0]
let sampleIronPure = allMapNodes.filterIt(it.resourceId == "iron-ore" and it.purity == "pure")[0]
let sampleIronImpure = allMapNodes.filterIt(it.resourceId == "iron-ore" and it.purity == "impure")[0]

doAssert getNodeExtractionRate(sampleIronNormal, 1) == 60.0
doAssert getNodeExtractionRate(sampleIronPure, 1) == 120.0
doAssert getNodeExtractionRate(sampleIronImpure, 1) == 30.0
doAssert getNodeExtractionRate(sampleIronNormal, 2) == 120.0
doAssert getNodeExtractionRate(sampleIronPure, 3) == 480.0
doAssert getNodeExtractionRate(sampleIronPure, 3, 2.5) == 1200.0
echo "✅ Extraction rate calculation tests passed!"

# 2. Test candidate location search for User's Example:
# Sub-fábrica Siderúrgica y Hormigón:
# iron-ore: 120.0, coal: 120.0, limestone: 180.0
var rawDemand = initTable[string, float]()
rawDemand["iron-ore"] = 120.0
rawDemand["coal"] = 120.0
rawDemand["limestone"] = 180.0

var steelMod = SubFactoryModule(
  id: "subfac_steel",
  name: "Sub-fábrica Siderúrgica y Hormigón",
  requiredRaw: rawDemand
)

echo "\n--- TESTING findOptimalLocations FOR STEEL & CONCRETE ---"
let recs = findOptimalLocations(steelMod, allMapNodes, 1)
echo "Total recommendations returned: ", recs.len
doAssert recs.len == 3, "Expected 3 distinct location recommendations"

for idx, r in recs:
  echo fmt"\nRecommendation #{idx+1}: {r.title}"
  echo fmt"  Biome: {r.biome} | Center: ({r.centerX:.1f}, {r.centerY:.1f}) | Score: {r.score:.1f}"
  echo fmt"  Avg Transport Distance: {r.logisticsDistanceMeters:.1f} m"
  echo fmt"  Explanation: {r.explanation}"
  echo "  Matched Nodes: ", r.matchedNodes.mapIt(it.resourceId & " (" & it.purity & ") in " & it.biome).join(", ")

# Check that distance between recommendations is >= 500 meters (50,000 cm)
for i in 0 ..< recs.len:
  for j in (i + 1) ..< recs.len:
    let dx = recs[i].centerX - recs[j].centerX
    let dy = recs[i].centerY - recs[j].centerY
    let distMeters = sqrt(dx*dx + dy*dy) / 100.0
    echo fmt"  Distance between #{i+1} and #{j+1}: {distMeters:.1f} m"
    doAssert distMeters >= 500.0, "Expected >= 500m separation between recommendations!"

echo "\n✅ Separation test passed! (All options are >= 500m apart)"

# 3. Test Quartz Sub-factory:
var quartzDemand = initTable[string, float]()
quartzDemand["raw-quartz"] = 51.33

var quartzMod = SubFactoryModule(
  id: "subfac_quartz",
  name: "Sub-fábrica de Cuarzo",
  requiredRaw: quartzDemand
)

echo "\n--- TESTING findOptimalLocations FOR QUARTZ ---"
let quartzRecs = findOptimalLocations(quartzMod, allMapNodes, 1)
echo "Total recommendations returned: ", quartzRecs.len
doAssert quartzRecs.len == 3

for idx, r in quartzRecs:
  echo fmt"  #{idx+1}: {r.title} ({r.biome}) - dist: {r.logisticsDistanceMeters:.1f}m - nodes: {r.matchedNodes.len}"

echo "\n🎉 ALL LOCATOR ENGINE TESTS PASSED!"
