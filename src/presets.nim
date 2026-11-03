import types

proc getPresets*(): seq[Preset] =
  result = @[
    Preset(
      id: "phase1",
      name: "🚀 Space Elevator Phase 1",
      desc: "Smart Plating (2.0 / min). Beginner factory setup.",
      targets: @[
        FactoryTarget(itemId: "smart-plating", rate: 2.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "phase2",
      name: "🚀 Space Elevator Phase 2",
      desc: "Versatile Framework (5.0 / min) & Automated Wiring (2.5 / min).",
      targets: @[
        FactoryTarget(itemId: "versatile-framework", rate: 5.0),
        FactoryTarget(itemId: "automated-wiring", rate: 2.5)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "phase3",
      name: "🚀 Space Elevator Phase 3",
      desc: "Modular Engine (1.0 / min) & Adaptive Control Unit (1.0 / min). Mid-game automation.",
      targets: @[
        FactoryTarget(itemId: "modular-engine", rate: 1.0),
        FactoryTarget(itemId: "adaptive-control-unit", rate: 1.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "phase4",
      name: "🚀 Space Elevator Phase 4",
      desc: "Assembly Director (0.75/m), Magnetic Field Gen (1/m), Thermal Rocket (1/m), Nuclear Pasta (0.5/m).",
      targets: @[
        FactoryTarget(itemId: "assembly-director-system", rate: 0.75),
        FactoryTarget(itemId: "magnetic-field-generator", rate: 1.0),
        FactoryTarget(itemId: "thermal-propulsion-rocket", rate: 1.0),
        FactoryTarget(itemId: "nuclear-pasta", rate: 0.5)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "phase5",
      name: "🌌 Satisfactory 1.0 Phase 5 Endgame",
      desc: "AI Expansion Server, Ballistic Warp Drive, Biochemical Sculptor, & Ficsonium Fuel Rod.",
      targets: @[
        FactoryTarget(itemId: "ai-expansion-server", rate: 1.0),
        FactoryTarget(itemId: "ballistic-warp-drive", rate: 1.0),
        FactoryTarget(itemId: "biochemical-sculptor", rate: 1.0),
        FactoryTarget(itemId: "ficsonium-fuel-rod", rate: 1.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "hmf_10",
      name: "🏗️ Heavy Modular Frame Factory",
      desc: "10.0 Heavy Modular Frames / min. Industrial steel and frame powerhouse.",
      targets: @[
        FactoryTarget(itemId: "heavy-modular-frame", rate: 10.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "aluminum_battery",
      name: "💧 Aluminum & Battery Loop (Byproduct Recycled)",
      desc: "Aluminum Casing (120/m), Alclad Sheet (120/m), Battery (60/m). Automatic water recycling loop.",
      targets: @[
        FactoryTarget(itemId: "aluminum-casing", rate: 120.0),
        FactoryTarget(itemId: "alclad-aluminum-sheet", rate: 120.0),
        FactoryTarget(itemId: "battery", rate: 60.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "supercomputers",
      name: "💻 High-Tech Supercomputer Complex",
      desc: "Supercomputer (5.0 / min) & Radio Control Unit (10.0 / min). Electronics assembly.",
      targets: @[
        FactoryTarget(itemId: "supercomputer", rate: 5.0),
        FactoryTarget(itemId: "radio-control-unit", rate: 10.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "rocket_fuel",
      name: "⛽ Rocket Fuel Refinery Setup",
      desc: "Rocket Fuel (60.0 / min) & Plastic (60.0 / min). Oil refinery & gas production.",
      targets: @[
        FactoryTarget(itemId: "rocket-fuel", rate: 60.0),
        FactoryTarget(itemId: "plastic", rate: 60.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    ),
    Preset(
      id: "motor_rotors",
      name: "⚙️ Motor & Rotor Automation",
      desc: "Motor (10.0 / min), Rotor (15.0 / min), Stator (15.0 / min). Basic manufacturing line.",
      targets: @[
        FactoryTarget(itemId: "motor", rate: 10.0),
        FactoryTarget(itemId: "rotor", rate: 15.0),
        FactoryTarget(itemId: "stator", rate: 15.0)
      ],
      enableAlternates: false,
      enabledAlts: @[]
    )
  ]

