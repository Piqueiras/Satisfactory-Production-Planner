#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Choose port: check $1 or find first free port starting from 8080 or 8000
TARGET_PORT="${1:-8080}"
PORT=$(python3 -c "
import socket
candidates = [$TARGET_PORT, 8000, 8888, 5000, 3000]
for p in candidates:
    try:
        s = socket.socket()
        s.bind(('0.0.0.0', p))
        s.close()
        print(p)
        break
    except:
        pass
" 2>/dev/null || echo "$TARGET_PORT")

cd "$ROOT_DIR/web"

echo "================================================================"
echo "🏭 FICSIT PRODUCTION OPTIMIZER (SATISFACTORY 1.0)"
echo "   Servidor web local para WSL y navegador de Windows"
echo "================================================================"
echo ""
echo "🚀 Servidor iniciado en puerto $PORT."
echo "👉 Abre en tu navegador (Windows o Linux):"
echo "   http://localhost:$PORT"
echo "   http://127.0.0.1:$PORT"
echo ""
echo "Presiona Ctrl+C para detener el servidor."
echo "================================================================"

# Try Python3 http.server, then Node
if command -v python3 &>/dev/null; then
    python3 -m http.server "$PORT" --bind 0.0.0.0
elif command -v node &>/dev/null; then
    node -e "
    const http = require('http');
    const fs = require('fs');
    const path = require('path');
    const mime = { '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css' };
    http.createServer((req, res) => {
      let f = req.url === '/' ? '/index.html' : req.url;
      let p = path.join(process.cwd(), f);
      fs.readFile(p, (err, data) => {
        if (err) { res.writeHead(404); res.end('Not found'); }
        else {
          let ext = path.extname(p);
          res.writeHead(200, { 'Content-Type': mime[ext] || 'text/plain' });
          res.end(data);
        }
      });
    }).listen($PORT, '0.0.0.0', () => console.log('Node server running on port $PORT'));
    "
fi

