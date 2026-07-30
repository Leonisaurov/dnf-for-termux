#!/usr/bin/env bash
# build.sh template para componentes de dnf-for-termux
# 
# Variables de entorno disponibles en CI:
#   TERMUX_PREFIX  - Ruta base de Termux (/data/data/com.termux/files/usr)
#   TARGET_ARCH    - aarch64 (por ahora)
#   CC, CXX, etc  - Cross-compiler toolchain (desde container termux)
#
# Uso: source este script desde el directorio del componente source

set -euo pipefail

# === CONFIGURACIÓN ===
COMPONENT_NAME="@COMPONENT@"
COMPONENT_VERSION="@VERSION@"

# === PRE-REQUISITOS ===
echo "=== Build: $COMPONENT_NAME $COMPONENT_VERSION ==="
echo "Prefix: $TERMUX_PREFIX"
echo "Arch: ${TARGET_ARCH:-aarch64}"

# Verificar toolchain
if ! command -v cmake &>/dev/null; then
    echo "❌ cmake required"
    exit 1
fi

# === CONFIGURACIÓN DE COMPILACIÓN ===
BUILD_DIR="build-termux"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# === CROSS-COMPILATION FLAGS ===
# Estas flags se usan en el container termux-packages
CFLAGS="-Os -g0 -D__ANDROID__ -DANDROID"
CXXFLAGS="-Os -g0 -D__ANDROID__ -DANDROID"
LDFLAGS="-L$TERMUX_PREFIX/lib"

export CFLAGS CXXFLAGS LDFLAGS

echo "Configuración lista para: $COMPONENT_NAME"
echo "Ejecuta cmake/make manualmente en: $BUILD_DIR"
