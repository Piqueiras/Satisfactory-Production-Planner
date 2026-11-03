import std/[tables, sets, sequtils, algorithm, math, strutils, strformat]
import types, dataset, simplex

# Raw resource cost weights for LP objective function
proc getRawResourceWeight(idStr: string): float =
  case idStr
  of "iron-ore": 1.0
  of "limestone": 1.0
  of "water": 1.0
  of "copper-ore": 1.5
  of "coal": 2.0
  of "caterium-ore": 4.0
  of "raw-quartz": 4.0
  of "crude-oil": 5.0
  of "nitrogen-gas": 5.0
  of "bauxite": 8.0
  of "sulfur": 10.0
  of "sam-ore": 20.0
  of "uranium": 50.0
  else: 10.0

proc formatClockConfig(count: float): string =
  if count <= 0.001:
    return "0"
  let fullCount = int(floor(count))
  let remainder = count - float(fullCount)
  if remainder < 0.005:
    return fmt"{fullCount} @ 100%"
  elif fullCount == 0:
    return fmt"1 @ {remainder * 100.0:.1f}%"
  else:
    let uniformClock = (count / float(fullCount + 1)) * 100.0
    return fmt"{fullCount} @ 100% + 1 @ {remainder * 100.0:.1f}%  (or {fullCount + 1} @ {uniformClock:.1f}%)"

proc suggestMiner(rawItem: string, rate: float): string =
  case rawItem
  of "water":
    let extractors = rate / 120.0 # 120 m³/min
    return fmt"{extractors:.1f}x Water Extractor (120 m³/min)"
  of "crude-oil":
    let extractors = rate / 120.0 # 120 m³/min on normal
    return fmt"{extractors:.1f}x Oil Extractor (Normal node: 120 m³/min)"
  of "nitrogen-gas":
    let wells = rate / 120.0
    return fmt"{wells:.1f}x Resource Well Extractor (Normal node)"
  else:
    # Solid ores
    let mk1 = rate / 60.0
    let mk2 = rate / 120.0
    let mk3 = rate / 240.0
    if rate <= 120.0:
      return fmt"{mk1:.1f}x Mk.1 (60/m) or {mk2:.1f}x Mk.2 (120/m)"
    elif rate <= 480.0:
      return fmt"{mk2:.1f}x Mk.2 (120/m) or {mk3:.1f}x Mk.3 (240/m)"
    else:
      return fmt"{mk3:.1f}x Mk.3 (240/m Normal / 480/m Pure)"

proc hasReach(startNode, endNode: string, edges: seq[FlowEdge], visited: var HashSet[string]): bool =
  if startNode == endNode: return true
  visited.incl(startNode)
  for e in edges:
    if e.fromNode == startNode:
      if e.toNode == endNode: return true
      if not visited.contains(e.toNode):
        if hasReach(e.toNode, endNode, edges, visited):
          return true
  return false

proc isBackEdge(u, v: string, edges: seq[FlowEdge]): bool =
  var visited = initHashSet[string]()
  return hasReach(v, u, edges, visited)

