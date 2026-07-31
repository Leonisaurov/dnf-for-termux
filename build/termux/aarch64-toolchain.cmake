#=============================================================================
# Toolchain file for cross-compiling dnf-for-termux to aarch64 (ARM64)
# Target: Android/Termux (bionic libc, Linux kernel)
# Host container: ghcr.io/termux/package-builder:latest
#=============================================================================

# Target system
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Cross-compilers (absolute paths via NDK_TOOLCHAIN_BIN env var)
set(CMAKE_C_COMPILER $ENV{NDK_TOOLCHAIN_BIN}/aarch64-linux-android-clang)
set(CMAKE_CXX_COMPILER $ENV{NDK_TOOLCHAIN_BIN}/aarch64-linux-android-clang++)

# Toolchain utilities
set(CMAKE_AR $ENV{NDK_TOOLCHAIN_BIN}/aarch64-linux-android-ar CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB $ENV{NDK_TOOLCHAIN_BIN}/aarch64-linux-android-ranlib CACHE FILEPATH "Ranlib")
set(CMAKE_LINKER $ENV{NDK_TOOLCHAIN_BIN}/aarch64-linux-android-ld CACHE FILEPATH "Linker")
set(CMAKE_STRIP $ENV{NDK_TOOLCHAIN_BIN}/aarch64-linux-android-strip CACHE FILEPATH "Strip")

# Skip compiler test - cross-compilers may not link simple test programs
# due to missing crt objects in non-standard paths
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Find root mode - only search target sysroot for libs/includes
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
