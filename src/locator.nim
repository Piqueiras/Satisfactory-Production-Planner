import std/[tables, sets, sequtils, algorithm, math, strutils, strformat]
import types, dataset

# Raw resource affinity classification:
# Groups foundational terrestrial ores, while keeping specialized regional resources distinct
proc getRawBasin(rawId: string): string =
  case rawId
  of "raw-quartz": "quartz"
  of "crude-oil": "oil"
  of "bauxite": "bauxite"
  of "caterium-ore": "caterium"
  of "uranium": "uranium"
  of "nitrogen-gas": "nitrogen"
  of "copper-ore": "copper"
  of "sulfur": "sulfur"
  of "sam-ore": "sam"
  of "iron-ore", "coal", "limestone", "water": "terrestrial_steel"
  else: rawId

# Helper to generate a friendly descriptive name for a primary/intermediate module
proc getPrimaryModuleName(clusterRaws: HashSet[string]): string =
  var rawList = toSeq(clusterRaws)
  rawList.sort()
  if rawList == @["raw-quartz"]:
    return "Sub-fábrica de Cuarzo"
  elif rawList == @["crude-oil"]:
    return "Sub-fábrica Petroquímica"
  elif rawList == @["copper-ore"]:
    return "Sub-fábrica de Cobre"
  elif rawList == @["iron-ore"]:
    return "Sub-fábrica de Hierro"
  elif rawList == @["caterium-ore"]:
    return "Sub-fábrica de Caterium"
  elif rawList == @["bauxite"]:
    return "Sub-fábrica de Bauxita / Aluminio"
  elif rawList == @["uranium"]:
    return "Sub-fábrica Nuclear"
  elif clusterRaws.contains("coal") and clusterRaws.contains("iron-ore"):
    if clusterRaws.contains("limestone"):
      return "Sub-fábrica Siderúrgica y Hormigón (Hierro, Carbón, Caliza)"
    else:
      return "Sub-fábrica Siderúrgica (Hierro y Carbón)"
  elif clusterRaws.contains("iron-ore") and clusterRaws.contains("limestone"):
    return "Sub-fábrica Metalúrgica y Hormigón (Hierro y Caliza)"
  else:
    var rawNames: seq[string] = @[]
    for r in rawList:
      rawNames.add(getItemName(r))
    let joined = rawNames.join(", ")
    return fmt"Sub-fábrica de Procesamiento ({joined})"

proc getNodeExtractionRate*(node: ResourceNode, minerMk: int = 1, clockSpeed: float = 1.0): float =
  ## Calculates extraction rate in items/min (or m³/min for fluids) for a given node,
  ## miner tier (Mk.1, Mk.2, Mk.3) and clock speed (1.0 = 100%, 2.5 = 250%).
  let purityMult = case node.purity
    of "impure": 0.5
    of "pure": 2.0
    else: 1.0 # "normal"

  let baseRate = case node.resourceId
    of "crude-oil": 120.0
    of "water": 120.0
    of "nitrogen-gas": 120.0
    else:
      case minerMk
      of 2: 120.0
      of 3: 240.0
      else: 60.0 # Mk.1

  return baseRate * purityMult * clockSpeed

type
  LocationCandidate = object
    centerX: float
    centerY: float
    centerZ: float
    biome: string
    score: float
    avgDistMeters: float
    totalCost: float
    matchedNodes: seq[ResourceNode]
    nodeAllocations: seq[tuple[node: ResourceNode, rate: float]]

