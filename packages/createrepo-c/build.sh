TERMUX_PKG_HOMEPAGE=https://github.com/rpm-software-management/createrepo_c
TERMUX_PKG_DESCRIPTION="A C implementation of the createrepo tool for generating RPM repository metadata"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_LICENSE_FILE="COPYING"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.2.4
TERMUX_PKG_SRCURL=https://github.com/rpm-software-management/createrepo_c/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=4c980c2b5938694d36ab3117eb286b9ffa7187c768ac66e7805662a3dd22edf1
# Deps derivadas del CMakeLists.txt de la raiz (createrepo_c 1.2.4):
#   REQUIRED incondicionales: BZip2 (libbz2), CURL (libcurl), LibXml2 (libxml2),
#             OpenSSL (openssl), ZLIB (zlib), glib-2.0/gio-2.0/gthread-2.0 (glib),
#             liblzma (liblzma), sqlite3>=3.6.18 (libsqlite), rpm, libzstd (zstd).
#   WITH_ZCHUNK=ON -> zck>=0.9.11 (zchunk, paquete local de este repo, overlay en CI).
#   NO usa libsolv, libarchive, libmagic, json-c ni util-linux (grep del source vacio).
TERMUX_PKG_DEPENDS="libbz2, libcurl, libxml2, openssl, zlib, glib, liblzma, libsqlite, rpm, zstd, zchunk"
# Flags cmake validados contra el CMakeLists.txt del tag 1.2.4:
#   WITH_LIBMODULEMD (default ON, CMakeLists.txt:97) -> OFF: evita portar libmodulemd.
#   ENABLE_DRPM (default OFF, CMakeLists.txt:74): OFF explicito, sin delta RPM.
#   ENABLE_PYTHON (default ON, CMakeLists.txt:87) -> OFF: sin bindings de python.
#   WITH_ZCHUNK (default ON, CMakeLists.txt:89): ON, con zchunk.
#   La "C interface" (libcreaterepo_c.so + headers + createrepo_c.pc) la controlan
#   BUILD_LIBCREATEREPO_C_SHARED (CMakeLists.txt:19) y CREATEREPO_C_INSTALL_DEVELOPMENT
#   (CMakeLists.txt:24), ambos ON por defecto; NO existe flag ENABLE_C_INTERFACE.
#   BUILD_DOC_C (ON por defecto, doc/CMakeLists.txt) -> OFF: find_package(Doxygen
#   REQUIRED) en configure romperia la build sin doxygen.
#   ENABLE_BASHCOMP (default ON, CMakeLists.txt:135) -> OFF: sin bash-completion
#   (el fallback del CMakeLists instalaria bajo /etc/bash_completion.d).
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DBUILD_LIBCREATEREPO_C_SHARED=ON
-DCREATEREPO_C_INSTALL_DEVELOPMENT=ON
-DENABLE_BASHCOMP=OFF
-DENABLE_DRPM=OFF
-DENABLE_PYTHON=OFF
-DWITH_ZCHUNK=ON
-DWITH_LIBMODULEMD=OFF
-DBUILD_DOC_C=OFF
"
