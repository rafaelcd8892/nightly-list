#!/bin/bash
# Compila en Release e instala en /Applications, reemplazando lo que haya.
#
# La app vive en /Applications y no en DerivedData: dos copias significan dos
# iconos en la barra de menus y no saber cual se esta usando.
set -euo pipefail

cd "$(dirname "$0")/.."

DESTINO="/Applications/Nightly List.app"

xcodebuild -project NightlyList.xcodeproj -scheme NightlyList \
    -configuration Release -destination 'platform=macOS' build

PRODUCTOS=$(xcodebuild -project NightlyList.xcodeproj -scheme NightlyList \
    -configuration Release -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')

pkill -f "Nightly List.app/Contents/MacOS" || true
sleep 1

ditto "$PRODUCTOS/Nightly List.app" "$DESTINO"
codesign --verify --strict "$DESTINO"

# Que no quede una segunda copia con la que confundirse.
rm -rf "$PRODUCTOS/Nightly List.app"

open "$DESTINO"
echo "Instalada en $DESTINO"
