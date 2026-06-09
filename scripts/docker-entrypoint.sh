#!/bin/sh
# Start Node and optionally Cloudflare Tunnel (when CLOUDFLARE_TUNNEL_TOKEN is set).
set -e

PORT="${PORT:-3000}"
NODE_PID=""
TUNNEL_PID=""

cleanup() {
  if [ -n "$TUNNEL_PID" ]; then
    kill "$TUNNEL_PID" 2>/dev/null || true
  fi
  if [ -n "$NODE_PID" ]; then
    kill "$NODE_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

node server.js &
NODE_PID=$!

if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  echo "Starting Cloudflare Tunnel (origin http://127.0.0.1:${PORT})"
  cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" &
  TUNNEL_PID=$!
else
  echo "CLOUDFLARE_TUNNEL_TOKEN not set — serving HTTP on port ${PORT} only"
fi

wait "$NODE_PID"
