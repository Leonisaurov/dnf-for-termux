#!/usr/bin/env bash
# gha-build-all.sh - Orquestador de compilación para GitHub Actions
# Compila todos los componentes del stack DNF en orden de dependencias.
# Uso: ./scripts/gha-build-all.sh [component]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Dependency order
ORDER=(zchunk libcomps libsolv librepo rpm dnf5)
COMPONENT="${1:-all}"

echo "=== dnf-for-termux: CI Build Orchestrator ==="
echo "Target: $TARGET_ARCH (aarch64)"
echo "Prefix: $TERMUX_PREFIX"
echo ""

build_component() {
    local name="$1"
    echo "--- Building: $name ---"
    
    local SRC_DIR="$PROJECT_DIR/source/$name"
    local BUILD_DIR="$PROJECT_DIR/build/termux/$name"
    local PATCH_DIR="$PROJECT_DIR/patches/$name"
    
    if [ ! -d "$SRC_DIR" ]; then
        echo "⚠️  Source not found: $SRC_DIR"
        return 1
    fi
    
    # Apply patches
    if [ -d "$PATCH_DIR" ]; then
        for patch in "$PATCH_DIR"/*.patch; do
            if [ -s "$patch" ]; then
                echo "  Applying patch: $(basename $patch)"
                patch -p1 -d "$SRC_DIR" < "$patch" 2>/dev/null || \
                patch -p0 -d "$SRC_DIR" < "$patch" 2>/dev/null || \
                echo "  ⚠️  Patch skipped: $(basename $patch)"
            fi
        done
    fi
    
    # Execute build if script exists
    if [ -f "$BUILD_DIR/build.sh" ]; then
        echo "  Running build script..."
        chmod +x "$BUILD_DIR/build.sh"
        (cd "$SRC_DIR" && TERMUX_PREFIX="$TERMUX_PREFIX" bash "$BUILD_DIR/build.sh")
        echo "  ✅ $name built successfully"
    else
        echo "  ⚠️  No build.sh for $name"
    fi
}

# Build in dependency order
for component in "${ORDER[@]}"; do
    if [ "$COMPONENT" = "all" ] || [ "$COMPONENT" = "$component" ]; then
        build_component "$component"
    fi
done

echo ""
echo "=== Build complete ==="
