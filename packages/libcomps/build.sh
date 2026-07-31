TERMUX_PKG_HOMEPAGE=https://github.com/rpm-software-management/libcomps
TERMUX_PKG_DESCRIPTION="Library for Comps XML files (Fedora package groups)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=0.1.24
TERMUX_PKG_SRCURL=https://github.com/rpm-software-management/libcomps/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=c24a81dea8e9f7f3c877618d3812a5293df772abc6b90fad1d34fa62326141bc
TERMUX_PKG_DEPENDS="libxml2, zlib, libexpat"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="-DENABLE_DOCS=OFF -DENABLE_TESTS=OFF -DENABLE_DEVELOPMENT=ON"

# CMakeLists.txt vive en libcomps/ (subdir del source), no en la raíz
termux_step_configure() {
	TERMUX_PKG_SRCDIR="$TERMUX_PKG_SRCDIR/libcomps"
	termux_step_configure_cmake
}
