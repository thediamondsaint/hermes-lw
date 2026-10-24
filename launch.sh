#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Open the dedicated control desk at a useful size in Hyprland, accounting for
# monitor scaling so a 2x laptop panel does not crop the floating window.
if command -v hyprctl >/dev/null 2>&1; then
  read -r WINDOW_W WINDOW_H < <(hyprctl monitors -j 2>/dev/null | python -c 'import json,sys; m=json.load(sys.stdin)[0]; s=float(m.get("scale",1)); w=round(m["width"]/s); h=round(m["height"]/s); print(min(1500,max(1150,w-80)),min(960,max(720,h-40)))' 2>/dev/null || true)
  if [[ "${WINDOW_W:-}" =~ ^[0-9]+$ && "${WINDOW_H:-}" =~ ^[0-9]+$ ]] && [[ "$(hyprctl status -j 2>/dev/null | python -c 'import json,sys; print(json.load(sys.stdin).get("configProvider",""))' 2>/dev/null || true)" == "lua" ]]; then
    hyprctl eval "hl.window_rule({name='hermes-control-window',match={title='Hermes LW'},workspace='5',float=true,center=true,size={$WINDOW_W,$WINDOW_H},tag='-default-opacity',opacity='1 override 1 override'})" >/dev/null 2>&1 || true
  fi
fi

if ! python -c 'import socket; s=socket.create_connection(("127.0.0.1",18731),0.25); s.close()' 2>/dev/null; then
  nohup python "$APP_DIR/backend.py" >/tmp/hermes-control-backend.log 2>&1 </dev/null &
  for _ in $(seq 1 30); do
    if python -c 'import socket; s=socket.create_connection(("127.0.0.1",18731),0.25); s.close()' 2>/dev/null; then break; fi
    sleep 0.1
  done
fi
exec qs -p "$APP_DIR/Main.qml"