proc findOptimalLocations*(module: SubFactoryModule,
                           allNodes: seq[ResourceNode],
                           minerMk: int = 1,
                           clockSpeed: float = 1.0,
                           supplierModules: seq[SubFactoryModule] = @[]): seq[LocationRecommendation] =
  ## Evaluates all map resource nodes to find the Top 3 optimal locations for a SubFactoryModule.
  ## For primary modules, searches for local node clusters minimizing 3D transport logistics.
  ## For pure assembly modules, co-locates with the heaviest intermediate supplier sub-factory.
  ## Enforces at least 500m separation between the Top 3 locations.

  # Case 1: Pure Assembly Module (no virgin raw extraction directly from the ground)
  if module.requiredRaw.len == 0:
    # Find supplier that provides the greatest volume of parts to this module
    var maxSupplierRate = 0.0
    var bestSupplierIdx = -1

    for sIdx, sup in supplierModules:
      if sup.id == module.id: continue
      var supRateToMod = 0.0
      for prod in sup.producedItems:
        for st in module.steps:
          if st.inputs.hasKey(prod.itemId):
            supRateToMod += min(prod.rate, st.inputs[prod.itemId])
      if supRateToMod > maxSupplierRate:
        maxSupplierRate = supRateToMod
        bestSupplierIdx = sIdx

    if bestSupplierIdx >= 0 and supplierModules[bestSupplierIdx].recommendations.len > 0:
      let topSup = supplierModules[bestSupplierIdx]
      var recs: seq[LocationRecommendation] = @[]
      for k, supRec in topSup.recommendations:
        var rec = LocationRecommendation(
          id: fmt"{module.id}_loc_{k+1}",
          title: fmt"Opción {k+1}: {supRec.biome} (Co-localizado)",
          biome: supRec.biome,
          centerX: supRec.centerX,
          centerY: supRec.centerY,
          score: supRec.score,
          matchedNodes: @[],
          logisticsDistanceMeters: 0.0,
          explanation: fmt"Co-localizado con '{topSup.name}' para eliminar el transporte de {maxSupplierRate:.1f} items/min del insumo principal."
        )
        recs.add(rec)
      return recs

    # Default fallback strategic assembly hubs if standalone
    return @[
      LocationRecommendation(
        id: fmt"{module.id}_loc_1",
        title: "Opción 1: Northern Forest (Hub Central Óptimo)",
        biome: "Northern Forest",
        centerX: -25000.0,
        centerY: -110000.0,
        score: 95.0,
        matchedNodes: @[],
        logisticsDistanceMeters: 0.0,
        explanation: "Ubicación central con accesos ferroviarios rápidos a cuencas de cuarzo, carbón, hierro y petróleo."
      ),
      LocationRecommendation(
        id: fmt"{module.id}_loc_2",
        title: "Opción 2: Dune Desert (Gran Llanura)",
        biome: "Dune Desert",
        centerX: 230000.0,
        centerY: -140000.0,
        score: 90.0,
        matchedNodes: @[],
        logisticsDistanceMeters: 0.0,
        explanation: "Área llana masiva ideal para megaconstrucciones de fábricas modulares y centros de ensamblaje."
      ),
      LocationRecommendation(
        id: fmt"{module.id}_loc_3",
        title: "Opción 3: Grass Fields (Meseta Principal)",
        biome: "Grass Fields",
        centerX: -120000.0,
        centerY: 150000.0,
        score: 85.0,
        matchedNodes: @[],
        logisticsDistanceMeters: 0.0,
        explanation: "Meseta amplia y despejada para ensamblaje intermedio y conexión directa al Ascensor Espacial."
      )
    ]

  # Case 2: Primary / Intermediate Sub-Factory Module with virgin resource requirements
  # Pre-filter nodes by required resources
  var requiredResources: seq[string] = @[]
  var nodesByReq = initTable[string, seq[ResourceNode]]()
  for rId, _ in module.requiredRaw:
    requiredResources.add(rId)
    nodesByReq[rId] = allNodes.filterIt(it.resourceId == rId)

  # Collect candidate search seeds from all nodes of the required minerals
  var searchSeeds: seq[tuple[x: float, y: float]] = @[]
  for rId in requiredResources:
    for n in nodesByReq.getOrDefault(rId, @[]):
      searchSeeds.add((n.x, n.y))

  if searchSeeds.len == 0:
    return @[]

  var validCandidates: seq[LocationCandidate] = @[]

  for seed in searchSeeds:
    var matchedNodes: seq[ResourceNode] = @[]
    var allocations: seq[tuple[node: ResourceNode, rate: float]] = @[]
    var candidateFeasible = true

    for rId, neededDemand in module.requiredRaw:
      let availNodes = nodesByReq.getOrDefault(rId, @[])
      # Sort available nodes of this resource by 2D distance to the seed point
      var nodesWithDist: seq[tuple[node: ResourceNode, distSq: float]] = @[]
      for n in availNodes:
        let dx = n.x - seed.x
        let dy = n.y - seed.y
        nodesWithDist.add((n, dx * dx + dy * dy))
      nodesWithDist.sort(proc(a, b: tuple[node: ResourceNode, distSq: float]): int =
        cmp(a.distSq, b.distSq)
      )

      var remaining = neededDemand
      for item in nodesWithDist:
        let nodeCap = getNodeExtractionRate(item.node, minerMk, clockSpeed)
        let alloc = min(nodeCap, remaining)
        allocations.add((item.node, alloc))
        matchedNodes.add(item.node)
        remaining -= alloc
        if remaining <= 0.001:
          break

      if remaining > 0.001:
        candidateFeasible = false
        break

    if not candidateFeasible:
      continue

    # Calculate weighted 3D centroid of the selected nodes
    var sumX = 0.0
    var sumY = 0.0
    var sumZ = 0.0
    var totalAllocatedRate = 0.0

    for a in allocations:
      sumX += a.node.x * a.rate
      sumY += a.node.y * a.rate
      sumZ += a.node.z * a.rate
      totalAllocatedRate += a.rate

    let cX = if totalAllocatedRate > 0: sumX / totalAllocatedRate else: seed.x
    let cY = if totalAllocatedRate > 0: sumY / totalAllocatedRate else: seed.y
    let cZ = if totalAllocatedRate > 0: sumZ / totalAllocatedRate else: 0.0

    # Calculate logistics score: 2D distance + 20% vertical elevation penalty (in meters)
    var totalWeightedMeters = 0.0
    for a in allocations:
      let dxMeters = (a.node.x - cX) / 100.0
      let dyMeters = (a.node.y - cY) / 100.0
      let dzMeters = abs(a.node.z - cZ) / 100.0
      let dist2D = sqrt(dxMeters * dxMeters + dyMeters * dyMeters)
      let effectiveMeters = dist2D + 0.20 * dzMeters
      totalWeightedMeters += effectiveMeters * a.rate

    let avgDistMeters = if totalAllocatedRate > 0: totalWeightedMeters / totalAllocatedRate else: 0.0
    let score = max(5.0, min(100.0, 100.0 - (avgDistMeters / 10.0)))

    # Determine dominant biome among matched nodes
    var biomeCounts = initTable[string, float]()
    for a in allocations:
      biomeCounts[a.node.biome] = biomeCounts.getOrDefault(a.node.biome, 0.0) + a.rate
    var dominantBiome = "World"
    var maxB = -1.0
    for bName, bRate in biomeCounts:
      if bRate > maxB:
        maxB = bRate
        dominantBiome = bName

    var cand = LocationCandidate(
      centerX: cX,
      centerY: cY,
      centerZ: cZ,
      biome: dominantBiome,
      score: score,
      avgDistMeters: avgDistMeters,
      totalCost: totalWeightedMeters,
      matchedNodes: matchedNodes,
      nodeAllocations: allocations
    )
    validCandidates.add(cand)

  # Sort candidates by lowest logistics cost (best first)
  validCandidates.sort(proc(a, b: LocationCandidate): int =
    cmp(a.totalCost, b.totalCost)
  )

  # Spatial diversity filtering: minimum 500 meters (50,000 cm) separation between recommendations
  const minSeparationCm = 500.0 * 100.0
  var topCandidates: seq[LocationCandidate] = @[]

  for c in validCandidates:
    var tooClose = false
    for accepted in topCandidates:
      let dx = c.centerX - accepted.centerX
      let dy = c.centerY - accepted.centerY
      let dist = sqrt(dx * dx + dy * dy)
      if dist < minSeparationCm:
        tooClose = true
        break
    if not tooClose:
      topCandidates.add(c)
      if topCandidates.len == 3:
        break

  # If less than 3 due to strict 500m separation (e.g. rare resources like Uranium), relax separation
  if topCandidates.len < 3:
    for c in validCandidates:
      var tooClose = false
      for accepted in topCandidates:
        let dx = c.centerX - accepted.centerX
        let dy = c.centerY - accepted.centerY
        if sqrt(dx * dx + dy * dy) < 100.0 * 100.0: # 100m minimum
          tooClose = true
          break
      if not tooClose:
        topCandidates.add(c)
        if topCandidates.len == 3:
          break

  # Format output LocationRecommendation list
  var recommendations: seq[LocationRecommendation] = @[]
  for idx, c in topCandidates:
    # Summarize matched nodes by resource and purity
    var summaryMap = initTable[string, int]()
    for a in c.nodeAllocations:
      let key = fmt"{getItemName(a.node.resourceId)} ({a.node.purity.capitalizeAscii()})"
      summaryMap[key] = summaryMap.getOrDefault(key, 0) + 1
    var summaryParts: seq[string] = @[]
    for k, count in summaryMap:
      summaryParts.add(fmt"{count}x {k}")
    let nodesSummary = summaryParts.join(", ")

    let title = if idx == 0:
                  fmt"Opción 1: {c.biome} (Óptima)"
                else:
                  fmt"Opción {idx+1}: {c.biome}"

    let explanation = fmt"Distancia media de transporte: {c.avgDistMeters:.1f}m. Nodos: {nodesSummary}."

    var rec = LocationRecommendation(
      id: fmt"{module.id}_loc_{idx+1}",
      title: title,
      biome: c.biome,
      centerX: c.centerX,
      centerY: c.centerY,
      score: round(c.score, 1),
      matchedNodes: c.matchedNodes,
      logisticsDistanceMeters: round(c.avgDistMeters, 1),
      explanation: explanation
    )
    recommendations.add(rec)

  return recommendations

