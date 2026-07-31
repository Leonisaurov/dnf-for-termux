TERMUX_PKG_HOMEPAGE=https://github.com/rpm-software-management/libcomps
TERMUX_PKG_DESCRIPTION="Library for Comps XML files (Fedora package groups)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=0.1.24
TERMUX_PKG_SRCURL=https://github.com/rpm-software-management/libcomps/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=c24a81dea8e9f7f3c877618d3812a5293df772abc6b90fad1d34fa62326141bc
TERMUX_PKG_DEPENDS="libxml2, zlib, libexpat"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="-DENABLE_DOCS=OFF -DENABLE_TESTS=OFF -DENABLE_DEVELOPMENT=ON"

# El framework auto-aplica solo *.patch (termux_step_patch_package.sh usa
# `find -name \*.patch | sed ... | patch --silent -p1`), con fallo silencioso.
# El overlay .diff se aplica aquí explícitamente tras extraer el source.
termux_step_post_get_source() {
	cd "$TERMUX_PKG_SRCDIR"
	echo "Aplicando overlay patch 0001-skip-python-bindings.diff..."
	patch --forward --batch -p1 < "$TERMUX_PKG_BUILDER_DIR/0001-skip-python-bindings.diff"
}

# CMakeLists.txt vive en libcomps/ (subdir del source), no en la raíz
termux_step_configure() {
	TERMUX_PKG_SRCDIR="$TERMUX_PKG_SRCDIR/libcomps"
	termux_step_configure_cmake
}
