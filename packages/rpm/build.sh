TERMUX_PKG_HOMEPAGE=https://rpm.org/
TERMUX_PKG_DESCRIPTION="RPM Package Manager"
TERMUX_PKG_LICENSE="GPL-2.0, LGPL-2.0"
TERMUX_PKG_LICENSE_FILE="COPYING"
TERMUX_PKG_MAINTAINER="@termux"
_MAJOR_VERSION=4.18
TERMUX_PKG_VERSION=${_MAJOR_VERSION}.1
# REVISION 3: el rpm parcheado es 4.18.1-3 > el oficial 4.18.1-2 de termux-main;
# asi el instalador pacman no lo salta con --needed cuando ya hay rpm instalado.
# REVISION 4: (bump: nuevo patch termux-remove-sqlite3-global-log.patch — fix SIGSEGV dnf5 history; > 4.18.1-3 anterior)
TERMUX_PKG_REVISION=4
TERMUX_PKG_SRCURL=https://ftp.osuosl.org/pub/rpm/releases/rpm-${_MAJOR_VERSION}.x/rpm-${TERMUX_PKG_VERSION}.tar.bz2
TERMUX_PKG_SHA256=37f3b42c0966941e2ad3f10fde3639824a6591d07197ba8fd0869ca0779e1f56
TERMUX_PKG_DEPENDS="file, libandroid-spawn, libarchive, libbz2, libgcrypt, libiconv, lua54, liblzma, libpopt, libsqlite, readline, zlib, zstd"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--disable-static
--disable-openmp
"

termux_step_pre_configure() {
	export LUA_CFLAGS="-I$TERMUX_PREFIX/include/lua5.4"
	export LUA_LIBS="-L$TERMUX_PREFIX/lib/liblua5.4.so"
	LDFLAGS+=" -llua5.4 -landroid-spawn $($CC -print-libgcc-file-name)"
}
