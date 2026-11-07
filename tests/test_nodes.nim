import dataset, types, tables

echo "=== TESTING MAP NODES IN DATASET ==="
echo "Total map nodes loaded: ", allMapNodes.len
doAssert allMapNodes.len == 608, "Expected 608 nodes, got " & $allMapNodes.len

echo "Nodes by resource types: ", nodesByResource.len
let ironNodes = getNodesForResource("iron-ore")
echo "  Iron nodes: ", ironNodes.len
doAssert ironNodes.len == 127

let coalNodes = getNodesForResource("coal")
echo "  Coal nodes: ", coalNodes.len
doAssert coalNodes.len == 62

let uraniumNodes = getNodesForResource("uranium")
echo "  Uranium nodes: ", uraniumNodes.len
doAssert uraniumNodes.len == 5

echo "Biomes indexed: ", nodesByBiome.len
for b in nodesByBiome.keys:
  let inBiome = getNodesInBiome(b)
  echo "  Biome '", b, "': ", inBiome.len, " nodes"

echo "\nSample node: ", allMapNodes[0].id, " -> ", allMapNodes[0].resourceId, " (", allMapNodes[0].purity, ") at UE (", allMapNodes[0].x, ", ", allMapNodes[0].y, ") in ", allMapNodes[0].biome
echo "✅ MAP NODES LOADED AND VERIFIED SUCCESSFULLY!"
