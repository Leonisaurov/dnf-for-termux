#=============================================================================
# Toolchain file for cross-compiling dnf-for-termux to aarch64 (ARM64)
# Target: Android/Termux (bionic libc, Linux kernel)
# Host container: ghcr.io/termux/package-builder:latest
# NDK r27: compilers are API-versioned; tools are llvm-*
# Vars exported by scripts/setup-ndk.sh via GITHUB_ENV
#=============================================================================

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Cross-compilers (absolute paths from setup-ndk.sh)
set(CMAKE_C_COMPILER $ENV{NDK_CC})
set(CMAKE_CXX_COMPILER $ENV{NDK_CXX})

# Toolchain utilities (NDK r27 llvm-* tools)
set(CMAKE_AR $ENV{NDK_TOOLCHAIN_BIN}/llvm-ar CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB $ENV{NDK_TOOLCHAIN_BIN}/llvm-ranlib CACHE FILEPATH "Ranlib")
set(CMAKE_LINKER $ENV{NDK_TOOLCHAIN_BIN}/ld.lld CACHE FILEPATH "Linker")
set(CMAKE_STRIP $ENV{NDK_TOOLCHAIN_BIN}/llvm-strip CACHE FILEPATH "Strip")

# Skip compiler test - cross-compilers may not link simple test programs
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Find root mode - only search target sysroot for libs/includes
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
