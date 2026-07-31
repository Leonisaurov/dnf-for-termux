#!/usr/bin/env bash
# setup-ndk.sh - Install Android NDK for cross-compilation
# NDK r27+: cross-compilers are API-versioned (aarch64-linux-android<api>-clang)
# and tools are llvm-* (llvm-ar, llvm-ranlib, llvm-strip, ld.lld)
set -euo pipefail

NDK_VERSION="r27"
NDK_DIR="/tmp/android-ndk"
NDK_URL="https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
TOOLCHAIN_DIR=""
NDK_CC=""
NDK_CXX=""

find_cross_compiler() {
    local d f
    for d in "$NDK_DIR"/toolchains/llvm/prebuilt/*/bin; do
        [ -d "$d" ] || continue
        # Prefer API 24 (Termux minimum), fallback to lowest available
        f=""
        [ -x "$d/aarch64-linux-android24-clang" ] && f="$d/aarch64-linux-android24-clang"
        if [ -z "$f" ]; then
            f=$(ls "$d"/aarch64-linux-android*-clang 2>/dev/null | sort -V | head -1)
        fi
        if [ -n "$f" ] && [ -x "$f" ]; then
            TOOLCHAIN_DIR="$d"
            NDK_CC="$f"
            NDK_CXX="${f%-clang}-clang++"
            echo "✅ Cross-compiler found: $NDK_CC"
            echo "   CXX: $NDK_CXX"
            return 0
        fi
    done
    echo "❌ Cross-compiler NOT found in $NDK_DIR"
    return 1
}

export_ndk_vars() {
    if [ -z "$TOOLCHAIN_DIR" ] || [ -z "$NDK_CC" ]; then
        echo "❌ Toolchain vars not set, cannot export"
        exit 1
    fi
    {
        echo "NDK_TOOLCHAIN_BIN=$TOOLCHAIN_DIR"
        echo "NDK_CC=$NDK_CC"
        echo "NDK_CXX=$NDK_CXX"
        echo "CC=$NDK_CC"
        echo "CXX=$NDK_CXX"
        echo "AR=$TOOLCHAIN_DIR/llvm-ar"
        echo "RANLIB=$TOOLCHAIN_DIR/llvm-ranlib"
        echo "STRIP=$TOOLCHAIN_DIR/llvm-strip"
        echo "LD=$TOOLCHAIN_DIR/ld.lld"
    } >> "$GITHUB_ENV"
    export PATH="$TOOLCHAIN_DIR:$PATH"
    if [ -n "$GITHUB_PATH" ]; then
        echo "$TOOLCHAIN_DIR" >> "$GITHUB_PATH"
    fi
}

# Check if cross-compiler already in PATH (unlikely in fresh container)
if command -v aarch64-linux-android-clang &>/dev/null; then
    echo "✅ Cross-compiler in PATH"
    TOOLCHAIN_DIR="$(dirname "$(command -v aarch64-linux-android-clang)")"
    NDK_CC="$(command -v aarch64-linux-android-clang)"
    NDK_CXX="$(command -v aarch64-linux-android-clang++)"
    export_ndk_vars
    exit 0
fi

# Check if NDK already installed
if [ -d "$NDK_DIR" ] && find_cross_compiler; then
    echo "✅ NDK found at $NDK_DIR"
    export_ndk_vars
    exit 0
fi

# Download and extract NDK
echo "📥 Downloading Android NDK ${NDK_VERSION}..."
curl -Lo /tmp/ndk.zip "$NDK_URL" 2>&1 | tail -5

echo "📦 Extracting NDK..."
unzip -q /tmp/ndk.zip -d /tmp/ndk-extract || { echo "❌ unzip failed"; exit 1; }
rm -rf "$NDK_DIR"
mv /tmp/ndk-extract/android-ndk-${NDK_VERSION} "$NDK_DIR" || { echo "❌ mv failed"; exit 1; }
rm -rf /tmp/ndk.zip /tmp/ndk-extract

# Verify cross-compiler exists
if find_cross_compiler; then
    echo "✅ NDK installed and verified"
    export_ndk_vars
    exit 0
else
    echo "❌ Cross-compiler NOT found after extraction!"
    echo "--- NDK top level: ---"
    ls "$NDK_DIR" 2>/dev/null || true
    echo "--- llvm prebuilt bin (sample): ---"
    ls "$NDK_DIR"/toolchains/llvm/prebuilt/*/bin 2>/dev/null | head -30 || true
    echo "--- aarch64 wrappers: ---"
    ls "$NDK_DIR"/toolchains/llvm/prebuilt/*/bin/aarch64-linux-android* 2>/dev/null | head -20 || true
    exit 1
fi
