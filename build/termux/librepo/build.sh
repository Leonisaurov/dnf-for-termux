#!/usr/bin/env bash
# librepo build script for Termux
# Builds natively (x86_64) in the package-builder container
set -euo pipefail

# === Configuration ===
COMPONENT="librepo"
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

# Ensure build dependencies (RPM linkage)
sudo apt-get update -qq 2>/dev/null || true
sudo apt-get install -y -qq \
    libpopt-dev \
    liblua5.4-dev \
    libarchive-dev \
    libbz2-dev \
    libzstd-dev \
    libssl-dev \
    libsqlite3-dev \
    libelf-dev \
    libmagic-dev \
    2>&1 | tail -5 || echo "Some packages may already be installed"

# Create build directory
rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

# Configurar PKG_CONFIG_PATH para encontrar rpm.pc del staging
RPM_STAGING="$SCRIPT_DIR/../build/termux/rpm/staging"
if [ -d "$RPM_STAGING/$PREFIX/lib/pkgconfig" ]; then
    export PKG_CONFIG_PATH="$RPM_STAGING/$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    echo "✅ RPM pkgconfig found: $PKG_CONFIG_PATH"
else
    echo "⚠️ RPM pkgconfig NOT found at $RPM_STAGING/$PREFIX/lib/pkgconfig"
    # Intentar buscar en el sistema
    ls /usr/lib/pkgconfig/rpm.pc 2>/dev/null && echo "System rpm.pc found" || echo "No system rpm.pc either"
fi

# LDFLAGS para linkear contra RPM
export LDFLAGS="${LDFLAGS:-} -L$RPM_STAGING/$PREFIX/lib -Wl,-rpath-link,$RPM_STAGING/$PREFIX/lib"

# También necesitamos -I flags para los headers de RPM durante compilación
export CFLAGS="${CFLAGS:-} -I$RPM_STAGING/$PREFIX/include"
echo "CFLAGS now: $CFLAGS"

# Configure with cmake
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -G "Ninja" \
  -DCMAKE_TOOLCHAIN_FILE="$PROJECT_DIR/build/termux/aarch64-toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="$PREFIX/lib" \
  -DENABLE_DOCS=OFF \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_TESTS=OFF \
  -DWITH_PYTHON3=OFF \
  -DENABLE_PYTHON=OFF \
  -DWITH_ZCHUNK=OFF \
  -DUSE_GPGME=ON \
  -DENABLE_SELINUX=OFF \
  -DPKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
  2>&1

# Build
ninja -C "$BUILD_DIR" -j$(nproc) 2>&1

# Install to staging
DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR" 2>&1

echo "=== $COMPONENT build complete ==="
echo "Build artifacts in: $STAGING_DIR"
find "$STAGING_DIR" -type f 2>/dev/null | head -30 || true
