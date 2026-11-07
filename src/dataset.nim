import std/[json, tables, sets, algorithm]
import types

const
  rawDataStr = staticRead("../data/raw_data.json")
  mapNodesStr = staticRead("../data/map_nodes.json")

var
  allItems*: Table[string, Item]
  allRecipes*: Table[string, Recipe]
  allMachines*: Table[string, MachineInfo]
  alternateRecipeIds*: HashSet[string]
  rawResourceIds*: HashSet[string]
  craftableItemIds*: seq[string]
  itemRecipesMap*: Table[string, seq[Recipe]]
  allMapNodes*: seq[ResourceNode]
  nodesByResource*: Table[string, seq[ResourceNode]]
  nodesByBiome*: Table[string, seq[ResourceNode]]

proc initMachines() =
  allMachines = initTable[string, MachineInfo]()
  
  template reg(idStr, nameStr: string, mw: float, catStr: string) =
    allMachines[idStr] = MachineInfo(id: idStr, name: nameStr, power: mw, category: catStr)

  reg("smelter", "Smelter", 4.0, "smelting")
  reg("foundry", "Foundry", 16.0, "smelting")
  reg("constructor-id", "Constructor", 4.0, "production")
  reg("assembler", "Assembler", 15.0, "production")
  reg("manufacturer", "Manufacturer", 55.0, "production")
  reg("refinery", "Refinery", 30.0, "refining")
  reg("blender", "Blender", 75.0, "refining")
  reg("packager", "Packager", 10.0, "packaging")
  reg("particle-accelerator", "Particle Accelerator", 750.0, "quantum")
  reg("converter", "Converter", 100.0, "quantum")
  reg("quantum-encoder", "Quantum Encoder", 2000.0, "quantum")
  reg("water-extractor", "Water Extractor", 20.0, "extraction")
  reg("oil-extractor", "Oil Extractor", 40.0, "extraction")
  reg("resource-well-extractor", "Resource Well Extractor", 25.0, "extraction")
  reg("miner-mk1", "Miner Mk.1", 5.0, "mining")
  reg("miner-mk2", "Miner Mk.2", 12.0, "mining")
  reg("miner-mk3", "Miner Mk.3", 30.0, "mining")

