#=============================================================================
# Toolchain file for cross-compiling dnf-for-termux to aarch64 (ARM64)
# Target: Android/Termux (bionic libc, Linux kernel)
# Host container: ghcr.io/termux/package-builder:latest
#=============================================================================

# Target system
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Cross-compilers (must be in PATH in the CI container)
set(CMAKE_C_COMPILER aarch64-linux-android-clang)
set(CMAKE_CXX_COMPILER aarch64-linux-android-clang++)

# Toolchain utilities
set(CMAKE_AR aarch64-linux-android-ar CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB aarch64-linux-android-ranlib CACHE FILEPATH "Ranlib")
set(CMAKE_LINKER aarch64-linux-android-ld CACHE FILEPATH "Linker")
set(CMAKE_STRIP aarch64-linux-android-strip CACHE FILEPATH "Strip")

# Skip compiler test - cross-compilers may not link simple test programs
# due to missing crt objects in non-standard paths
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Find root mode - only search target sysroot for libs/includes
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
