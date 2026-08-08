#!/usr/bin/env bash
# install-dnf-termux.sh — bootstrap del stack dnf5 en Termux a partir de los
# artifacts del CI de Leonisaurov/dnf-for-termux (workflow build.yml).
#
# El CI compila cada paquete con el sistema termux-packages en formato pacman
# (.pkg.tar.xz) y sube un artifact "<paquete>-aarch64" (zip con el .pkg dentro).
# Este script:
#   1. localiza el último run EXITOSO de build.yml en main (vía gh)
#   2. descarga los 8 artifacts a un staging (gh run download)
#   3. instala los .pkg con `pacman -U --needed` (libpopt primero, dnf5 último)
#   4. verifica con `dnf5 --version`
#
# Uso:
#   install-dnf-termux.sh [opciones] [dir_con_pkgs]
#
# Opciones:
#   --assume-yes   pasa --noconfirm a pacman (no pregunta confirmaciones)
#   --help         muestra esta ayuda
#
# Sin argumentos   → descarga e instala el último build exitoso.
# Con un directorio → modo offline: instala los .pkg de ese directorio
#                      (p.ej. install-dnf-termux.sh ~/dnf-pkgs-new5/).
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
WORKFLOW="build.yml"          # workflow de CI que compila los paquetes
BRANCH="main"                 # rama del run a usar
# Artifacts subidos por la matrix de build.yml (uno por paquete).
ARTIFACTS=(dnf5-aarch64 rpm-aarch64 libpopt-aarch64 libsolv-aarch64 librepo-aarch64 libcomps-aarch64 zchunk-aarch64 createrepo-c-aarch64)
# Orden de instalación: libpopt antes que rpm (rpm depende de libpopt y el
# artifact es el PARCHADO del SIGSYS; si no, pacman bajaría el oficial 1.19-3
# sin parche del repo) y dnf5 último; el resto de dependencias en medio.
INSTALL_ORDER=(libpopt rpm libsolv librepo libcomps zchunk createrepo-c dnf5)
# Staging bajo $HOME/.cache para que los .pkg persistan entre reinicios y se
# puedan reinstalar en modo offline sin volver a descargar.
STAGING="${HOME}/.cache/dnf-termux-install"

ASSUME_YES=0
DIR=""

usage() {
  cat <<'EOF'
Uso: install-dnf-termux.sh [--assume-yes] [--help] [dir_con_pkgs]

Instala el stack dnf5 en Termux desde los artifacts del CI (formato pacman).

Sin argumentos:
    Descarga los 8 .pkg del último run exitoso de build.yml en main y los
    instala con: pacman -U --needed <paquetes>

Con un directorio:
    Modo offline: instala los .pkg.tar.* de ese directorio sin descargar nada.

Opciones:
    --assume-yes   pasa --noconfirm a pacman (no pregunta confirmaciones)
    --help         muestra esta ayuda

Ejemplos:
    install-dnf-termux.sh
    install-dnf-termux.sh --assume-yes
    install-dnf-termux.sh ~/dnf-pkgs-new5/
EOF
}

# Ordena una lista de .pkg (una por línea en stdin): libpopt primero (dep de
# rpm, parcheado contra SIGSYS), después rpm, dnf5 último y el resto en orden
# alfabético. Los nombres siguen el patrón pacman:
# <paquete>-<version>-aarch64.pkg.tar.xz
order_pkgs() {
  local -a pre=() mid=() later=()
  local p b
  while IFS= read -r p; do
    b="$(basename "$p")"
    case "$b" in
      libpopt-* | libpopt.*) pre+=( "$p" ) ;;              # libpopt al frente
      rpm-* | rpm.*) mid+=( "$p" ) ;;                      # rpm a continuación
      dnf5-* | dnf5.*) later+=( "$p" ) ;;                  # dnf5 al final
      *) mid+=( "$p" ) ;;
    esac
  done
  printf '%s\n' "${pre[@]}" "${mid[@]}" "${later[@]}"
}

