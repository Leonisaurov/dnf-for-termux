#!/usr/bin/env bash
# RPM 4.20.1 build script for Termux CI (x86_64 native in package-builder container)
set -euo pipefail

# === Configuration ===
COMPONENT="rpm"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../../build" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/source/$COMPONENT"
BUILD_DIR="$PROJECT_DIR/build/termux/$COMPONENT/build"
STAGING_DIR="$PROJECT_DIR/build/termux/$COMPONENT/staging"
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

# Install system dependencies for RPM
echo "Installing RPM build dependencies..."
sudo apt-get update -qq 2>/dev/null || true
sudo apt-get install -y -qq \
    libpopt-dev libarchive-dev libsqlite3-dev liblua5.4-dev \
    libbz2-dev libelf-dev 2>&1 | tail -5 || echo "Some packages may already be installed"

# Create build directory
rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

# Configure with cmake
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -G "Ninja" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="$PREFIX/lib" \
  -DENABLE_NLS=OFF \
  -DENABLE_OPENMP=OFF \
  -DENABLE_PYTHON=OFF \
  -DENABLE_PLUGINS=OFF \
  -DENABLE_WERROR=OFF \
  -DENABLE_SQLITE=ON \
  -DENABLE_NDB=OFF \
  -DENABLE_BDB_RO=OFF \
  -DENABLE_TESTSUITE=OFF \
  -DWITH_CAP=OFF \
  -DWITH_ACL=OFF \
  -DWITH_SELINUX=OFF \
  -DWITH_DBUS=OFF \
  -DWITH_AUDIT=OFF \
  -DWITH_FSVERITY=OFF \
  -DWITH_IMAEVM=OFF \
  -DWITH_FAPOLICYD=OFF \
  -DWITH_SEQUOIA=OFF \
  -DWITH_OPENSSL=ON \
  -DWITH_READLINE=ON \
  -DWITH_BZIP2=ON \
  -DWITH_ZSTD=ON \
  -DWITH_LIBDW=OFF \
  -DWITH_LIBELF=OFF \
  -DWITH_LIBLZMA=ON \
  -DWITH_DOXYGEN=OFF \
  -DWITH_ICONV=ON \
  2>&1

# Build
ninja -C "$BUILD_DIR" -j$(nproc) 2>&1

# Install to staging
DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR" 2>&1

echo "=== $COMPONENT build complete ==="
echo "Build artifacts in: $STAGING_DIR"
find "$STAGING_DIR" -type f 2>/dev/null | head -30 || true
