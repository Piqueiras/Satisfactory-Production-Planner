import std/[tables, sets, sequtils, algorithm]
import dataset, planner, types

echo "=== TESTING FACTORY CONSTRAINTS & RESOURCE AVAILABILITY ==="

# Test 1: Standard Wire with all resources enabled
let allRaws = rawResourceIds
let noAlts = initHashSet[string]()
let plan1 = planProduction(@[FactoryTarget(itemId: "wire", rate: 60.0)], allRaws, noAlts)
doAssert plan1.success, "Plan 1 should succeed"
echo "Plan 1 (Standard Wire):"
for r in plan1.rawResources:
  echo "  Raw: ", r.itemName, " ", r.rate, "/m"
doAssert plan1.rawResources[0].itemId == "copper-ore"

# Test 2: Wire with Copper Ore DISABLED, and no alternates
var noCopperRaws = allRaws
noCopperRaws.excl("copper-ore")
let plan2 = planProduction(@[FactoryTarget(itemId: "wire", rate: 60.0)], noCopperRaws, noAlts)
doAssert not plan2.success, "Plan 2 should fail because copper is disabled"
echo "Plan 2 Error (as expected): ", plan2.errorMessage

# Test 3: Wire with Copper Ore DISABLED, but Iron Wire alternate ENABLED!
var ironWireAlts = initHashSet[string]()
ironWireAlts.incl("wire-iron") # alternate recipe ID
let plan3 = planProduction(@[FactoryTarget(itemId: "wire", rate: 60.0)], noCopperRaws, ironWireAlts)
doAssert plan3.success, "Plan 3 should succeed using Iron Wire alternate"
echo "Plan 3 (Iron Wire only):"
for r in plan3.rawResources:
  echo "  Raw: ", r.itemName, " ", r.rate, "/m"
doAssert plan3.rawResources.len == 1 and plan3.rawResources[0].itemId == "iron-ore"
echo "  Step: ", plan3.steps[0].recipeName

echo "\nAll constraint tests PASSED successfully!"
