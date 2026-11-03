#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔧 Compilando aplicación Nim Satisfactory Planner a JavaScript..."

# Use local workspace nim toolchain or system nim
if [ -f "$ROOT_DIR/.nim_toolchain/bin/nim" ]; then
    NIM="$ROOT_DIR/.nim_toolchain/bin/nim"
else
    NIM="nim"
fi

cd "$ROOT_DIR"
"$NIM" js --path:src -d:release -o:web/app.js src/main.nim

echo "✅ Compilación exitosa!"
echo "📦 Bundle generado: web/app.js ($(du -h web/app.js | cut -f1))"

