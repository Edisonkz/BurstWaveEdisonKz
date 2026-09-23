#!/usr/bin/env bash
# ==============================================================================
# BurstWave Uninstaller for KDE Plasma 6
# Author: EdisonKz
# ==============================================================================

set -e

PLUGIN_ID="org.edisonkz.burstwave"
TARGET_DIR="${HOME}/.local/share/plasma/plasmoids/${PLUGIN_ID}"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/audio-wave-widget"

echo "🗑️  Desinstalando BurstWave..."

# Matar procesos residuales del feeder si estuvieran corriendo
if [ -d "$RUN_DIR" ]; then
    if [ -f "$RUN_DIR/feeder.pid" ]; then
        PID=$(cat "$RUN_DIR/feeder.pid" 2>/dev/null || true)
        if [ -n "$PID" ]; then
            kill "$PID" 2>/dev/null || true
        fi
    fi
    pkill -f "cava.*cava.conf" 2>/dev/null || true
    rm -rf "$RUN_DIR"
fi

if command -v kpackagetool6 >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet --remove "${PLUGIN_ID}" 2>/dev/null || true
fi

if [ -d "${TARGET_DIR}" ]; then
    rm -rf "${TARGET_DIR}"
    echo "  Eliminado: ${TARGET_DIR}"
fi

echo "✅ BurstWave ha sido desinstalado correctamente."
read -p "¿Deseas reiniciar Plasma Shell ahora? [s/N]: " restart_plasma
if [[ "$restart_plasma" =~ ^[sSyY]$ ]]; then
    systemctl --user restart plasma-plasmashell.service
    echo "✅ Plasma Shell reiniciado."
fi
