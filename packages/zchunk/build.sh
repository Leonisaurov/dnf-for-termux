TERMUX_PKG_HOMEPAGE=https://github.com/zchunk/zchunk
TERMUX_PKG_DESCRIPTION="A file format designed for highly efficient deltas while maintaining good compression"
TERMUX_PKG_LICENSE="BSD-2-Clause"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.5.3
TERMUX_PKG_SRCURL=https://github.com/zchunk/zchunk/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=832381dafe192109742c141ab90a6bc0a9d7e9926a4bafbdf98f596680da2a95
TERMUX_PKG_DEPENDS="zlib, zstd, openssl, libcurl"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="-Dwith-zstd=enabled -Dwith-openssl=enabled -Dwith-curl=enabled -Dtests=false -Ddocs=false"

# zchunk bundlea gnulib/argp (bionic no trae argp) y meson install lo instala
# (include/argp.h + lib/libargp.a). El paquete argp de Termux ya provee esos
# archivos, asi que se eliminan del staging antes del empaquetado.
# El argp bundleado queda linkeado estaticamente en los binarios CLI, por lo
# que el runtime no necesita el paquete argp (sin DEPENDS/BUILD_DEPENDS).
termux_step_pre_massage() {
	rm -f "$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX_CLASSICAL/include/argp.h"
	rm -f "$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX_CLASSICAL/lib/libargp.a"
}
