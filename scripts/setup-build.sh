#!/data/data/com.termux/files/usr/bin/bash
# setup-build.sh - Prepara el entorno de build para dnf-for-termux
set -e

echo "=== dnf-for-termux: Build Environment Setup ==="

# Verificar dependencias base
DEPS="cmake make pkg-config git curl wget"
MISSING=""
for dep in $DEPS; do
    if ! command -v $dep &>/dev/null; then
        MISSING="$MISSING $dep"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Faltan dependencias:$MISSING"
    echo "Instálalas con: pkg install$MISSING"
    exit 1
fi

echo "✅ Dependencias base OK"

# Verificar Termux
if [ ! -d "$PREFIX" ]; then
    echo "❌ No parece que estés en Termux (\$PREFIX no existe)"
    exit 1
fi
echo "✅ Entorno Termux: $PREFIX"

# Crear directorios si no existen
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$SCRIPT_DIR/build/termux"
mkdir -p "$SCRIPT_DIR/patches"

echo "✅ Directorios listos"
echo "=== Entorno listo para compilar ==="
