TERMUX_PKG_HOMEPAGE=https://github.com/rpm-software-management/dnf5
TERMUX_PKG_DESCRIPTION="DNF5 is the next-generation version of the DNF package manager"
TERMUX_PKG_LICENSE="LGPL-2.1-or-later"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=5.4.2.1
TERMUX_PKG_SRCURL=https://github.com/rpm-software-management/dnf5/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=6b3f23275a99c66c4b416d4d312f22da779e90f29c881be73eabfc459fca4fef
TERMUX_PKG_DEPENDS="rpm, libsolv, librepo, libcomps, zchunk, libsqlite, json-c, fmt, glib, libxml2, zstd, liblzma, openssl, zlib, libsmartcols, libandroid-glob"
TERMUX_PKG_BUILD_DEPENDS="libcurl"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DWITH_DNF5DAEMON_SERVER=OFF
-DWITH_DNF5DAEMON_CLIENT=OFF
-DWITH_ACL=OFF
-DWITH_MODULEMD=OFF
-DWITH_SYSTEMD=OFF
-DWITH_HTML=OFF
-DWITH_MAN=OFF
-DWITH_TRANSLATIONS=OFF
-DWITH_TESTS=OFF
-DWITH_DNF5DAEMON_TESTS=OFF
-DWITH_SANITIZERS=OFF
-DWITH_PERL5=OFF
-DWITH_PYTHON3=OFF
-DWITH_RUBY=OFF
-DWITH_GO=OFF
-DWITH_DNF5_OBSOLETES_DNF=OFF
-DWITH_PYTHON_PLUGINS_LOADER=OFF
-DWITH_PLUGIN_APPSTREAM=OFF
-DWITH_PLUGIN_EXPIRED_PGP_KEYS=OFF
-DWITH_PLUGIN_RHSM=OFF
-DWITH_PLUGIN_MANIFEST=OFF
-DWITH_COMPS=ON
"
TERMUX_PKG_CONFFILES="etc/dnf/dnf.conf etc/yum.repos.d/termux.repo"

# toml11 es header-only y no existe como paquete termux. dnf5 hace
# find_package(toml11 REQUIRED) y usa #include <toml.hpp> sin enlazar un
# target (en Fedora los headers viven en /usr/include, en la ruta por
# defecto del compilador). Lo descargamos a $TERMUX_PKG_TMPDIR y generamos
# un config minimal para config-mode, con include_directories() apuntando
# al include extraido (replica el comportamiento de Fedora).
# Tambien aplica el overlay 0002 (.diff): el parche 0002-termux-paths-
# config-main no aplica limpio contra 5.4.2.1, y como es preferente (rutas
# FHS -> $PREFIX) se aplica aqui con fallo no fatal (|| true).
termux_step_post_get_source() {
	local TOML11_VERSION=4.3.0
	local toml11_src="$TERMUX_PKG_TMPDIR/toml11-${TOML11_VERSION}"
	local toml11_cfg="$TERMUX_PKG_TMPDIR/toml11"

	curl -L "https://github.com/ToruNiina/toml11/archive/refs/tags/v${TOML11_VERSION}.tar.gz" -o "$TERMUX_PKG_TMPDIR/toml11.tar.gz"
	tar -xzf "$TERMUX_PKG_TMPDIR/toml11.tar.gz" -C "$TERMUX_PKG_TMPDIR"
	rm -f "$TERMUX_PKG_TMPDIR/toml11.tar.gz"

	mkdir -p "$toml11_cfg"
	cat > "$toml11_cfg/toml11Config.cmake" <<-EOF
		add_library(toml11::toml11 INTERFACE IMPORTED)
		set_target_properties(toml11::toml11 PROPERTIES
			INTERFACE_INCLUDE_DIRECTORIES "${toml11_src}/include")
		include_directories("${toml11_src}/include")
	EOF
	cat > "$toml11_cfg/toml11ConfigVersion.cmake" <<-EOF
		set(PACKAGE_VERSION "${TOML11_VERSION}")
		if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)
			set(PACKAGE_VERSION_COMPATIBLE FALSE)
		else()
			set(PACKAGE_VERSION_COMPATIBLE TRUE)
			if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
				set(PACKAGE_VERSION_EXACT TRUE)
			endif()
		endif()
	EOF

	patch --forward --batch -p1 < "$TERMUX_PKG_BUILDER_DIR/0002-termux-paths-config-main.diff" || true
}

