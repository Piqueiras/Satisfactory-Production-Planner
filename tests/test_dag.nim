import dataset, planner, types, presets, svg_graph, tables, sequtils, algorithm, sets

echo "=== TESTING PRODUCTION TIERS & DAG GENERATION ==="
let ps = getPresets()
for p in ps:
  echo "\nTesting Preset: ", p.name
  let altsSet = p.enabledAlts.toHashSet()
  let plan = planProduction(p.targets, altsSet)
  echo "  Success: ", plan.success, " | Steps: ", plan.steps.len, " | Nodes: ", plan.nodes.len, " | Edges: ", plan.edges.len
  
  var tiers: seq[int] = @[]
  for n in plan.nodes:
    if not tiers.contains(n.tier): tiers.add(n.tier)
  tiers.sort()
  echo "  Distinct Tiers (Columns): ", tiers.len, " -> ", tiers
  
  let svg = renderSvgGraph(plan)
  let board = renderStageBreakdown(plan)
  echo "  SVG bytes: ", svg.len, " | Board bytes: ", board.len

  # Assert that multi-step presets have more than 2 or 3 tiers!
  if p.targets.len > 0 and plan.steps.len >= 3:
    doAssert tiers.len >= 3, "Expected at least 3 distinct tiers for " & p.name
    doAssert tiers[tiers.len - 1] > 2, "Expected max tier > 2 for " & p.name
