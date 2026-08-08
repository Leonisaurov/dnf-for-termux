#!/usr/bin/env bash
# uninstall-dnf-termux.sh — desinstala el stack dnf5 de Termux. Espejo del
# instalador (scripts/install-dnf-termux.sh): elimina los 8 paquetes pacman que
# instala (dnf5, rpm, libpopt, libsolv, librepo, libcomps, zchunk,
# createrepo-c), la config/runtime de dnf5/libdnf5 (incluido el staging del
# instalador $HOME/.cache/dnf-termux-install y la caché de metadata
# $PREFIX/var/cache/dnf), la rpmdb (con backup en $TMPDIR) y la clave GPG de
# prueba del ring de ~/.gnupg.
#
# CONSERVA por defecto:
#   $HOME/dnf-gpg                     → clave de firma del repo
#   $HOME/dnf-repo, dnf-repo-remote, dnf-pkgs*, dnf-rpms, dnf-artifacts
#                                     → stagings de descarga/build
#
# Uso:
#   uninstall-dnf-termux.sh [--purge] [--help]
#
# Sin flags:
#   desinstala los 8 paquetes con `pacman -Rdd --noconfirm` (solo los que están
#   instalados, detectados con `pacman -Q`), elimina config/runtime, hace backup
#   de la rpmdb y la elimina, y borra la clave GPG de prueba de ~/.gnupg.
#
# --purge: además elimina $HOME/dnf-gpg y los stagings de build.
# --help:  muestra esta ayuda.
set -euo pipefail

# Los 8 paquetes del stack instalados por install-dnf-termux.sh (matrix de
# build.yml: zchunk, libcomps, libsolv, librepo, rpm, libpopt, createrepo-c,
# dnf5).
PKGS=(dnf5 rpm libpopt libsolv librepo libcomps zchunk createrepo-c)

usage() {
  cat <<'EOF'
Uso: uninstall-dnf-termux.sh [--purge] [--help]

Desinstala el stack dnf5 de Termux (espejo de install-dnf-termux.sh).

Sin flags:
    Desinstala los 8 paquetes pacman (dnf5, rpm, libpopt, libsolv, librepo,
    libcomps, zchunk, createrepo-c) con:  pacman -Rdd --noconfirm
    (solo los instalados; el resto se omite).
    Elimina config/runtime de dnf5/libdnf5 (incluido el staging del instalador
    $HOME/.cache/dnf-termux-install y la caché de metadata $PREFIX/var/cache/dnf),
    la rpmdb (con backup en $TMPDIR) y la clave GPG de prueba de ~/.gnupg.
    CONSERVA $HOME/dnf-gpg (clave de firma del repo) y los stagings de build
    ($HOME/dnf-repo, dnf-repo-remote, dnf-pkgs*, dnf-rpms, dnf-artifacts).

--purge:
    Además elimina $HOME/dnf-gpg y los stagings de build:
        $HOME/dnf-repo
        $HOME/dnf-repo-remote
        $HOME/dnf-pkgs*
        $HOME/dnf-rpms
        $HOME/dnf-artifacts

--help:
    Muestra esta ayuda.

Ejemplos:
    uninstall-dnf-termux.sh
    uninstall-dnf-termux.sh --purge
EOF
}

# Verifica que estamos en Termux y que pacman está disponible (misma validación
# que el instalador).
check_env() {
  if [ -z "${PREFIX:-}" ] || [ ! -d "${PREFIX}" ]; then
    echo "error: esto solo funciona dentro de Termux (no hay \$PREFIX)" >&2
    exit 1
  fi
  if ! command -v pacman >/dev/null 2>&1; then
    echo "error: no se encontró 'pacman'. Instala termux-pacman primero." >&2
    exit 1
  fi
}

# Desinstala los 8 paquetes con pacman -Rdd --noconfirm. Solo procesa los que
# están instalados (detectados con pacman -Q); el resto se omite.
remove_pkgs() {
  local -a installed=()
  local pkg
  for pkg in "${PKGS[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      installed+=("$pkg")
    else
      echo "  (no instalado, se omite) $pkg"
    fi
  done
  if [ "${#installed[@]}" -gt 0 ]; then
    echo "Desinstalando: ${installed[*]}"
    pacman -Rdd --noconfirm "${installed[@]}"
  else
    echo "Ninguno de los 8 paquetes está instalado; se omite pacman -Rdd."
  fi
}

