import std/[tables, sets, sequtils, algorithm, strutils, strformat]
import dataset, planner, types, locator

echo "=== VERIFYING STAGE 2: SUB-FACTORY PARTITIONING ==="

# Test 1: User's specification example:
# "Quartz Crystal" / "Silica" (solo dependen de Raw Quartz) y "Encased Industrial Beam" (depende de Iron Ore, Coal y Limestone)
# Expected: Exactly 2 sub-factories, 0 assembly modules.
let targets1 = @[
  FactoryTarget(itemId: "encased-industrial-beam", rate: 10.0),
  FactoryTarget(itemId: "quartz-crystal", rate: 20.0),
  FactoryTarget(itemId: "silica", rate: 30.0)
]
let plan1 = planProduction(targets1, rawResourceIds, initHashSet[string]())
let modules1 = partitionIntoSubFactories(plan1, 1)

echo "\n--- TEST 1: User Example (Encased Beam + Quartz Crystal + Silica) ---"
echo "Total sub-factories detected: ", modules1.len
doAssert modules1.len == 2, "Expected exactly 2 sub-factories for Test 1"

for m in modules1:
  echo fmt"\n* Module [{m.id}]: {m.name}"
  echo "  Steps: ", m.steps.mapIt(it.recipeName).join(", ")
  var raws: seq[string] = @[]
  for r, rate in m.requiredRaw:
    raws.add(fmt"{getItemName(r)}: {rate:.1f}/m")
  echo "  Required Raw: ", raws.join(", ")
  var prods: seq[string] = @[]
  for p in m.producedItems:
    prods.add(fmt"{getItemName(p.itemId)}: {p.rate:.1f}/m")
  echo "  Produced Items: ", prods.join(", ")

# Verify Test 1 content:
let quartzMod = modules1.filterIt(it.requiredRaw.hasKey("raw-quartz"))[0]
let steelMod = modules1.filterIt(it.requiredRaw.hasKey("iron-ore"))[0]

doAssert quartzMod.requiredRaw["raw-quartz"] > 51.0 and quartzMod.requiredRaw["raw-quartz"] < 52.0
doAssert quartzMod.producedItems.anyIt(it.itemId == "quartz-crystal" and it.rate == 20.0)
doAssert quartzMod.producedItems.anyIt(it.itemId == "silica" and it.rate == 30.0)

doAssert steelMod.requiredRaw.hasKey("iron-ore")
doAssert steelMod.requiredRaw.hasKey("coal")
doAssert steelMod.requiredRaw.hasKey("limestone")
doAssert steelMod.producedItems.anyIt(it.itemId == "encased-industrial-beam" and it.rate == 10.0)

echo "✅ Test 1 Passed Perfectly!"

# Test 2: Crystal Oscillator (multi-basin convergence into assembly hub)
let targets2 = @[
  FactoryTarget(itemId: "crystal-oscillator", rate: 5.0)
]
let plan2 = planProduction(targets2, rawResourceIds, initHashSet[string]())
let modules2 = partitionIntoSubFactories(plan2, 1)

echo "\n--- TEST 2: Multi-Basin Convergence (Crystal Oscillator) ---"
echo "Total sub-factories detected: ", modules2.len
doAssert modules2.len == 4, "Expected 4 modules (Assembly + Iron + Copper + Quartz)"

let assemblyMod2 = modules2.filterIt(it.id.startsWith("subfac_assembly"))[0]
doAssert assemblyMod2.requiredRaw.len == 0, "Assembly module should not mine raw resources directly"
doAssert assemblyMod2.producedItems.anyIt(it.itemId == "crystal-oscillator" and it.rate == 5.0)

for m in modules2:
  var prods = m.producedItems.mapIt(it.itemId & " " & $it.rate & "/m").join(", ")
  echo fmt"* [{m.id}] {m.name} -> produced: {prods}"

echo "✅ Test 2 Passed Perfectly!"

# Test 3: Modular Engine (Manufacturer combining Smart Plating [Iron], Motor [Iron+Copper+Coal], Rubber [Oil])
let targets3 = @[
  FactoryTarget(itemId: "modular-engine", rate: 5.0)
]
let plan3 = planProduction(targets3, rawResourceIds, initHashSet[string]())
let modules3 = partitionIntoSubFactories(plan3, 1)

echo "\n--- TEST 3: Space Elevator Complex (Modular Engine) ---"
echo "Total sub-factories detected: ", modules3.len
doAssert modules3.len == 4, "Expected 4 modules (Assembly + Oil + Copper + Steel/Iron)"

let oilMod3 = modules3.filterIt(it.requiredRaw.hasKey("crude-oil"))[0]
doAssert oilMod3.producedItems.anyIt(it.itemId == "rubber" and it.rate == 75.0)
echo "✅ Test 3 Passed Perfectly!"

echo "\n=========================================="
echo "🎉 ALL SUB-FACTORY PARTITIONING TESTS PASSED!"
