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

# Check and install missing build tools
CMAKE=$(command -v cmake 2>/dev/null || true)
if [ -z "$CMAKE" ]; then
    echo "Downloading cmake..."
    CMAKE_VERSION=3.31.7
    wget -q "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" -O /tmp/cmake.tar.gz
    tar -xzf /tmp/cmake.tar.gz -C /tmp/
    export PATH="/tmp/cmake-${CMAKE_VERSION}-linux-x86_64/bin:$PATH"
    echo "cmake installed at $(which cmake)"
fi
NINJA=$(command -v ninja 2>/dev/null || command -v ninja-build 2>/dev/null || true)
if [ -z "$NINJA" ]; then
    echo "Downloading ninja..."
    wget -q "https://github.com/ninja-build/ninja/releases/download/v1.13.0/ninja-linux.zip" -O /tmp/ninja-linux.zip
    unzip -o /tmp/ninja-linux.zip -d /tmp/ninja 2>/dev/null || true
    export PATH="/tmp/ninja:$PATH"
    echo "ninja installed at $(which ninja)"
fi

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
find "$STAGING_DIR" -type f 2>/dev/null | head -30 || true
