#!/usr/bin/env bash
# libsolv build script for Termux
# Builds natively (x86_64) in the package-builder container
set -euo pipefail

# === Configuration ===
COMPONENT="libsolv"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DIR="$SCRIPT_DIR/../source/$COMPONENT"
BUILD_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/build"
STAGING_DIR="$SCRIPT_DIR/../build/termux/$COMPONENT/staging"
PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"

echo "=== Building $COMPONENT ==="
echo "Source dir: $SOURCE_DIR"
echo "Prefix: $PREFIX"

# Install dependencies
apt-get update -qq
apt-get install -y -qq cmake ninja-build pkg-config zlib1g-dev libexpat1-dev liblzma-dev libbz2-dev libzstd-dev 2>&1 | tail -5

# Create build directory
rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

# Configure with cmake
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -G "Ninja" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="$PREFIX/lib" \
  -DENABLE_RPMMD=ON \
  -DENABLE_COMPS=ON \
  -DENABLE_DEBIAN=ON \
  -DENABLE_LZMA_COMPRESSION=ON \
  -DENABLE_ZSTD_COMPRESSION=ON \
  -DENABLE_BZIP2_COMPRESSION=ON \
  -DENABLE_STATIC=OFF \
  -DENABLE_PERL=OFF \
  -DENABLE_PYTHON=OFF \
  -DENABLE_RUBY=OFF \
  -DENABLE_TCL=OFF \
  -DENABLE_LUA=OFF \
  -DENABLE_RPMDB=OFF \
  -DENABLE_PUBKEY=OFF \
  -DBUILD_TESTING=OFF \
  2>&1

# Build
ninja -C "$BUILD_DIR" -j$(nproc) 2>&1

# Install to staging
DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR" 2>&1

echo "=== $COMPONENT build complete ==="
echo "Build artifacts in: $STAGING_DIR"
find "$STAGING_DIR" -type f 2>/dev/null | head -30
