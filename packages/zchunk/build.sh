TERMUX_PKG_HOMEPAGE=https://github.com/zchunk/zchunk
TERMUX_PKG_DESCRIPTION="A file format designed for highly efficient deltas while maintaining good compression"
TERMUX_PKG_LICENSE="BSD-2-Clause"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.5.3
TERMUX_PKG_SRCURL=https://github.com/zchunk/zchunk/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=832381dafe192109742c141ab90a6bc0a9d7e9926a4bafbdf98f596680da2a95
TERMUX_PKG_DEPENDS="zlib, libzstd, openssl, libcurl"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="-Dwith-zstd=enabled -Dwith-openssl=enabled -Dwith-curl=enabled -Dtests=false -Ddocs=false"
