#!/usr/bin/env bash
# zchunk build script for Termux
# Builds natively (x86_64) in the package-builder container
set -euo pipefail

# === Configuration ===
COMPONENT="zchunk"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../source/$COMPONENT"
BUILD_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/build"
STAGING_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/staging"
PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"

echo "=== Building $COMPONENT ==="
echo "Source dir: $SOURCE_DIR"
echo "Prefix: $PREFIX"

# Check and install missing build tools
MESON=$(command -v meson 2>/dev/null || true)
if [ -z "$MESON" ]; then
    echo "Installing meson..."
    pip install meson 2>&1 | tail -3
fi
NINJA=$(command -v ninja 2>/dev/null || command -v ninja-build 2>/dev/null || true)
if [ -z "$NINJA" ]; then
    echo "Installing ninja..."
    pip install ninja 2>&1 | tail -3
fi

# Create build directory
rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

# Configure with meson
cd "$SOURCE_DIR"
meson setup "$BUILD_DIR" \
  --prefix="$PREFIX" \
  --libdir="$PREFIX/lib" \
  -Dwith-zstd=enabled \
  -Dwith-openssl=enabled \
  -Dwith-curl=enabled \
  -Ddocs=false \
  -Dtests=false \
  --default-library=shared \
  2>&1

# Build
meson compile -C "$BUILD_DIR" -v 2>&1

# Install to staging
DESTDIR="$STAGING_DIR" meson install -C "$BUILD_DIR" 2>&1

echo "=== $COMPONENT build complete ==="
echo "Build artifacts in: $STAGING_DIR"
find "$STAGING_DIR" -type f 2>/dev/null | head -30
