#!/usr/bin/env bash
# libcomps build script for Termux
# Builds natively (x86_64) in the package-builder container
set -euo pipefail

# === Configuration ===
COMPONENT="libcomps"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../source/$COMPONENT"
BUILD_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/build"
STAGING_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/staging"
PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"

echo "=== Building $COMPONENT ==="
echo "Source dir: $SOURCE_DIR"
echo "Prefix: $PREFIX"

# Dependencies are pre-installed in the package-builder container
echo "Using pre-installed dependencies"

# Create build directory
rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

# Configure with cmake
cmake -S "$SOURCE_DIR/libcomps" -B "$BUILD_DIR" \
  -G "Ninja" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="$PREFIX/lib" \
  -DBUILD_LIBCOMPS_SHARED=ON \
  -DENABLE_DEVELOPMENT=ON \
  -DENABLE_DOCS=OFF \
  -DENABLE_TESTS=OFF \
  2>&1

# Build
ninja -C "$BUILD_DIR" -j$(nproc) 2>&1

# Install to staging
DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR" 2>&1

echo "=== $COMPONENT build complete ==="
echo "Build artifacts in: $STAGING_DIR"
find "$STAGING_DIR" -type f 2>/dev/null | head -30
