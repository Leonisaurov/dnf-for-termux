#!/usr/bin/env bash
# setup-ndk.sh - Install Android NDK for cross-compilation
set -euo pipefail

NDK_VERSION="r27"
NDK_DIR="/tmp/android-ndk"
NDK_URL="https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
TOOLCHAIN_DIR=""

find_cross_compiler() {
    # 1) Prefer the standard NDK llvm prebuilt bin directory
    local d found
    for d in "$NDK_DIR"/toolchains/llvm/prebuilt/*/bin; do
        [ -d "$d" ] || continue
        if [ -x "$d/aarch64-linux-android-clang" ]; then
            TOOLCHAIN_DIR="$d"
            echo "✅ Cross-compiler found at: $TOOLCHAIN_DIR"
            return 0
        fi
    done
    # 2) Fallback: any executable clang inside a bin/ dir (excludes build/core dirs)
    found=$(find "$NDK_DIR" -path "*/bin/aarch64-linux-android-clang" \( -type f -o -type l \) -exec test -x {} \; -print 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        TOOLCHAIN_DIR="$(dirname "$found")"
        echo "✅ Cross-compiler found (fallback) at: $TOOLCHAIN_DIR"
        return 0
    fi
    echo "❌ Cross-compiler NOT found"
    return 1
}

export_ndk_vars() {
    if [ -z "$TOOLCHAIN_DIR" ]; then
        echo "❌ TOOLCHAIN_DIR is empty, cannot export"
        exit 1
    fi
    {
        echo "NDK_TOOLCHAIN_BIN=$TOOLCHAIN_DIR"
        echo "CC=$TOOLCHAIN_DIR/aarch64-linux-android-clang"
        echo "CXX=$TOOLCHAIN_DIR/aarch64-linux-android-clang++"
        echo "AR=$TOOLCHAIN_DIR/aarch64-linux-android-ar"
        echo "RANLIB=$TOOLCHAIN_DIR/aarch64-linux-android-ranlib"
        echo "STRIP=$TOOLCHAIN_DIR/aarch64-linux-android-strip"
        echo "LD=$TOOLCHAIN_DIR/aarch64-linux-android-ld"
    } >> "$GITHUB_ENV"
    export PATH="$TOOLCHAIN_DIR:$PATH"
    if [ -n "$GITHUB_PATH" ]; then
        echo "$TOOLCHAIN_DIR" >> "$GITHUB_PATH"
    fi
}

# Check if cross-compiler already in PATH
if command -v aarch64-linux-android-clang &>/dev/null; then
    echo "✅ Cross-compiler aarch64-linux-android-clang found in PATH"
    TOOLCHAIN_DIR="$(dirname "$(command -v aarch64-linux-android-clang)")"
    export_ndk_vars
    exit 0
fi

# Check if NDK already installed somewhere
if [ -d "$NDK_DIR" ] && find_cross_compiler; then
    echo "✅ NDK found at $NDK_DIR"
    export_ndk_vars
    exit 0
fi

# Download and extract NDK
echo "📥 Downloading Android NDK ${NDK_VERSION}..."
mkdir -p /tmp
curl -Lo /tmp/ndk.zip "$NDK_URL" 2>&1 | tail -5

echo "📦 Extracting NDK..."
unzip -q /tmp/ndk.zip -d /tmp/ndk-extract
rm -rf "$NDK_DIR"
mv /tmp/ndk-extract/android-ndk-${NDK_VERSION} "$NDK_DIR"
rm -rf /tmp/ndk.zip /tmp/ndk-extract

# Verify the cross-compiler exists (with diagnostic output if not)
if find_cross_compiler; then
    echo "✅ NDK installed and verified"
    export_ndk_vars
    exit 0
else
    echo "❌ Cross-compiler NOT found after extraction!"
    echo "--- NDK layout (first 3 levels): ---"
    ls -la "$NDK_DIR" 2>/dev/null | head -30
    echo "--- Searching for any clang: ---"
    find "$NDK_DIR" -name "*clang*" 2>/dev/null | head -20
    echo "--- Searching for aarch64 bin dirs: ---"
    find "$NDK_DIR" -type d -name "bin" 2>/dev/null | head -20
    exit 1
fi
