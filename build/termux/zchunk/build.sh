#!/usr/bin/env bash
# zchunk build script for Termux
# Builds natively (x86_64) in the package-builder container
set -euo pipefail

# === Configuration ===
COMPONENT="zchunk"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../source/$COMPONENT"
BUILD_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/build"
STAGING_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/staging"
PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"

echo "=== Building $COMPONENT ==="
echo "Source dir: $SOURCE_DIR"
echo "Prefix: $PREFIX"

# Check and install missing build tools
NINJA=$(command -v ninja 2>/dev/null || command -v ninja-build 2>/dev/null || true)
if [ -z "$NINJA" ]; then
    echo "Downloading ninja..."
    wget -q "https://github.com/ninja-build/ninja/releases/download/v1.13.0/ninja-linux.zip" -O /tmp/ninja-linux.zip
    unzip -o /tmp/ninja-linux.zip -d /tmp/ninja 2>/dev/null
    export PATH="/tmp/ninja:$PATH"
    echo "ninja installed at $(which ninja)"
fi
MESON=$(command -v meson 2>/dev/null || true)
if [ -z "$MESON" ]; then
    echo "Downloading meson..."
    pip install --break-system-packages meson 2>&1 | tail -3
    export PATH="$HOME/.local/bin:$PATH"
fi

# Create build directory
rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

# Export cross-compile toolchain for Meson (Android NDK)
export CC=aarch64-linux-android-clang
export CXX=aarch64-linux-android-clang++
export AR=aarch64-linux-android-ar
export STRIP=aarch64-linux-android-strip

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
find "$STAGING_DIR" -type f 2>/dev/null | head -30 || true