proc planProduction*(targets: seq[FactoryTarget], enabledAlts: HashSet[string]): FactoryPlan =
  var plan = FactoryPlan()
  plan.targets = targets

  if targets.len == 0:
    plan.success = true
    return plan

  # 1. Reverse traversal to collect candidate recipes and items
  var targetTable = initTable[string, float]()
  var relevantItems = initHashSet[string]()
  var queue: seq[string] = @[]

  for t in targets:
    if t.rate > 0.0:
      targetTable[t.itemId] = targetTable.getOrDefault(t.itemId, 0.0) + t.rate
      if not relevantItems.contains(t.itemId):
        relevantItems.incl(t.itemId)
        queue.add(t.itemId)

  if queue.len == 0:
    plan.success = true
    return plan

  var candidateRecipes: seq[Recipe] = @[]
  var visitedRecipes = initHashSet[string]()

  while queue.len > 0:
    let currItem = queue.pop()
    for _, rec in allRecipes:
      if rec.outputs.hasKey(currItem):
        # Check alternate recipe permission
        if rec.isAlternate and not enabledAlts.contains(rec.id):
          continue
        if not visitedRecipes.contains(rec.id):
          visitedRecipes.incl(rec.id)
          candidateRecipes.add(rec)
          for inItem, _ in rec.inputs:
            if not relevantItems.contains(inItem):
              relevantItems.incl(inItem)
              queue.add(inItem)
          for outItem, _ in rec.outputs:
            if not relevantItems.contains(outItem):
              relevantItems.incl(outItem)

  # Separate raw extraction vs manufacturing recipes
  var craftRecipes: seq[Recipe] = @[]
  for r in candidateRecipes:
    # Skip raw mining recipes from craft list so they are handled as explicit extraction variables
    if not r.isMining and r.inputs.len > 0:
      craftRecipes.add(r)

  # Index items
  var itemList: seq[string] = @[]
  var itemIndex = initTable[string, int]()
  for it in relevantItems:
    itemIndex[it] = itemList.len
    itemList.add(it)

  # Determine raw resources among relevant items
  var rawResourcesInPlan: seq[string] = @[]
  for it in itemList:
    if rawResourceIds.contains(it):
      # Items that can be supplied by the map
      rawResourcesInPlan.add(it)

  let nCraft = craftRecipes.len
  let nRaw = rawResourcesInPlan.len
  let nVars = nCraft + nRaw
  let nItems = itemList.len

  if nCraft == 0 and nRaw == 0:
    plan.success = false
    plan.errorMessage = "No valid recipes found to produce the selected items."
    return plan

  # 2. Build Simplex matrices
  var A = newSeqWith(nItems, newSeq[float](nVars))
  var c = newSeq[float](nVars)

  # Crafting recipes:
  for j in 0 ..< nCraft:
    let r = craftRecipes[j]
    let mult = 60.0 / r.time # cycles/min per 1 machine
    c[j] = 0.001 # small machine penalty to avoid useless loops and minimize buildings

    for outItem, amt in r.outputs:
      let i = itemIndex[outItem]
      A[i][j] += amt * mult

    for inItem, amt in r.inputs:
      let i = itemIndex[inItem]
      A[i][j] -= amt * mult

  # Raw resources extraction variables:
  for k in 0 ..< nRaw:
    let j = nCraft + k
    let rawItem = rawResourcesInPlan[k]
    let i = itemIndex[rawItem]
    A[i][j] = 1.0 # 1 unit per minute
    c[j] = getRawResourceWeight(rawItem)

  # Target demands
  var b = newSeq[float](nItems)
  for it, rate in targetTable:
    if itemIndex.hasKey(it):
      b[itemIndex[it]] = rate

  # 3. Solve Simplex
  let sol = solveDualSimplex(A, b, c)

  if not sol.success:
    plan.success = false
    plan.errorMessage = sol.errorMessage
    return plan

  plan.success = true

  # 4. Extract results
  var totalBuildings = 0.0
  var totalPowerMW = 0.0

  # Production steps
  for j in 0 ..< nCraft:
    let count = sol.x[j]
    if count > 0.0001:
      let r = craftRecipes[j]
      var step = ProductionStep()
      step.recipeId = r.id
      step.recipeName = r.name
      step.buildingCount = count
      step.clockConfig = formatClockConfig(count)

      let machineId = if r.producers.len > 0: r.producers[0] else: "assembler"
      step.machineId = machineId
      step.machineName = getMachineName(machineId)
      let basePower = getMachinePower(machineId)
      step.powerMW = count * basePower
      totalPowerMW += step.powerMW
      totalBuildings += count

      step.inputs = initTable[string, float]()
      for inItem, rate100 in r.ratesIn:
        step.inputs[inItem] = rate100 * count

      step.outputs = initTable[string, float]()
      for outItem, rate100 in r.ratesOut:
        step.outputs[outItem] = rate100 * count

      plan.steps.add(step)

  # Sort steps by machine category & building count
  plan.steps.sort(proc(a, b: ProductionStep): int =
    cmp(b.buildingCount, a.buildingCount)
  )

  # Raw resources
  for k in 0 ..< nRaw:
    let j = nCraft + k
    let rate = sol.x[j]
    if rate > 0.0001:
      let rawId = rawResourcesInPlan[k]
      var req = ResourceRequirement()
      req.itemId = rawId
      req.itemName = getItemName(rawId)
      req.rate = rate
      req.suggestedMiners = suggestMiner(rawId, rate)
      plan.rawResources.add(req)

  plan.rawResources.sort(proc(a, b: ResourceRequirement): int =
    cmp(b.rate, a.rate)
  )

  # Byproducts / Surplus
  for i in 0 ..< nItems:
    let surplusRate = sol.surplus[i]
    if surplusRate > 0.001:
      let itemId = itemList[i]
      var sur = SurplusInfo()
      sur.itemId = itemId
      sur.itemName = getItemName(itemId)
      sur.rate = surplusRate
      sur.status = if rawResourceIds.contains(itemId):
                     "Raw resource unextracted"
                   elif itemId == "water" or itemId == "heavy-oil-residue" or itemId == "polymer-resin":
                     "Recyclable byproduct / AWESOME Sink"
                   else:
                     "Excess intermediate (can feed AWESOME Sink)"
      plan.byproducts.add(sur)

  plan.totalBuildings = totalBuildings
  plan.totalPowerMW = totalPowerMW

  # 5. Build Flow Graph (DAG) for visualization
  # Nodes: Raw, Steps, Targets, Byproducts
  var nodeMap = initTable[string, FlowNode]()
  var stepNodeIds: seq[string] = @[]

  # Raw resource nodes (Tier 0)
  for req in plan.rawResources:
    let nid = "raw_" & req.itemId
    let fn = FlowNode(
      id: nid,
      kind: "raw",
      title: req.itemName,
      subtitle: fmt"{req.rate:.1f} / min",
      color: getItemColor(req.itemId),
      tier: 0,
      inputsSummary: "From Nature",
      outputsSummary: fmt"{req.rate:.1f}/m"
    )
    nodeMap[nid] = fn

  # Production step nodes (Tier 1 .. n)
  for idx, st in plan.steps:
    let nid = "step_" & st.recipeId
    stepNodeIds.add(nid)
    let fn = FlowNode(
      id: nid,
      kind: "step",
      title: st.recipeName,
      subtitle: fmt"{st.buildingCount:.2f}x {st.machineName} ({st.powerMW:.1f} MW)",
      color: "#FA9549",
      tier: 1, # will compute topological depth below
      inputsSummary: "",
      outputsSummary: ""
    )
    nodeMap[nid] = fn

  # Target nodes (Tier 99)
  for tg in plan.targets:
    if tg.rate > 0.0:
      let nid = "target_" & tg.itemId
      let fn = FlowNode(
        id: nid,
        kind: "target",
        title: getItemName(tg.itemId),
        subtitle: fmt"Target: {tg.rate:.1f} / min",
        color: getItemColor(tg.itemId),
        tier: 99,
        inputsSummary: fmt"{tg.rate:.1f}/m",
        outputsSummary: "Final Output"
      )
      nodeMap[nid] = fn

  # Calculate flow edges:
  # For each item, total production comes from (raw resources + steps).
  # Total consumption goes to (steps + target demands + surplus).
  var itemProducers = initTable[string, seq[tuple[nodeId: string, rate: float]]]()
  var itemConsumers = initTable[string, seq[tuple[nodeId: string, rate: float]]]()

  for req in plan.rawResources:
    let nid = "raw_" & req.itemId
    var list = itemProducers.getOrDefault(req.itemId, @[])
    list.add((nid, req.rate))
    itemProducers[req.itemId] = list

  for st in plan.steps:
    let nid = "step_" & st.recipeId
    for outIt, rOut in st.outputs:
      var list = itemProducers.getOrDefault(outIt, @[])
      list.add((nid, rOut))
      itemProducers[outIt] = list
    for inIt, rIn in st.inputs:
      var list = itemConsumers.getOrDefault(inIt, @[])
      list.add((nid, rIn))
      itemConsumers[inIt] = list

  for tg in plan.targets:
    if tg.rate > 0.0:
      let nid = "target_" & tg.itemId
      var list = itemConsumers.getOrDefault(tg.itemId, @[])
      list.add((nid, tg.rate))
      itemConsumers[tg.itemId] = list

  # Distribute flow proportionally
  for it, producers in itemProducers:
    let consumers = itemConsumers.getOrDefault(it, @[])
    var totalProd = 0.0
    for p in producers:
      totalProd += p.rate

    if totalProd > 0.0001:
      for c in consumers:
        for p in producers:
          let flowRate = c.rate * (p.rate / totalProd)
          if flowRate > 0.001:
            var edge = FlowEdge()
            edge.fromNode = p.nodeId
            edge.toNode = c.nodeId
            edge.itemId = it
            edge.itemName = getItemName(it)
            edge.rate = flowRate
            plan.edges.add(edge)

  # Compute topological tier depth for clean DAG columns:
  # Raw nodes: tier = 0
  # For steps: tier = 1 + max(producer tier)
  var nodeTiers = initTable[string, int]()
  for req in plan.rawResources:
    nodeTiers["raw_" & req.itemId] = 0

  # Relax tiers across edges iteratively, ignoring back-edges (byproduct feedback loops)
  var maxTier = 1
  for _ in 0 ..< 20:
    var changed = false
    for e in plan.edges:
      if e.toNode.startsWith("target_"): continue
      # Feedback loop check: if toNode can already reach fromNode, e is a back-edge
      if isBackEdge(e.fromNode, e.toNode, plan.edges):
        continue

      let fromT = nodeTiers.getOrDefault(e.fromNode, 0)
      let currToT = nodeTiers.getOrDefault(e.toNode, 0)
      if fromT + 1 > currToT:
        nodeTiers[e.toNode] = fromT + 1
        changed = true
        if fromT + 1 > maxTier:
          maxTier = fromT + 1
    if not changed: break

  # Assign updated tiers
  for nid, fn in nodeMap:
    var updated = fn
    if fn.kind == "raw":
      updated.tier = 0
    elif fn.kind == "target":
      updated.tier = maxTier + 1
    else:
      updated.tier = max(1, nodeTiers.getOrDefault(nid, 1))
    nodeMap[nid] = updated

  for _, fn in nodeMap:
    plan.nodes.add(fn)

  plan.nodes.sort(proc(a, b: FlowNode): int =
    if a.tier != b.tier: cmp(a.tier, b.tier)
    else: cmp(a.title, b.title)
  )

  return plan

