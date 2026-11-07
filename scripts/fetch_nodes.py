#!/usr/bin/env python3
"""
scripts/fetch_nodes.py
Downloads or parses the complete Satisfactory 1.0 resource node dataset and
saves it into data/map_nodes.json with coordinates (UE X, Y, Z), purity,
internal resource IDs (matching data/raw_data.json), and biome classification.
"""

import os
import sys
import json
import urllib.request

ITEM_MAP = {
    "Desc_OreIron_C": "iron-ore",
    "Desc_OreCopper_C": "copper-ore",
    "Desc_Stone_C": "limestone",
    "Desc_Coal_C": "coal",
    "Desc_LiquidOil_C": "crude-oil",
    "Desc_RawQuartz_C": "raw-quartz",
    "Desc_OreGold_C": "caterium-ore",
    "Desc_OreBauxite_C": "bauxite",
    "Desc_Sulfur_C": "sulfur",
    "Desc_OreUranium_C": "uranium",
    "Desc_SAM_C": "sam-ore",
    "Desc_NitrogenGas_C": "nitrogen-gas",
    "Desc_Water_C": "water",
    "Desc_Geyser_C": "geyser",
}

PURITY_MAP = {
    0: "impure",
    1: "normal",
    2: "pure",
    "impure": "impure",
    "normal": "normal",
    "pure": "pure",
    "Impure": "impure",
    "Normal": "normal",
    "Pure": "pure",
}

def determine_biome(ue_x: float, ue_y: float) -> str:
    """Classifies (ue_x, ue_y) into a Satisfactory biome based on region bounds."""
    # North-East
    if ue_x > 180000 and ue_y < -50000:
        return "Dune Desert"
    # Far East
    if ue_x > 270000 and ue_y >= 50000 and ue_y <= 300000:
        return "Swamp"
    if ue_x > 220000 and ue_y > -50000 and ue_y < 120000:
        return "Eastern Dune Forest"
    # Far North / Spire Coast
    if ue_y < -260000 and -150000 <= ue_x <= 200000:
        return "Spire Coast"
    # North-Central
    if -100000 <= ue_x <= 180000 and -260000 <= ue_y <= -70000:
        return "Northern Forest"
    # North-West
    if ue_x < -100000 and ue_y < -60000:
        return "Rocky Desert"
    # Central East (Titan Forest)
    if 70000 <= ue_x <= 260000 and -70000 <= ue_y <= 90000:
        return "Titan Forest"
    # Central Highlands (Red Jungle & Bamboo)
    if -140000 <= ue_x <= 40000 and -70000 <= ue_y <= 70000:
        return "Red Jungle"
    if 0 <= ue_x <= 140000 and 0 <= ue_y <= 160000:
        return "Bamboo Fields"
    # Crater Lakes
    if -100000 <= ue_x <= 10000 and -30000 <= ue_y <= 80000:
        return "Crater Lakes"
    # West Central
    if ue_x < -140000 and -60000 <= ue_y <= 150000:
        return "Western Dune Forest"
    # South-West Islands
    if ue_x < -140000 and ue_y > 150000:
        return "Islands"
    # South-East (Blue Crater)
    if 90000 <= ue_x <= 270000 and 160000 <= ue_y <= 340000:
        return "Blue Crater"
    # South / South-Central (Grass Fields)
    if -140000 <= ue_x <= 90000 and ue_y >= 120000:
        return "Grass Fields"
    # Default fallback central
    return "Central Basin"

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    out_file = os.path.join(root_dir, "data", "map_nodes.json")

    url = "https://raw.githubusercontent.com/Albis0/ficsit_planner/main/src/data/world.json"
    print(f"📡 Descargando dataset de nodos mundiales de Satisfactory 1.0 desde {url}...")

    req = urllib.request.Request(
        url,
        headers={"User-Agent": "SatisfactoryPlanner/1.0 (Nim/Python dataset extractor)"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw_data = json.loads(resp.read().decode())

    bounds = raw_data.get("bounds", {
        "x0": -324698.832,
        "x1": 425301.168,
        "y0": -375000.0,
        "y1": 375000.0
    })
    size = float(raw_data.get("size", 8192))
    x0, x1 = float(bounds["x0"]), float(bounds["x1"])
    y0, y1 = float(bounds["y0"]), float(bounds["y1"])

    raw_nodes = raw_data.get("nodes", [])
    print(f"📦 Procesando {len(raw_nodes)} nodos brutos...")

    resource_nodes = []
    counts_by_res = {}
    counts_by_purity = {}

    for idx, n in enumerate(raw_nodes):
        raw_item = n.get("item", "")
        if raw_item not in ITEM_MAP:
            continue

        resource_id = ITEM_MAP[raw_item]
        # Skip geysers if only looking for extractable production resources, or keep them tagged
        kind = n.get("kind", "node")
        purity_val = n.get("purity", 1)
        purity_str = PURITY_MAP.get(purity_val, "normal")

        map_x = float(n.get("x", 0.0))
        map_y = float(n.get("y", 0.0))

        # Convert map pixel coordinate (0..8192) to Unreal Engine world centimeters
        ue_x = round(x0 + (map_x / size) * (x1 - x0), 1)
        ue_y = round(y0 + (map_y / size) * (y1 - y0), 1)
        # Z height estimate (or default 0)
        ue_z = 0.0

        biome = determine_biome(ue_x, ue_y)
        node_id = f"node-{resource_id}-{idx+1}"

        node_obj = {
            "id": node_id,
            "resourceId": resource_id,
            "kind": kind, # "node", "well", "geyser"
            "purity": purity_str, # "impure", "normal", "pure"
            "x": ue_x,
            "y": ue_y,
            "z": ue_z,
            "mapX": round(map_x, 1),
            "mapY": round(map_y, 1),
            "biome": biome
        }
        resource_nodes.append(node_obj)

        counts_by_res[resource_id] = counts_by_res.get(resource_id, 0) + 1
        counts_by_purity[purity_str] = counts_by_purity.get(purity_str, 0) + 1

    result = {
        "version": "1.0",
        "totalNodes": len(resource_nodes),
        "bounds": bounds,
        "mapSize": int(size),
        "nodes": resource_nodes
    }

    os.makedirs(os.path.dirname(out_file), exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"✅ Guardado exitoso en {out_file} ({len(resource_nodes)} nodos).")
    print("📊 Desglose por recurso:")
    for r, c in sorted(counts_by_res.items(), key=lambda x: -x[1]):
        print(f"   - {r}: {c} nodos")
    print("📊 Desglose por pureza:")
    for p, c in counts_by_purity.items():
        print(f"   - {p}: {c} nodos")

if __name__ == "__main__":
    main()
