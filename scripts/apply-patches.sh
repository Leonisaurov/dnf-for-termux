#!/data/data/com.termux/files/usr/bin/bash
# apply-patches.sh - Aplica parches Termux a un componente
# Uso: ./apply-patches.sh <componente>
# Ejemplo: ./apply-patches.sh libsolv

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPONENT="$1"
PATCH_DIR="$SCRIPT_DIR/patches/$COMPONENT"
SOURCE_DIR="$SCRIPT_DIR/source/$COMPONENT"

if [ -z "$COMPONENT" ]; then
    echo "Uso: $0 <componente>"
    echo "Componentes disponibles:"
    ls "$SCRIPT_DIR/patches/"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "❌ No existe directorio de parches: $PATCH_DIR"
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ No existe directorio fuente: $SOURCE_DIR"
    exit 1
fi

cd "$SOURCE_DIR"
for patch in "$PATCH_DIR"/*.patch; do
    if [ -f "$patch" ]; then
        echo "Aplicando: $(basename $patch)"
        patch -p1 < "$patch" || echo "⚠️  Error aplicando $patch"
    fi
done
echo "✅ Parches aplicados a $COMPONENT"
