#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Let the window manager tile and place Hermes LW like any normal app.
python "$APP_DIR/ensure_backend.py"
exec qs -n -p "$APP_DIR/Main.qml"