# En pre_configure todas las variables del framework ya estan definidas
# (TERMUX_PKG_EXTRA_CONFIGURE_ARGS se evalua en termux_step_configure_cmake,
# no al sourcear build.sh), asi que aqui se anade la ruta de toml11.
# libandroid-glob provee glob()/globfree() (ausentes en bionic). El framework
# cmake de termux-packages NO propaga $LDFLAGS a los targets cmake (solo a
# -DCMAKE_LINKER), por eso ademas del LDFLAGS se pasan explicitos los flags
# de enlazado para libs compartidas y ejecutables (libdnf5.so era el que
# arrastraba los symbols undefined glob/globfree).
termux_step_pre_configure() {
	LDFLAGS+=" -landroid-glob"
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" -Dtoml11_DIR=${TERMUX_PKG_TMPDIR}/toml11"
	# -landroid-glob rompe el try-compile de CMake (reemplaza los -L del framework).
	# Enlazar por ruta absoluta del .so: no depende de -L y conserva las flags default.
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" -DCMAKE_EXE_LINKER_FLAGS=${TERMUX_PREFIX}/lib/libandroid-glob.so -DCMAKE_SHARED_LINKER_FLAGS=${TERMUX_PREFIX}/lib/libandroid-glob.so"
}

# Los confiles se escriben en el MASSAGEDIR (el framework empaqueta desde
# ahi via make install DESTDIR=$TERMUX_PKG_MASSAGEDIR); si se escribieran en
# $TERMUX_PREFIX directo no entrarian en el .deb.
termux_step_post_make_install() {
	mkdir -p "$TERMUX_PKG_MASSAGEDIR$TERMUX_PREFIX/etc/dnf" \
		"$TERMUX_PKG_MASSAGEDIR$TERMUX_PREFIX/etc/yum.repos.d"

	cat > "$TERMUX_PKG_MASSAGEDIR$TERMUX_PREFIX/etc/dnf/dnf.conf" <<-EOF
		# dnf.conf - Configuración de DNF para Termux
		[main]
		gpgcheck=True
		installonly_limit=3
		clean_requirements_on_remove=True
		best=False
		skip_if_unavailable=True

		# Termux-specific paths
		cachedir=$TERMUX_PREFIX/var/cache/dnf
		pluginconfpath=$TERMUX_PREFIX/etc/dnf/plugins
		persistdir=$TERMUX_PREFIX/var/lib/dnf
		system_state_dir=$TERMUX_PREFIX/var/lib/dnf
		transaction_lock=$TERMUX_PREFIX/var/lib/dnf/lock
		varsdir=$TERMUX_PREFIX/etc/dnf/vars

		# Repositories
		reposdir=$TERMUX_PREFIX/etc/yum.repos.d
		vendor_conf_dir=$TERMUX_PREFIX/etc/yum.repos.d
	EOF

	cat > "$TERMUX_PKG_MASSAGEDIR$TERMUX_PREFIX/etc/yum.repos.d/termux.repo" <<-EOF
		# termux.repo - Repositorio base Termux para DNF
		[termux]
		name=Termux RPM Repository
		baseurl=https://packages.termux.dev/rpm/
		enabled=1
		gpgcheck=1
		repo_gpgcheck=0
		gpgkey=https://packages.termux.dev/rpm/termux-rpm.gpg
	EOF
}
