#!/usr/bin/env bash
# setup-ndk.sh - Install Android NDK for cross-compilation
set -euo pipefail

NDK_VERSION="r27"
NDK_DIR="/tmp/android-ndk"
NDK_URL="https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
TOOLCHAIN_DIR="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"

export_ndk_vars() {
    # Export toolchain variables with ABSOLUTE paths via GITHUB_ENV
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

# Check if cross-compiler already available
if command -v aarch64-linux-android-clang &>/dev/null; then
    echo "✅ Cross-compiler aarch64-linux-android-clang found in PATH"
    export_ndk_vars
    exit 0
fi

# Check if NDK already installed
if [ -f "$TOOLCHAIN_DIR/aarch64-linux-android-clang" ]; then
    echo "✅ NDK found at $NDK_DIR"
    export_ndk_vars
    exit 0
fi

# Download and install NDK
echo "📥 Downloading Android NDK ${NDK_VERSION}..."
curl -Lo /tmp/ndk.zip "$NDK_URL" 2>&1 | tail -5

echo "📦 Extracting NDK..."
unzip -q /tmp/ndk.zip -d /tmp/ndk-extract
mv /tmp/ndk-extract/android-ndk-${NDK_VERSION} "$NDK_DIR"
rm -rf /tmp/ndk.zip /tmp/ndk-extract

echo "✅ NDK installed at $NDK_DIR"
export_ndk_vars
