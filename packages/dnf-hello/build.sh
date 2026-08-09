TERMUX_PKG_HOMEPAGE=https://github.com/Leonisaurov/dnf-for-termux
TERMUX_PKG_DESCRIPTION="Hello world test package for dnf5 on Termux"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.0
TERMUX_PKG_REVISION=1
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_make_install() {
	install -Dm755 "$TERMUX_PKG_BUILDER_DIR/dnf-hello" "$TERMUX_PREFIX/bin/dnf-hello"
}
