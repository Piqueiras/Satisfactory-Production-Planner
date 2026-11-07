import std/[tables, sets, sequtils, algorithm, strutils, strformat]
import dataset, planner, types, locator

echo "=== TESTING END-TO-END PLAN PRODUCTION WITH SPATIAL RECOMMENDATIONS ==="

# Test 1: User's Example
let targets1 = @[
  FactoryTarget(itemId: "encased-industrial-beam", rate: 10.0),
  FactoryTarget(itemId: "quartz-crystal", rate: 20.0),
  FactoryTarget(itemId: "silica", rate: 30.0)
]
let plan1 = planProduction(targets1, rawResourceIds, initHashSet[string]())

echo "\n--- PLAN 1: Encased Industrial Beam + Quartz Crystal + Silica ---"
echo "Plan Success: ", plan1.success
echo "Total Sub-Factories: ", plan1.subFactories.len
doAssert plan1.subFactories.len == 2, "Expected exactly 2 sub-factories"

for sub in plan1.subFactories:
  echo fmt"\n🏭 Sub-Factory [{sub.id}]: {sub.name}"
  echo fmt"   Assigned Biome: {sub.assignedBiome} | Center: ({sub.centerX:.1f}, {sub.centerY:.1f})"
  echo fmt"   Top 3 Recommendations:"
  doAssert sub.recommendations.len == 3, "Expected 3 recommendations per sub-factory"
  for idx, rec in sub.recommendations:
    echo fmt"     #{idx+1} {rec.title} -> Score: {rec.score:.1f} | Avg Dist: {rec.logisticsDistanceMeters:.1f}m"
    echo fmt"        Explanation: {rec.explanation}"

# Test 2: Modular Engine (Space Elevator assembly)
let targets2 = @[
  FactoryTarget(itemId: "modular-engine", rate: 5.0)
]
let plan2 = planProduction(targets2, rawResourceIds, initHashSet[string]())

echo "\n--- PLAN 2: Modular Engine 5/m ---"
echo "Plan Success: ", plan2.success
echo "Total Sub-Factories: ", plan2.subFactories.len
doAssert plan2.subFactories.len == 4, "Expected 4 sub-factories (Assembly + Iron/Steel + Copper + Oil)"

let assemblyMod = plan2.subFactories.filterIt(it.requiredRaw.len == 0)[0]
echo fmt"\n🚀 Assembly Module [{assemblyMod.id}]: {assemblyMod.name}"
echo fmt"   Assigned Biome: {assemblyMod.assignedBiome}"
echo fmt"   Recommendations: {assemblyMod.recommendations.len}"
doAssert assemblyMod.recommendations.len > 0
for idx, rec in assemblyMod.recommendations:
  echo fmt"     #{idx+1} {rec.title}: {rec.explanation}"

echo "\n=========================================="
echo "🎉 ALL END-TO-END PLAN SPATIAL LOCATOR TESTS PASSED!"