proc partitionIntoSubFactories*(plan: FactoryPlan, minerMk: int = 1): seq[SubFactoryModule] =
  ## Partitions a FactoryPlan DAG into logical modular sub-factories
  ## based on raw resource affinities, transport volume compression, and assembly steps.
  if not plan.success or plan.steps.len == 0:
    return @[]

  # 1. Build adjacency lookups (predecessors and successors)
  var preds = initTable[string, seq[FlowEdge]]()
  var succs = initTable[string, seq[FlowEdge]]()
  for e in plan.edges:
    var p = preds.getOrDefault(e.toNode, @[])
    p.add(e)
    preds[e.toNode] = p
    var s = succs.getOrDefault(e.fromNode, @[])
    s.add(e)
    succs[e.fromNode] = s

  # 2. Compute Raw Ancestors for each node in the DAG
  var rawAncestors = initTable[string, HashSet[string]]()
  for req in plan.rawResources:
    rawAncestors["raw_" & req.itemId] = [req.itemId].toHashSet()

  var visitedAncestors = initHashSet[string]()
  proc getRawAncestors(nodeId: string): HashSet[string] =
    if rawAncestors.hasKey(nodeId): return rawAncestors[nodeId]
    var res = initHashSet[string]()
    for e in preds.getOrDefault(nodeId, @[]):
      if e.fromNode.startsWith("raw_"):
        res.incl(e.itemId)
      else:
        if not visitedAncestors.contains(e.fromNode):
          visitedAncestors.incl(e.fromNode)
          let up = getRawAncestors(e.fromNode)
          visitedAncestors.excl(e.fromNode)
          res = res + up
    rawAncestors[nodeId] = res
    return res

  for s in plan.steps:
    discard getRawAncestors("step_" & s.recipeId)

  # 3. Determine Raw Basins touched by each step
  var stepBasins = initTable[string, HashSet[string]]()
  for s in plan.steps:
    let nid = "step_" & s.recipeId
    var basins = initHashSet[string]()
    for r in rawAncestors.getOrDefault(nid, initHashSet[string]()):
      basins.incl(getRawBasin(r))
    stepBasins[nid] = basins

  # 4. Identify Assembly Steps:
  # Steps that combine inputs from 2+ distinct raw basins and do not mine directly from raw nodes
  var assemblySteps = initHashSet[string]()
  for s in plan.steps:
    let nid = "step_" & s.recipeId
    let b = stepBasins.getOrDefault(nid, initHashSet[string]())
    if b.len >= 2:
      var hasRawInput = false
      for e in preds.getOrDefault(nid, @[]):
        if e.fromNode.startsWith("raw_"):
          hasRawInput = true
          break
      if not hasRawInput:
        assemblySteps.incl(nid)

  # Map step recipeId -> step object
  var stepMap = initTable[string, ProductionStep]()
  for s in plan.steps:
    stepMap["step_" & s.recipeId] = s

  var modules: seq[SubFactoryModule] = @[]
  var stepModuleId = initTable[string, string]()

  # 5. Cluster Assembly Steps into Assembly Modules (connected components of assembly steps)
  var visitedAssembly = initHashSet[string]()
  var assemblyCount = 0
  for nid in assemblySteps:
    if not visitedAssembly.contains(nid):
      inc assemblyCount
      var cluster: seq[string] = @[]
      var q = @[nid]
      visitedAssembly.incl(nid)
      while q.len > 0:
        let curr = q.pop()
        cluster.add(curr)
        for e in preds.getOrDefault(curr, @[]):
          if assemblySteps.contains(e.fromNode) and not visitedAssembly.contains(e.fromNode):
            visitedAssembly.incl(e.fromNode)
            q.add(e.fromNode)
        for e in succs.getOrDefault(curr, @[]):
          if assemblySteps.contains(e.toNode) and not visitedAssembly.contains(e.toNode):
            visitedAssembly.incl(e.toNode)
            q.add(e.toNode)

      let modId = fmt"subfac_assembly_{assemblyCount}"
      for stepId in cluster:
        stepModuleId[stepId] = modId

      # Name the module after top-tier assembled recipe
      var topStep = stepMap[cluster[0]]
      for stepId in cluster:
        let st = stepMap[stepId]
        if st.machineId == "manufacturer" or st.powerMW > topStep.powerMW:
          topStep = st

      var subMod = SubFactoryModule(
        id: modId,
        name: fmt"Módulo de Ensamblaje: {topStep.recipeName}",
        steps: cluster.mapIt(stepMap[it]),
        requiredRaw: initTable[string, float]()
      )
      modules.add(subMod)

  # 6. Cluster Non-Assembly Steps into Primary / Intermediate Processing Sub-factories
  # Connected components considering both step-to-step flows and shared raw resource sources
  var nonAssemblySteps: seq[string] = @[]
  for s in plan.steps:
    let nid = "step_" & s.recipeId
    if not assemblySteps.contains(nid):
      nonAssemblySteps.add(nid)

  var primaryAdj = initTable[string, HashSet[string]]()
  for u in nonAssemblySteps:
    primaryAdj[u] = initHashSet[string]()

  for e in plan.edges:
    if e.fromNode.startsWith("step_") and e.toNode.startsWith("step_"):
      if not assemblySteps.contains(e.fromNode) and not assemblySteps.contains(e.toNode):
        primaryAdj[e.fromNode].incl(e.toNode)
        primaryAdj[e.toNode].incl(e.fromNode)

  for req in plan.rawResources:
    let rNode = "raw_" & req.itemId
    var stepsWithThisRaw: seq[string] = @[]
    for e in plan.edges:
      if e.fromNode == rNode and e.toNode.startsWith("step_") and not assemblySteps.contains(e.toNode):
        stepsWithThisRaw.add(e.toNode)
    for i in 0 ..< stepsWithThisRaw.len:
      for j in (i + 1) ..< stepsWithThisRaw.len:
        let u = stepsWithThisRaw[i]
        let v = stepsWithThisRaw[j]
        primaryAdj[u].incl(v)
        primaryAdj[v].incl(u)

  var visitedPrimary = initHashSet[string]()
  var primaryCount = 0
  for nid in nonAssemblySteps:
    if not visitedPrimary.contains(nid):
      inc primaryCount
      var cluster: seq[string] = @[]
      var q = @[nid]
      visitedPrimary.incl(nid)
      while q.len > 0:
        let curr = q.pop()
        cluster.add(curr)
        for neighbor in primaryAdj.getOrDefault(curr, initHashSet[string]()):
          if not visitedPrimary.contains(neighbor):
            visitedPrimary.incl(neighbor)
            q.add(neighbor)

      var clusterRaws = initHashSet[string]()
      for stepId in cluster:
        for r in rawAncestors.getOrDefault(stepId, initHashSet[string]()):
          clusterRaws.incl(r)

      let modId = fmt"subfac_primary_{primaryCount}"
      for stepId in cluster:
        stepModuleId[stepId] = modId

      let modName = getPrimaryModuleName(clusterRaws)
      var subMod = SubFactoryModule(
        id: modId,
        name: modName,
        steps: cluster.mapIt(stepMap[it]),
        requiredRaw: initTable[string, float]()
      )
      modules.add(subMod)

  # 7. Compute requiredRaw and producedItems for all SubFactoryModules
  for i in 0 ..< modules.len:
    var m = modules[i]
    var stepIdsInMod = initHashSet[string]()
    for s in m.steps:
      stepIdsInMod.incl("step_" & s.recipeId)

    # Virgin raw inputs directly entering this module
    for e in plan.edges:
      if e.fromNode.startsWith("raw_") and stepIdsInMod.contains(e.toNode):
        m.requiredRaw[e.itemId] = m.requiredRaw.getOrDefault(e.itemId, 0.0) + e.rate

    # Outputs exported from this module (going to target or steps in another module)
    var exported = initTable[string, float]()
    for e in plan.edges:
      if stepIdsInMod.contains(e.fromNode):
        if not stepIdsInMod.contains(e.toNode):
          exported[e.itemId] = exported.getOrDefault(e.itemId, 0.0) + e.rate

    for it, rate in exported:
      m.producedItems.add(FactoryTarget(itemId: it, rate: rate))

    m.producedItems.sort(proc(a, b: FactoryTarget): int = cmp(b.rate, a.rate))
    modules[i] = m

  return modules
