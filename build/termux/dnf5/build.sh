#!/usr/bin/env bash
# DNF5 build script for Termux CI (x86_64 native in package-builder container)
# Builds dnf5 for aarch64 (cross-compiled in container).
set -euo pipefail

# === Configuration ===
COMPONENT="dnf5"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../../build" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/source/$COMPONENT"
BUILD_DIR="$PROJECT_DIR/build/termux/$COMPONENT/build"
STAGING_DIR="$PROJECT_DIR/build/termux/$COMPONENT/staging"
PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"

echo "=== Building $COMPONENT ==="
echo "Source dir: $SOURCE_DIR"
echo "Prefix: $PREFIX"

# === Build tools ===
# Check and install missing build tools (cmake, ninja)
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

# === System dependencies ===
echo "Installing DNF5 build dependencies..."
sudo apt-get update -qq 2>/dev/null || true
sudo apt-get install -y -qq \
    libpopt-dev \
    libsqlite3-dev libjson-c-dev libfmt-dev \
    libglib2.0-dev libxml2-dev libssl-dev \
    libzstd-dev libbz2-dev liblzma-dev 2>&1 | tail -5 || echo "Some packages may already be installed"

# === Install toml11 (header-only TOML parser, required by dnf5) ===
# dnf5 uses toml11 for versionlock config parsing (find_package(toml11))
echo "Installing toml11..."
if apt-cache show libtoml11-dev &>/dev/null; then
    sudo apt-get install -y -qq libtoml11-dev 2>&1 | tail -3
else
    # toml11 v4.3.0 - header-only, just need CMake config installed
    TOML11_VERSION="4.3.0"
    wget -q "https://github.com/ToruNiina/toml11/archive/refs/tags/v${TOML11_VERSION}.tar.gz" -O /tmp/toml11.tar.gz
    tar -xzf /tmp/toml11.tar.gz -C /tmp/
    mkdir -p /tmp/toml11-${TOML11_VERSION}/build
    cmake -S "/tmp/toml11-${TOML11_VERSION}" -B "/tmp/toml11-${TOML11_VERSION}/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -Dtoml11_BUILD_TEST=OFF
    sudo cmake --install "/tmp/toml11-${TOML11_VERSION}/build" 2>&1 | tail -3
    rm -rf "/tmp/toml11-${TOML11_VERSION}" /tmp/toml11.tar.gz
fi
echo "toml11 installed"

# === Apply patches (handled by CI workflow) ===
# Patches are applied by the CI workflow before this script runs.
# If running manually, apply them first: ./scripts/apply-patches.sh dnf5
echo "Patches are applied by CI workflow. Skipping patch application."

# === Cached dependency detection ===
# Use environment variables (RPM_INCLUDE_DIR, RPM_LIB_DIR, LIBSOLV_DIR, etc.)
# to locate cached staging builds of dependencies.
# Fall back to default staging paths when env vars are unset.
echo "Setting up cached dependency paths..."

# Build PKG_CONFIG_PATH from staging directories
PKG_CONFIG_DIRS=""

# Helper: append pkgconfig dir if it exists
_add_pc_dir() {
    local d="$1"
    if [ -d "$d" ]; then
        PKG_CONFIG_DIRS="${PKG_CONFIG_DIRS}${PKG_CONFIG_DIRS:+:}$d"
        echo "  pkg-config: $d"
    fi
}

# Determine staging base from env vars (or fallback)
RPM_STAGING="${RPM_DIR:-$PROJECT_DIR/build/termux/rpm/staging/$PREFIX}"
LIBSOLV_STAGING="${LIBSOLV_DIR:-$PROJECT_DIR/build/termux/libsolv/staging/$PREFIX}"
LIBREPO_STAGING="${LIBREPO_DIR:-$PROJECT_DIR/build/termux/librepo/staging/$PREFIX}"
LIBCOMPS_STAGING="${LIBCOMPS_DIR:-$PROJECT_DIR/build/termux/libcomps/staging/$PREFIX}"
ZCHUNK_STAGING="${ZCHUNK_DIR:-$PROJECT_DIR/build/termux/zchunk/staging/$PREFIX}"

