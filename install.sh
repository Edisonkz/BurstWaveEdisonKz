#!/usr/bin/env bash
# ==============================================================================
# BurstWave Installer for KDE Plasma 6
# Author: EdisonKz
# ==============================================================================

set -e

PLUGIN_ID="org.edisonkz.burstwave"
TARGET_DIR="${HOME}/.local/share/plasma/plasmoids/${PLUGIN_ID}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🌊 ==============================================="
echo "   BurstWave - Instalador para KDE Plasma 6"
echo "==============================================="

# 1. Comprobación de Dependencias
echo -e "\n🔍 Verificando dependencias necesarias..."

check_cmd() {
    local cmd="$1"
    local pkg="$2"
    local required="$3"

    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✅ $cmd encontrado."
    else
        if [ "$required" = "yes" ]; then
            echo "  ❌ FALTA: '$cmd' (necesario: $pkg)."
            MISSING_REQ=1
        else
            echo "  ⚠️ OPCIONAL: '$cmd' no encontrado ($pkg)."
        fi
    fi
}

MISSING_REQ=0
check_cmd "cava" "cava (visualizador de audio por terminal/fifo)" "yes"
check_cmd "python3" "python3 (lector de metadatos MPRIS)" "yes"
check_cmd "busctl" "systemd (comunicación D-Bus)" "yes"
check_cmd "playerctl" "playerctl (control multimedia de respaldo)" "no"

if [ "$MISSING_REQ" -eq 1 ]; then
    echo -e "\n⚠️  Hay dependencias obligatorias ausentes."
    echo "En Arch Linux puedes instalarlas con:"
    echo "  sudo pacman -S cava python systemd"
    echo "En Debian/Ubuntu:"
    echo "  sudo apt install cava python3 systemd"
    echo "En Fedora:"
    echo "  sudo dnf install cava python3 systemd"
    read -p "¿Deseas continuar con la instalación de todas formas? [s/N]: " continue_inst
    if [[ ! "$continue_inst" =~ ^[sSyY]$ ]]; then
        echo "Instalación cancelada."
        exit 1
    fi
fi

# 2. Permisos de ejecución a scripts internos
echo -e "\n🔧 Configurando permisos de scripts internos..."
chmod +x "${SCRIPT_DIR}/contents/code/"* 2>/dev/null || true

# 3. Instalación
echo -e "\n📦 Instalando widget en el sistema..."
mkdir -p "${HOME}/.local/share/plasma/plasmoids"

# Si kpackagetool6 está disponible, intentamos registrarlo formalmente
if command -v kpackagetool6 >/dev/null 2>&1; then
    echo "Usando kpackagetool6..."
    kpackagetool6 -t Plasma/Applet --upgrade "${SCRIPT_DIR}" 2>/dev/null || \
    kpackagetool6 -t Plasma/Applet --install "${SCRIPT_DIR}" 2>/dev/null || {
        echo "Copia directa a directorio de plasmoids..."
        rm -rf "${TARGET_DIR}"
        cp -r "${SCRIPT_DIR}" "${TARGET_DIR}"
    }
else
    echo "Copiando archivos directamente a ${TARGET_DIR}..."
    rm -rf "${TARGET_DIR}"
    mkdir -p "${TARGET_DIR}"
    cp -r "${SCRIPT_DIR}/contents" "${TARGET_DIR}/"
    cp "${SCRIPT_DIR}/metadata.json" "${TARGET_DIR}/"
fi

# Asegurar permisos en destino
chmod +x "${TARGET_DIR}/contents/code/"* 2>/dev/null || true

echo -e "\n✅ BurstWave instalado exitosamente en:"
echo "   ${TARGET_DIR}"

# 4. Preguntar reinicio de Plasma
echo -e "\n🔄 Para que KDE Plasma reconozca el nuevo widget de inmediato:"
read -p "¿Deseas reiniciar Plasma Shell ahora? [s/N]: " restart_plasma
if [[ "$restart_plasma" =~ ^[sSyY]$ ]]; then
    echo "Reiniciando plasmashell..."
    systemctl --user restart plasma-plasmashell.service
    echo "✅ Plasma Shell reiniciado."
else
    echo "Puedes reiniciarlo más tarde con:"
    echo "  systemctl --user restart plasma-plasmashell.service"
fi

echo -e "\n🎉 ¡Listo! Ahora haz clic derecho en tu escritorio:"
echo "   1. Selecciona 'Añadir elementos gráficos...'"
echo "   2. Busca 'BurstWave'"
echo "   3. Arrástralo a tu pantalla o panel."
echo "==============================================="
