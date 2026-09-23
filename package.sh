#!/usr/bin/env bash
# ==============================================================================
# Helper to package BurstWave as a .plasmoid file for KDE Store / Pling
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NAME="org.edisonkz.burstwave.plasmoid"

echo "📦 Empaquetando BurstWave..."

cd "${SCRIPT_DIR}"
rm -f "${PACKAGE_NAME}"

# Asegurar permisos correctos
chmod +x contents/code/* 2>/dev/null || true

# Plasmoids son archivos ZIP conteniendo metadata.json y contents/
if command -v zip >/dev/null 2>&1; then
    zip -r "${PACKAGE_NAME}" metadata.json contents/ >/dev/null
else
    # Fallback con python3 si zip no está instalado en el sistema
    python3 -c "
import zipfile, os

with zipfile.ZipFile('${PACKAGE_NAME}', 'w', zipfile.ZIP_DEFLATED) as z:
    z.write('metadata.json', 'metadata.json')
    for root, dirs, files in os.walk('contents'):
        for file in files:
            full_path = os.path.join(root, file)
            z.write(full_path, full_path)
"
fi

echo "✅ Paquete generado exitosamente: ${SCRIPT_DIR}/${PACKAGE_NAME}"
echo "   Puedes subir este archivo a store.kde.org (Pling) o compartirlo directamente."
