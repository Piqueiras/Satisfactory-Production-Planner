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

  Preset* = object
    id*: string
    name*: string
    desc*: string
    targets*: seq[FactoryTarget]
    enableAlternates*: bool
    enabledAlts*: seq[string]

