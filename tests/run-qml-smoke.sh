#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
smoke_dir=$(mktemp -d /tmp/holdings-smoke.XXXXXX)
trap 'rm -rf -- "$smoke_dir"' EXIT
cp "$repo_dir/tests/smoke.qml" "$smoke_dir/shell.qml"
ln -s /usr/share/omarchy/shell/Commons "$smoke_dir/Commons"
ln -s /usr/share/omarchy/shell/Ui "$smoke_dir/Ui"
ln -s "$repo_dir/plugin" "$smoke_dir/plugin"
mkdir "$smoke_dir/config" "$smoke_dir/cache" "$smoke_dir/runtime"
chmod 700 "$smoke_dir/runtime"
# Bloqueia rede durante o teste: cache/backoff isolados, sem saldo do usuário.
mkdir "$smoke_dir/cache/io.github.lpanebr.bitcoin-holdings"
python3 - "$smoke_dir/cache/io.github.lpanebr.bitcoin-holdings/backoff-binance.json" <<'PY'
import json, sys, time
with open(sys.argv[1], 'w') as f:
    json.dump({'until': time.time() + 3600, 'message': 'Teste offline', 'state': 'offline'}, f)
PY
wayland_socket=${WAYLAND_DISPLAY:-wayland-0}
if [[ $wayland_socket != /* ]]; then
    wayland_socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$wayland_socket"
fi
XDG_CONFIG_HOME="$smoke_dir/config" XDG_CACHE_HOME="$smoke_dir/cache" \
XDG_RUNTIME_DIR="$smoke_dir/runtime" WAYLAND_DISPLAY="$wayland_socket" \
QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
    timeout 15s quickshell --no-color -p "$smoke_dir/shell.qml" >"$smoke_dir/log" 2>&1 || {
        cat "$smoke_dir/log"
        exit 1
    }
cat "$smoke_dir/log"
rg -q HOLDINGS_SMOKE_PASS "$smoke_dir/log"
if rg -q '(TypeError|ReferenceError|SyntaxError|Error loading configuration|is not a type|Cannot assign|Unable to assign|QML.*Error)' "$smoke_dir/log"; then exit 1; fi
