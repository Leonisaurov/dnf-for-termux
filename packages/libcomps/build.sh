TERMUX_PKG_HOMEPAGE=https://github.com/rpm-software-management/libcomps
TERMUX_PKG_DESCRIPTION="Library for Comps XML files (Fedora package groups)"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=0.1.24
TERMUX_PKG_SRCURL=https://github.com/rpm-software-management/libcomps/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=c24a81dea8e9f7f3c877618d3812a5293df772abc6b90fad1d34fa62326141bc
TERMUX_PKG_DEPENDS="libxml2, zlib, libexpat"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="-DENABLE_DOCS=OFF -DENABLE_TESTS=OFF -DENABLE_DEVELOPMENT=ON"

# Generador Unix Makefiles. La variable REAL del framework es
# TERMUX_PKG_CMAKE_BUILD (termux_step_setup_variables.sh:119 la inicializa a
# Ninja; termux_step_configure_cmake.sh:2-6 ramifica en "Ninja" -> command -v
# ninja, y cualquier otro valor -> command -v make). TERMUX_PKG_CMAKE_GENERATOR
# NO existe en el framework: nuestro valor previo se ignoró y quedó Ninja como
# default, matando el build en MAKE_PROGRAM_PATH=$(command -v ninja) bajo set -e.
TERMUX_PKG_CMAKE_BUILD="Unix Makefiles"

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
	# Replica scripts/build/configure/termux_step_configure.sh:16-18 del
	# framework: el flujo NORMAL llama termux_setup_ninja antes de
	# termux_step_configure_cmake cuando el generador es Ninja. Este step custom
	# lo saltaba; garantizarlo aquí evita la muerte en
	# MAKE_PROGRAM_PATH=$(command -v ninja) si se vuelve al generador Ninja.
	termux_setup_ninja
	termux_step_configure_cmake
}