# Export variables for cmake/pkg-config
_add_pc_dir "$RPM_STAGING/lib/pkgconfig"
_add_pc_dir "$LIBSOLV_STAGING/lib/pkgconfig"
_add_pc_dir "$LIBREPO_STAGING/lib/pkgconfig"
_add_pc_dir "$LIBCOMPS_STAGING/lib/pkgconfig"
_add_pc_dir "$ZCHUNK_STAGING/lib/pkgconfig"

if [ -n "$PKG_CONFIG_DIRS" ]; then
    export PKG_CONFIG_PATH="$PKG_CONFIG_DIRS${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
fi

# Also set CFLAGS/CXXFLAGS/LDFLAGS from include/lib dirs for non-pkg-config deps
# Respect explicit RPM_INCLUDE_DIR / RPM_LIB_DIR env vars if set
RPM_INCLUDE="${RPM_INCLUDE_DIR:-$RPM_STAGING/include}"
RPM_LIB="${RPM_LIB_DIR:-$RPM_STAGING/lib}"
if [ -d "$RPM_INCLUDE" ]; then
    export CFLAGS="${CFLAGS:-} -I$RPM_INCLUDE"
    export CXXFLAGS="${CXXFLAGS:-} -I$RPM_INCLUDE"
fi
if [ -d "$RPM_LIB" ]; then
    export LDFLAGS="${LDFLAGS:-} -L$RPM_LIB"
fi

# Build CMAKE_PREFIX_PATH from staging dirs (semicolon-separated for cmake)
CMAKE_PREFIX_LIST=""
for d in "$RPM_STAGING" "$LIBSOLV_STAGING" "$LIBREPO_STAGING" "$LIBCOMPS_STAGING" "$ZCHUNK_STAGING"; do
    if [ -d "$d" ]; then
        CMAKE_PREFIX_LIST="${CMAKE_PREFIX_LIST}${CMAKE_PREFIX_LIST:+;}$d"
    fi
done

# === Create build directories ===
rm -rf "$BUILD_DIR" "$STAGING_DIR"
mkdir -p "$BUILD_DIR" "$STAGING_DIR"

# === Disable -Werror (incompatible with Termux/Android) ===
# dnf5/CMakeLists.txt hardcodes add_compile_options(-Werror).
# We comment it out for the build.
sed -i 's/add_compile_options(-Wall -Wextra -Werror)/add_compile_options(-Wall -Wextra)\n# -Werror disabled for Termux/' "$SOURCE_DIR/CMakeLists.txt"

# === Configure with cmake ===
# All options below are sourced from dnf5's CMakeLists.txt.
# Features incompatible with Termux/Android are explicitly disabled.
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -G "Ninja" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR="$PREFIX/lib" \
  ${CMAKE_PREFIX_LIST:+-DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_LIST"} \
  -DWITH_DNF5DAEMON_SERVER=OFF \
  -DWITH_DNF5DAEMON_CLIENT=OFF \
  -DWITH_ACL=OFF \
  -DWITH_MODULEMD=OFF \
  -DWITH_SYSTEMD=OFF \
  -DWITH_HTML=OFF \
  -DWITH_MAN=OFF \
  -DWITH_TRANSLATIONS=OFF \
  -DWITH_TESTS=OFF \
  -DWITH_DNF5DAEMON_TESTS=OFF \
  -DWITH_SANITIZERS=OFF \
  -DWITH_PERL5=OFF \
  -DWITH_PYTHON3=OFF \
  -DWITH_RUBY=OFF \
  -DWITH_GO=OFF \
  -DWITH_DNF5_OBSOLETES_DNF=OFF \
  -DWITH_PYTHON_PLUGINS_LOADER=OFF \
  -DWITH_PLUGIN_APPSTREAM=OFF \
  -DWITH_PLUGIN_EXPIRED_PGP_KEYS=OFF \
  -DWITH_PLUGIN_RHSM=OFF \
  -DWITH_PLUGIN_MANIFEST=OFF \
  -DWITH_COMPS=ON \
  2>&1

# === Build ===
ninja -C "$BUILD_DIR" -j$(nproc) 2>&1

# === Install to staging ===
DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR" 2>&1

echo "=== $COMPONENT build complete ==="
echo "Build artifacts in: $STAGING_DIR"
find "$STAGING_DIR" -type f 2>/dev/null | head -30 || true
