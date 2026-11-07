import std/tables

type
  Item* = object
    id*: string
    name*: string
    category*: string
    stack*: int
    color*: string
    isRaw*: bool

  Recipe* = object
    id*: string
    name*: string
    time*: float
    producers*: seq[string]
    inputs*: Table[string, float]      # amount per craft
    outputs*: Table[string, float]     # amount per craft
    ratesIn*: Table[string, float]     # items/min at 100%
    ratesOut*: Table[string, float]    # items/min at 100%
    isMining*: bool
    isAlternate*: bool
    primaryOutput*: string

  MachineInfo* = object
    id*: string
    name*: string
    power*: float # MW
    category*: string

  FactoryTarget* = object
    itemId*: string
    rate*: float # items/min

  ProductionStep* = object
    recipeId*: string
    recipeName*: string
    machineId*: string
    machineName*: string
    buildingCount*: float
    clockConfig*: string
    powerMW*: float
    inputs*: Table[string, float]   # items/min
    outputs*: Table[string, float]  # items/min
    isRecycling*: bool

  ResourceRequirement* = object
    itemId*: string
    itemName*: string
    rate*: float # items/min
    suggestedMiners*: string

  SurplusInfo* = object
    itemId*: string
    itemName*: string
    rate*: float # items/min
    status*: string

  FlowEdge* = object
    fromNode*: string
    toNode*: string
    itemId*: string
    itemName*: string
    rate*: float

  FlowNode* = object
    id*: string
    kind*: string # "raw", "step", "target", "byproduct"
    title*: string
    subtitle*: string
    color*: string
    tier*: int
    inputsSummary*: string
    outputsSummary*: string

  FactoryPlan* = object
    success*: bool
    errorMessage*: string
    totalBuildings*: float
    totalPowerMW*: float
    targets*: seq[FactoryTarget]
    steps*: seq[ProductionStep]
    rawResources*: seq[ResourceRequirement]
    byproducts*: seq[SurplusInfo]
    nodes*: seq[FlowNode]
    edges*: seq[FlowEdge]
    subFactories*: seq[SubFactoryModule]
    recommendations*: seq[LocationRecommendation]

  Preset* = object
    id*: string
    name*: string
    desc*: string
    targets*: seq[FactoryTarget]
    enableAlternates*: bool
    enabledAlts*: seq[string]

  Factory* = object
    id*: string
    name*: string
    targets*: seq[FactoryTarget]
    allowedRaw*: seq[string]
    enabledAlts*: seq[string]
    disabledRecipes*: seq[string]

  NodePurity* = enum
    npImpure = "impure"
    npNormal = "normal"
    npPure = "pure"

  ResourceNode* = object
    id*: string
    resourceId*: string
    kind*: string           # "node", "well", "geyser"
    purity*: string         # "impure", "normal", "pure"
    x*: float               # Unreal Engine X (cm)
    y*: float               # Unreal Engine Y (cm)
    z*: float               # Unreal Engine Z (cm)
    mapX*: float            # Map pixel X (0..8192)
    mapY*: float            # Map pixel Y (0..8192)
    biome*: string          # Biome name

  SubFactoryModule* = object
    id*: string
    name*: string
    producedItems*: seq[FactoryTarget]
    requiredRaw*: Table[string, float]
    steps*: seq[ProductionStep]
    assignedBiome*: string
    centerX*: float
    centerY*: float
    recommendations*: seq[LocationRecommendation]

  LocationRecommendation* = object
    id*: string
    title*: string
    biome*: string
    centerX*: float
    centerY*: float
    score*: float
    matchedNodes*: seq[ResourceNode]
    subModules*: seq[SubFactoryModule]
    logisticsDistanceMeters*: float
    explanation*: string