proc loadDatabase*() =
  initMachines()
  allItems = initTable[string, Item]()
  allRecipes = initTable[string, Recipe]()
  alternateRecipeIds = initHashSet[string]()
  rawResourceIds = initHashSet[string]()
  craftableItemIds = @[]
  itemRecipesMap = initTable[string, seq[Recipe]]()

  let data = parseJson(rawDataStr)

  # 1. Colors & Icons
  var colorMap = initTable[string, string]()
  if data.hasKey("icons"):
    for iconNode in data["icons"]:
      let idStr = iconNode["id"].getStr()
      let colorStr = if iconNode.hasKey("color"): iconNode["color"].getStr() else: "#FA9549"
      colorMap[idStr] = colorStr

  # 2. Excluded / Alternate recipes
  if data.hasKey("defaults") and data["defaults"].hasKey("excludedRecipes"):
    for ex in data["defaults"]["excludedRecipes"]:
      alternateRecipeIds.incl(ex.getStr())

  # 3. Items
  if data.hasKey("items"):
    for itemNode in data["items"]:
      let idStr = itemNode["id"].getStr()
      let catStr = if itemNode.hasKey("category"): itemNode["category"].getStr() else: "components"
      let nameStr = if itemNode.hasKey("name"): itemNode["name"].getStr() else: idStr
      let stackVal = if itemNode.hasKey("stack"): itemNode["stack"].getInt() else: 100
      let c = colorMap.getOrDefault(idStr, "#FA9549")

      allItems[idStr] = Item(
        id: idStr,
        name: nameStr,
        category: catStr,
        stack: stackVal,
        color: c,
        isRaw: false
      )

  # 4. Recipes
  var producedItemsSet = initHashSet[string]()

  if data.hasKey("recipes"):
    for rNode in data["recipes"]:
      var r: Recipe
      r.id = rNode["id"].getStr()
      r.name = if rNode.hasKey("name"): rNode["name"].getStr() else: r.id
      r.time = if rNode.hasKey("time"): max(0.1, rNode["time"].getFloat()) else: 1.0
      r.isMining = rNode.hasKey("flags") and rNode["flags"].contains(%"mining")
      r.isAlternate = alternateRecipeIds.contains(r.id)

      if rNode.hasKey("producers"):
        for p in rNode["producers"]:
          r.producers.add(p.getStr())

      r.inputs = initTable[string, float]()
      r.ratesIn = initTable[string, float]()
      if rNode.hasKey("in"):
        for k, v in rNode["in"]:
          let amt = v.getFloat()
          r.inputs[k] = amt
          r.ratesIn[k] = amt * 60.0 / r.time

      r.outputs = initTable[string, float]()
      r.ratesOut = initTable[string, float]()
      if rNode.hasKey("out"):
        for k, v in rNode["out"]:
          let amt = v.getFloat()
          r.outputs[k] = amt
          r.ratesOut[k] = amt * 60.0 / r.time
          producedItemsSet.incl(k)
          if r.primaryOutput == "":
            r.primaryOutput = k

      if r.inputs.len == 0 and r.outputs.len > 0:
        # Raw resource recipe!
        for k, _ in r.outputs:
          rawResourceIds.incl(k)
          if allItems.hasKey(k):
            var it = allItems[k]
            it.isRaw = true
            allItems[k] = it

      allRecipes[r.id] = r

  for _, r in allRecipes:
    for outItem, _ in r.outputs:
      var list = itemRecipesMap.getOrDefault(outItem, @[])
      list.add(r)
      itemRecipesMap[outItem] = list

  # Fill craftable list (excluding purely raw items, buildings, and purely internal items)
  for idStr, item in allItems:
    if producedItemsSet.contains(idStr) and item.category != "other":
      craftableItemIds.add(idStr)

  craftableItemIds.sort(proc(a, b: string): int = cmp(allItems[a].name, allItems[b].name))

  # 5. Load Satisfactory 1.0 Resource Nodes Dataset
  allMapNodes = @[]
  nodesByResource = initTable[string, seq[ResourceNode]]()
  nodesByBiome = initTable[string, seq[ResourceNode]]()

  let mapData = parseJson(mapNodesStr)
  if mapData.hasKey("nodes"):
    for nNode in mapData["nodes"]:
      let n = ResourceNode(
        id: nNode["id"].getStr(),
        resourceId: nNode["resourceId"].getStr(),
        kind: if nNode.hasKey("kind"): nNode["kind"].getStr() else: "node",
        purity: if nNode.hasKey("purity"): nNode["purity"].getStr() else: "normal",
        x: nNode["x"].getFloat(),
        y: nNode["y"].getFloat(),
        z: if nNode.hasKey("z"): nNode["z"].getFloat() else: 0.0,
        mapX: if nNode.hasKey("mapX"): nNode["mapX"].getFloat() else: 0.0,
        mapY: if nNode.hasKey("mapY"): nNode["mapY"].getFloat() else: 0.0,
        biome: if nNode.hasKey("biome"): nNode["biome"].getStr() else: "Unknown"
      )
      allMapNodes.add(n)
      var resList = nodesByResource.getOrDefault(n.resourceId, @[])
      resList.add(n)
      nodesByResource[n.resourceId] = resList

      var biomeList = nodesByBiome.getOrDefault(n.biome, @[])
      biomeList.add(n)
      nodesByBiome[n.biome] = biomeList

# Initialize on module load
loadDatabase()

proc getItemName*(idStr: string): string =
  if allItems.hasKey(idStr):
    return allItems[idStr].name
  return idStr

proc getItemColor*(idStr: string): string =
  if allItems.hasKey(idStr):
    return allItems[idStr].color
  return "#FA9549"

proc getMachineName*(idStr: string): string =
  if allMachines.hasKey(idStr):
    return allMachines[idStr].name
  return idStr

proc getMachinePower*(idStr: string): float =
  if allMachines.hasKey(idStr):
    return allMachines[idStr].power
  return 10.0

proc getRecipesForItem*(itemId: string): seq[Recipe] =
  return itemRecipesMap.getOrDefault(itemId, @[])

proc getNodesForResource*(resourceId: string): seq[ResourceNode] =
  return nodesByResource.getOrDefault(resourceId, @[])

proc getNodesInBiome*(biomeName: string): seq[ResourceNode] =
  return nodesByBiome.getOrDefault(biomeName, @[])
