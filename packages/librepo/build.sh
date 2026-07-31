TERMUX_PKG_HOMEPAGE=https://github.com/rpm-software-management/librepo
TERMUX_PKG_DESCRIPTION="Library providing C and Python (libcURL like) API for downloading Linux repository metadata and packages"
TERMUX_PKG_LICENSE="LGPL-2.1-or-later"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.20.0
TERMUX_PKG_SRCURL=https://github.com/rpm-software-management/librepo/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=c21dd3caefe97ea58bc865f92095a9d2db2ec8aab49d0c714d4742094db930b6
TERMUX_PKG_DEPENDS="libcurl, glib, openssl, libxml2, zchunk, gpgme, rpm"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="-DENABLE_DOCS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF -DENABLE_PYTHON=OFF -DWITH_ZCHUNK=ON -DUSE_GPGME=ON -DENABLE_SELINUX=OFF"

# Deps derivadas del CMakeLists.txt de la raiz (librepo 1.20.0):
#   REQUIRED: glib-2.0/gio-2.0 (glib), libcrypto (openssl), libxml-2.0 (libxml2),
#             CURL>=7.52.0 (libcurl).
#   WITH_ZCHUNK=ON -> zck>=0.9.11 (zchunk, paquete local de este repo, overlay en CI).
#   USE_GPGME=ON   -> gpgme (gpg_gpgme.c). rpm se declara como dep por instruccion
#                     explicita (headers rpm/rpmpgp.h de gpg_rpm.c, solo usado si
#                     USE_GPGME=OFF); ya esta probado como dep -I en libsolv.
#   NO usa zstd ni libexpat: el source no los referencia (XML via libxml2).
#   ENABLE_SELINUX=OFF evita el REQUIRED de libselinux (USE_GPGME AND ENABLE_SELINUX).
#   ENABLE_TESTS/ENABLE_DOCS/ENABLE_EXAMPLES/ENABLE_PYTHON=OFF evitan deps de build
#   innecesarias (check, python dev, etc.).
# CMakeLists.txt en la RAIZ: no hace falta termux_step_configure custom
# (a diferencia de libcomps). Los patches 0001 y 0003 los auto-aplica el
# framework (patron *.patch).
