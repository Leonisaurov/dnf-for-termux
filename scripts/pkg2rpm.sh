#!/usr/bin/env bash
# pkg2rpm.sh — convierte un paquete pacman de Termux (.pkg.tar.xz) a un .rpm aarch64.
#
# Uso: pkg2rpm.sh <archivo.pkg.tar.xz> [dir_salida]
#
# El .rpm resultante NO declara dependencias (AutoReqProv: no) y solo reempaqueta
# el contenido del .pkg tal cual: es una conversión de formato, no una
# recompilación ni una resolución de deps.
#
# Flujo:
#   1. Extrae el .pkg a un staging (bsdtar/tar).
#   2. Lee .PKGINFO (bsdtar -xOf): pkgname, pkgver, arch, pkgdesc, license.
#      pkgver "5.4.2.1-1" -> Version="5.4.2.1", Release="1" (se separa por el
#      ÚLTIMO guion).
#   3. Genera un spec: Name, Version, Release, Summary, License, BuildArch
#      aarch64, AutoReqProv no, %global __os_install_post %{nil}; %install copia
#      data/data/com.termux/files/usr/. a %{buildroot}; %files con TODAS las
#      rutas absolutas (find) y %defattr.
#   4. rpmbuild -bb --define "_topdir $STAGING/rpmbuild" <spec> y copia el .rpm
#      (RPMS/aarch64/) al dir_salida con nombre <name>-<version>-<release>.aarch64.rpm.
set -euo pipefail

PKG="${1:?uso: pkg2rpm.sh <archivo.pkg.tar.xz> [dir_salida]}"
OUTDIR="${2:-$PWD}"

if [ ! -f "$PKG" ]; then
  echo "error: no existe el archivo '$PKG'" >&2
  exit 1
fi

# --- staging (bajo $TMPDIR; nunca /tmp en Termux; fallback para runners) ---
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/pkg2rpm.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ROOT="$STAGING/rootfs"
TOPDIR="$STAGING/rpmbuild"
mkdir -p "$ROOT"
mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# --- 1. extraer el .pkg al staging ---
if command -v bsdtar >/dev/null 2>&1; then
  bsdtar -xf "$PKG" -C "$ROOT"
else
  tar -xf "$PKG" -C "$ROOT"
fi
if [ ! -d "$ROOT/data/data/com.termux/files/usr" ]; then
  echo "error: el .pkg no tiene el layout de Termux (data/data/com.termux/files/usr)" >&2
  exit 1
fi

# --- 2. leer .PKGINFO ---
PKGINFO="$(bsdtar -xOf "$PKG" .PKGINFO 2>/dev/null || cat "$ROOT/.PKGINFO")"
# field <clave>: valor de "clave = valor" en .PKGINFO
field() {
  printf '%s\n' "$PKGINFO" | awk -F' = ' -v k="$1" '$1==k {print $2; exit}'
}

NAME="$(field pkgname)"
PKGVER="$(field pkgver)"
ARCH="$(field arch)"
SUMMARY="$(field pkgdesc)"
LICENSE="$(field license)"

if [ -z "$NAME" ] || [ -z "$PKGVER" ]; then
  echo "error: .PKGINFO incompleto (pkgname o pkgver vacíos)" >&2
  exit 1
fi

# Separar pkgver en Version/Release por el ÚLTIMO guion:
#   "5.4.2.1-1"  -> Version="5.4.2.1",  Release="1"
#   "5.1.107.87" -> Version="5.1.107.87", Release="1" (sin guion: fallback)
if [[ "$PKGVER" == *-* ]]; then
  VERSION="${PKGVER%-*}"
  RELEASE="${PKGVER##*-}"
else
  VERSION="$PKGVER"
  RELEASE="1"
fi

[ -n "$ARCH" ] || ARCH="aarch64"

# --- 3. generar el spec ---
SPEC="$TOPDIR/SPECS/$NAME.spec"
SRC_DIR="$ROOT/data/data/com.termux/files/usr"
# TODAS las rutas absolutas (con '/' inicial) para %files: ficheros y symlinks.
# Las líneas que empiezan con '%' en el listado se escapan ('%%') para que rpm
# no las trate como directivas.
FILES="$(cd "$ROOT" && find "data/data/com.termux/files/usr" -mindepth 1 \( -type f -o -type l \) | sort | sed 's#^#/#' | sed 's#^/%#/%%#')"

cat > "$SPEC" <<EOF
# Generado por pkg2rpm.sh a partir de: $(basename "$PKG")
Name:           $NAME
Version:        $VERSION
Release:        $RELEASE
Summary:        $SUMMARY
License:        $LICENSE
BuildArch:      $ARCH
AutoReqProv:    no
%global __os_install_post %{nil}

%description
$SUMMARY
(convertido desde pacman/Arch Linux para Termux; sin Requires RPM.)

%install
mkdir -p %{buildroot}/data/data/com.termux/files/usr
cp -a $SRC_DIR/. %{buildroot}/data/data/com.termux/files/usr/

%files
%defattr(-,root,root)
$FILES
EOF

echo "spec generado: $SPEC"

# --- 4. build con rpmbuild (--target: el runner es x86_64 pero el rpm es aarch64) ---
rpmbuild -bb --target "$ARCH" --define "_topdir $TOPDIR" "$SPEC"

# --- copiar el .rpm al dir_salida con nombre <name>-<version>-<release>.<arch>.rpm ---
RPM="$(find "$TOPDIR/RPMS" -name '*.rpm' | head -1)"
if [ -z "$RPM" ]; then
  echo "error: no se generó ningún .rpm en $TOPDIR/RPMS" >&2
  exit 1
fi
mkdir -p "$OUTDIR"
OUTNAME="$NAME-$VERSION-$RELEASE.$ARCH.rpm"
cp "$RPM" "$OUTDIR/$OUTNAME"
echo "OK: $OUTDIR/$OUTNAME"