# Valida el entorno: Termux, arquitectura aarch64 y pacman disponible.
check_env() {
  if [ -z "${PREFIX:-}" ] || [ ! -d "${PREFIX}" ]; then
    echo "error: esto solo funciona dentro de Termux (no hay \$PREFIX)" >&2
    exit 1
  fi
  if [ "$(uname -m)" != "aarch64" ]; then
    echo "error: los artifacts del CI son solo aarch64; arquitectura actual: $(uname -m)" >&2
    exit 1
  fi
  if ! command -v pacman >/dev/null 2>&1; then
    echo "error: no se encontró 'pacman'. Instala termux-pacman primero." >&2
    exit 1
  fi
}

# Descarga los 8 artifacts del último run exitoso de build.yml a $STAGING.
download_pkgs() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: 'gh' no está instalado (pkg install gh)." >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "error: 'gh' no está autenticado. Ejecuta 'gh auth login' primero." >&2
    exit 1
  fi

  local run_id
  run_id="$(gh run list --workflow="$WORKFLOW" --branch "$BRANCH" --status success --limit 1 --json databaseId -q '.[0].databaseId')"
  if [ -z "$run_id" ]; then
    echo "error: no hay runs exitosos de $WORKFLOW en la rama $BRANCH." >&2
    exit 1
  fi
  echo "Último run exitoso de $WORKFLOW ($BRANCH): $run_id"

  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  local art
  for art in "${ARTIFACTS[@]}"; do
    echo "  descargando artifact: $art"
    gh run download "$run_id" -n "$art" -D "$STAGING" \
      || { echo "error: falló la descarga de '$art' en el run $run_id" >&2; exit 1; }
  done
  echo "Artifacts descargados en: $STAGING"
}

main() {
  # --- parseo de argumentos ---
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help | -h) usage; exit 0 ;;
      --assume-yes | -y) ASSUME_YES=1; shift ;;
      -*)
        echo "error: opción desconocida: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        [ -z "$DIR" ] || { echo "error: solo se admite un directorio de .pkg" >&2; exit 2; }
        DIR="$1"
        shift
        ;;
    esac
  done

  check_env

  # --- obtención de los .pkg (modo online u offline) ---
  local -a PKGS=()
  if [ -n "$DIR" ]; then
    echo "=== Modo offline: $DIR ==="
    [ -d "$DIR" ] || { echo "error: $DIR no es un directorio" >&2; exit 1; }
    mapfile -t PKGS < <(find "$DIR" -maxdepth 1 -type f -name '*.pkg.tar.*' | sort | order_pkgs)
  else
    echo "=== Modo online: descarga desde el CI ==="
    download_pkgs
    mapfile -t PKGS < <(find "$STAGING" -type f -name '*.pkg.tar.*' | sort | order_pkgs)
  fi

  if [ "${#PKGS[@]}" -eq 0 ]; then
    echo "error: no se encontró ningún .pkg.tar.*" >&2
    exit 1
  fi

  echo "Paquetes a instalar (${#PKGS[@]}):"
  printf '  %s\n' "${PKGS[@]}"

  # --- instalación con pacman ---
  local -a pacman_args=(-U --needed)
  [ "$ASSUME_YES" -eq 1 ] && pacman_args+=(--noconfirm)

  echo "=== Instalando con pacman ==="
  pacman "${pacman_args[@]}" "${PKGS[@]}"

  # --- verificación final ---
  echo ""
  echo "=== Verificación ==="
  if command -v dnf5 >/dev/null 2>&1 && dnf5 --version; then
    echo "OK: dnf5 instalado correctamente."
    echo "Sugerencia: ejecuta 'dnf5 repolist' para listar los repositorios."
  else
    echo "ERROR: 'dnf5 --version' falló; revisa la instalación de los .pkg." >&2
    exit 1
  fi
}

main "$@"