# Elimina config/runtime de dnf5/libdnf5 (solo lo que exista):
#   $PREFIX/etc/yum.repos.d, $PREFIX/etc/dnf, $PREFIX/var/lib/dnf,
#   $PREFIX/var/cache/dnf (caché de metadata de dnf5),
#   $HOME/.cache/dnf-termux-install (staging del instalador, se elimina siempre),
#   $HOME/.cache/libdnf5, $HOME/.local/state/dnf5.log
remove_config_runtime() {
  local -a dirs=(
    "$PREFIX/etc/yum.repos.d"
    "$PREFIX/etc/dnf"
    "$PREFIX/var/lib/dnf"
    "$PREFIX/var/cache/dnf"
    "$HOME/.cache/dnf-termux-install"
    "$HOME/.cache/libdnf5"
  )
  local d
  for d in "${dirs[@]}"; do
    if [ -e "$d" ]; then
      rm -rf "$d"
      echo "  eliminado: $d"
    fi
  done
  if [ -f "$HOME/.local/state/dnf5.log" ]; then
    rm -f "$HOME/.local/state/dnf5.log"
    echo "  eliminado: $HOME/.local/state/dnf5.log"
  fi
}

# Backup de la rpmdb en $TMPDIR y eliminación del original.
backup_remove_rpmdb() {
  if [ -d "$PREFIX/var/lib/rpm" ]; then
    local backup="$TMPDIR/rpmdb-backup-uninstall-$(date +%s)"
    cp -a "$PREFIX/var/lib/rpm" "$backup"
    echo "  rpmdb respaldada en: $backup"
    rm -rf "$PREFIX/var/lib/rpm"
    echo "  rpmdb eliminada: $PREFIX/var/lib/rpm"
  else
    echo "  no hay rpmdb en $PREFIX/var/lib/rpm; nada que respaldar."
  fi
}

# Elimina la clave GPG de prueba del ring de ~/.gnupg (no falla si no existe).
remove_gpg_key() {
  gpg --batch --yes --delete-keys 228A7E23748A40F925E7DEECFAAA6809B0971ADC 2>/dev/null || true
  echo "  clave GPG de prueba eliminada (si existía)"
}

# --purge: elimina $HOME/dnf-gpg y los stagings de build. El staging del
# instalador $HOME/.cache/dnf-termux-install ya se eliminó siempre en
# remove_config_runtime.
purge_stagings() {
  local -a paths=(
    "$HOME/dnf-gpg"
    "$HOME/dnf-repo"
    "$HOME/dnf-repo-remote"
    "$HOME/dnf-rpms"
    "$HOME/dnf-artifacts"
  )
  local p
  for p in "${paths[@]}"; do
    if [ -e "$p" ]; then
      rm -rf "$p"
      echo "  (purge) eliminado: $p"
    fi
  done
  # dnf-pkgs* (glob; puede coincidir con 0 o varios directorios).
  local g
  for g in "$HOME"/dnf-pkgs*; do
    if [ -e "$g" ]; then
      rm -rf "$g"
      echo "  (purge) eliminado: $g"
    fi
  done
}

# Verificación final: ninguno de los 8 paquetes debe seguir instalado.
verify() {
  echo ""
  echo "=== Verificación ==="
  local -a left=()
  local pkg
  for pkg in "${PKGS[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      left+=("$pkg")
    fi
  done
  if [ "${#left[@]}" -eq 0 ]; then
    echo "OK: los 8 paquetes del stack dnf5 están desinstalados."
  else
    echo "ADVERTENCIA: siguen instalados: ${left[*]}" >&2
    exit 1
  fi
}

main() {
  local PURGE=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help | -h) usage; exit 0 ;;
      --purge) PURGE=1; shift ;;
      -*)
        echo "error: opción desconocida: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        echo "error: argumento no esperado: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  check_env

  echo "=== Desinstalando stack dnf5 ==="
  remove_pkgs
  echo ""
  echo "=== Eliminando config/runtime ==="
  remove_config_runtime
  echo ""
  echo "=== rpmdb ==="
  backup_remove_rpmdb
  echo ""
  echo "=== Clave GPG de prueba ==="
  remove_gpg_key

  if [ "$PURGE" -eq 1 ]; then
    echo ""
    echo "=== Purge: clave de firma del repo y stagings ==="
    purge_stagings
  else
    echo ""
    echo "Nota: se conservan \$HOME/dnf-gpg y los stagings de build (usa --purge para eliminarlos)."
  fi

  verify
}

main "$@"
