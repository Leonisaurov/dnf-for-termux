#!/usr/bin/env bash
# ============================================================================
# generate-bootstrap-dnf5.sh — genera un bootstrap de Termux con dnf5 como
# gestor de paquetes nativo: un zip que la app Termux acepta como sistema base
# ($PREFIX = /data/data/com.termux/files/usr), con la rpmdb pre-poblada y todo
# el contenido instalado como RPMs.
#
# Flujo (14 pasos):
#   1.  Preparar dirs bajo $WORK y limpiar restos.
#   2.  Descargar main.json (índice termux-pacman) y resolver el set:
#       base (30) + deps runtime curadas (26) + cierre transitivo
#       (BFS sobre DEPENDS, fallback vía índice PROVIDES). Manifest.
#   3.  Descargar los .pkg.tar.xz por FILENAME, validando SHA256SUM.
#   4.  fix_any_arch_pkg() (arch=any → re-empaquetar con arch=aarch64) +
#       conversión a .rpm con scripts/pkg2rpm.sh + firma (siempre, M9).
#   5.  Descargar los 8 .rpm del proyecto desde gh-pages (grep anclado, M8).
#   6.  Poblar la rpmdb sqlite con rpm --root (cada comando con $SUDO).
#   7.  Verificar conffiles de dnf5 (termux.repo → gh-pages; dnf.conf).
#   8.  Limpieza de la rpmdb (wal/shm) + PRAGMA integrity_check (M2).
#   9.  Auditoría estática DT_NEEDED con readelf (C6; no se ejecutan los ELF).
#   10. SYMLINKS.txt (formato target←path) y borrado de symlinks.
#   11. Auditoría no apt/pacman/dpkg/makepkg en bin/ (m1).
#   12. Empaquetado zip (entries relativos a $PREFIX; excluye var/cache y tmp).
#   13. Verificaciones: unzip -l; rpm -qa en [90,200] + gpg-pubkey>=1; tamaño < 300MB; sha256.
#   14. Resumen final.
#
# Uso:
#   scripts/generate-bootstrap-dnf5.sh [opciones]
#
# Opciones:
#   --arch ARCH     arquitectura del target (default: aarch64)
#   --out DIR       dir de salida del zip (default: bootstrap-out/)
#   --work DIR      dir de trabajo (default: ${TMPDIR:-$HOME/tmp}/bootstrap-work)
#   --sign-key PATH ruta a la clave pública termux-rpm.gpg para importar en la
#                   rpmdb local ($HOME/rpmdb) y poder verificar rpm -K. Si se
#                   omite, se espera que la clave YA esté importada en $HOME/rpmdb.
#   --help          muestra esta ayuda
#
# Entorno (env):
#   SUDO            "" por defecto; en CI pasar "sudo" (passwordless en runners)
#   REPO_URL        índice termux-pacman (default https://sync.termux-pacman.dev/main/aarch64/)
#   PROJECT_RPM_URL repo RPM del proyecto (default https://leonisaurov.github.io/dnf-for-termux/rpm/)
#   TMPDIR          dir temporal (nunca /tmp en Termux; fallback en runners)
#
# Dependencias (runner Ubuntu 24.04 — rpm 4.18.2, esquema sqlite compatible con
# el rpm del dispositivo 4.18.1-4; M6):
#   jq curl zip unzip rpm rpmbuild sudo sqlite3 binutils(readelf) gpg bsdtar
#   (bsdtar o tar para .pkg.tar.xz; bsdtar -J re-empaqueta arch=any sin xz externo)
#
# Estilo: $TMPDIR nunca /tmp en Termux; mensajes en español; set -euo pipefail.
# ============================================================================
set -euo pipefail

# --- config -----------------------------------------------------------------
ARCH="aarch64"
OUT_DIR="bootstrap-out"
WORK=""
SIGN_KEY=""

REPO_URL="${REPO_URL:-https://sync.termux-pacman.dev/main/aarch64/}"
PROJECT_RPM_URL="${PROJECT_RPM_URL:-https://leonisaurov.github.io/dnf-for-termux/rpm/}"
SUDO="${SUDO:-}"

# Clave pública del repo dnf-for-termux (fingerprint fijo, m5).
GPG_KEY_FINGERPRINT="E4AC7735BD60196E19123DB6247EEE5F6AA25EC9"
GPG_KEY_NAME="dnf-for-termux"

# Set base = bootstrap de termux-pacman menos pacman/termux-keyring (M4):
# 30 paquetes. termux-keyring EXCLUIDO a propósito: el keyring de dnf5 es la
# clave pública importada en la rpmdb + gpgkey del repo (no la de pacman).
BASE_PKGS=(
  bash bzip2 command-not-found coreutils curl dash diffutils findutils gawk
  grep gzip less procps psmisc sed tar termux-core termux-exec termux-tools
  util-linux xz-utils ed dos2unix inetutils lsof nano net-tools patch unzip
  termux-am
)

# Deps runtime curadas del stack dnf5 (extraídas de packages/*/build.sh).
CURATED_DEPS=(
  libsqlite json-c fmt glib libxml2 zstd liblzma openssl zlib libsmartcols
  libandroid-glob file libandroid-spawn libarchive libbz2 libgcrypt libiconv
  lua54 readline libc++ ca-certificates gettext libcurl gpgme libexpat gnupg
)

# Stack del proyecto (8): vienen como .rpm YA firmados de gh-pages, NO de
# termux-pacman. dnf-hello se EXCLUYE del bootstrap.
PROJECT_STACK=(dnf5 rpm libpopt libsolv librepo libcomps zchunk createrepo-c)

# Librerías del sistema Android (bionic) + linkers que residen en el dispositivo y
# NO en $PREFIX/lib: un DT_NEEDED contra ellas es correcto (C6), no un MISS.
BIONIC_LIBS=(libc.so libdl.so libm.so liblog.so libandroid.so libjnigraphics.so linker64 ld-android.so)

# Ruta ABSOLUTA de la rpmdb DENTRO del rootfs: rpm >= 4.18 rechaza --dbpath
# relativo ("arguments to --dbpath must begin with '/'") y une el absoluto a
# --root, con lo que en disco queda $ROOTFS/data/data/... (idéntico al layout
# anterior relativo). El dispositivo la verá en $PREFIX/var/lib/rpm.
DBREL="/data/data/com.termux/files/usr/var/lib/rpm"

# --- helpers ----------------------------------------------------------------
log()  { printf '== %s\n' "$*" >&2; }
warn() { printf '!! AVISO: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Uso: generate-bootstrap-dnf5.sh [opciones]

Genera un bootstrap de Termux con dnf5 como gestor nativo (zip + rpmdb pre-poblada).

Opciones:
  --arch ARCH     arquitectura del target (default: aarch64)
  --out DIR       dir de salida del zip (default: bootstrap-out/)
  --work DIR      dir de trabajo (default: ${TMPDIR:-$HOME/tmp}/bootstrap-work)
  --sign-key PATH ruta a la clave pública termux-rpm.gpg (importa en $HOME/rpmdb);
                  si se omite, se espera que ya esté importada en $HOME/rpmdb
  --help          muestra esta ayuda

Entorno:
  SUDO            en CI usar "sudo"; local sin root, vacío
  REPO_URL        índice termux-pacman (default .../main/aarch64/)
  PROJECT_RPM_URL repo RPM del proyecto (default .../dnf-for-termux/rpm/)

Ejemplos:
  # CI (runner con sudo; clave importada vía el secret RPM_SIGNING_KEY)
  SUDO=sudo ./scripts/generate-bootstrap-dnf5.sh --out bootstrap-out/
  # Local (Termux) con la clave pública exportada del repo
  ./scripts/generate-bootstrap-dnf5.sh --sign-key ~/termux-rpm.gpg
EOF
}

# require <cmd> [cmd...]: falla si falta alguna herramienta.
require() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 \
      || die "falta la herramienta '$c'. Instálala antes de generar el bootstrap."
  done
}

# parse_args: flags y validación.
parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --arch)        ARCH="${2:?--arch necesita un valor}"; shift 2 ;;
      --out)         OUT_DIR="${2:?--out necesita un valor}"; shift 2 ;;
      --work)        WORK="${2:?--work necesita un valor}"; shift 2 ;;
      --sign-key)    SIGN_KEY="${2:?--sign-key necesita un valor}"; shift 2 ;;
      --help | -h)   usage; exit 0 ;;
      *) die "opción desconocida: $1 (usa --help)" ;;
    esac
  done
  [ "$ARCH" = "aarch64" ] || die "solo se soporta --arch aarch64 (se pidió '$ARCH')"
  [ -n "$WORK" ] || WORK="${TMPDIR:-$HOME/tmp}/bootstrap-work"
  mkdir -p "$OUT_DIR"
  # Absolutizar tras mkdir (C6): con --out relativo, zipfile="$OUT_DIR/bootstrap-..."
  # se escribía DENTRO de $USR y unzip/stat fallaban después.
  OUT_DIR="$(cd "$OUT_DIR" && pwd)"
}

# in_project_stack <name>: 0 si el nombre pertenece al stack de gh-pages.
in_project_stack() {
  local n
  for n in "${PROJECT_STACK[@]}"; do
    [ "$n" = "$1" ] && return 0
  done
  return 1
}

# in_bionic_libs <lib>: 0 si la librería es del sistema Android (bionic) y vive
# en el dispositivo, no en $PREFIX/lib (C6; DT_NEEDED contra ella es correcto).
in_bionic_libs() {
  local l
  for l in "${BIONIC_LIBS[@]}"; do
    [ "$l" = "$1" ] && return 0
  done
  return 1
}

# dep_name <dep>: quita el operador de versión ("readline>=8.3-0" → "readline").
dep_name() {
  local d="$1"
  d="${d//[<>=]*}"
  d="${d#"${d%%[![:space:]]*}"}"   # trim izquierda
  d="${d%"${d##*[![:space:]]}"}"   # trim derecha
  printf '%s\n' "$d"
}

# lookup_provide <name>: resuelve un dep vía índice provides→paquete (C5).
lookup_provide() {
  local name="$1"
  awk -F '\t' -v n="$name" '$2==n {print $1; exit}' "$WORK/provides-index.txt" 2>/dev/null || true
}

# pkg_arch <pkg.tar.xz>: lee el campo arch del .PKGINFO.
pkg_arch() {
  local src="$1"
  bsdtar -xOf "$src" .PKGINFO 2>/dev/null \
    | awk -F' = ' '$1=="arch" {print $2; exit}'
}

# fix_any_arch_pkg <pkg.tar.xz>: si el .PKGINFO dice "arch = any", re-empaqueta
# una copia con el campo parcheado a "aarch64" (rpmbuild --target aarch64 falla
# con arch=any: "No compatible architectures found"). Imprime el path a usar.
fix_any_arch_pkg() {
  local src="$1" arch
  arch="$(pkg_arch "$src")"
  if [ "$arch" != "any" ]; then
    printf '%s\n' "$src"
    return 0
  fi
  log "  arch=any en $(basename "$src") → re-empaquetando con arch=aarch64"
  local tmp out
  tmp="$(mktemp -d "$WORK/fixany.XXXXXX")"
  out="$WORK/pkgs-fixed/$(basename "$src")"
  mkdir -p "$WORK/pkgs-fixed"
  ( cd "$tmp" && bsdtar -xf "$src" )
  sed -i 's/^arch = any$/arch = aarch64/' "$tmp/.PKGINFO"
  # Re-empaquetar en .pkg.tar.xz (bsdtar -J usa liblzma interna, sin xz externo).
  ( cd "$tmp" && bsdtar -cJf "$out" . )
  rm -rf "$tmp"
  printf '%s\n' "$out"
}

# --- PASO 1: preparar dirs ---------------------------------------------------
prepare_dirs() {
  log "PASO 1/14 — preparando directorios bajo $WORK"
  rm -rf "$WORK"
  mkdir -p \
    "$WORK"/pkgs "$WORK"/pkgs-fixed \
    "$WORK"/rpms "$WORK"/rpms-project \
    "$WORK"/rootfs/data/data/com.termux/files/usr \
    "$OUT_DIR"
  ROOTFS="$WORK/rootfs"
  USR="$ROOTFS/data/data/com.termux/files/usr"
  # dirs vacíos que dnf5 espera (la app ignora usr/tmp y usr/etc/termux/*.env*)
  mkdir -p "$USR"/var/lib/dnf "$USR"/var/cache/dnf "$USR"/var/lib/rpm \
           "$USR"/etc/dnf/vars "$USR"/tmp
  log "  ROOTFS=$ROOTFS"
  log "  USR=$USR"
}

# --- PASO 2: set de paquetes + cierre transitivo -----------------------------
resolve_package_set() {
  log "PASO 2/14 — resolviendo set de paquetes desde main.json"
  curl -fL "$REPO_URL/main.json" -o "$WORK/main.json" \
    || die "no se pudo descargar $REPO_URL/main.json"

  # Índice provides→paquete (fallback C5). PROVIDES puede ser string o array.
  jq -r '
    to_entries[]
    | .key as $pkg
    | (.value.PROVIDES // [])
    | if type == "array" then .[] else . end
    | split("[<>=]")[0]
    | gsub("^[ \t]+|[ \t]+$"; "")
    | select(. != "" and . != $pkg)
    | "\($pkg)\t\(.)"
  ' "$WORK/main.json" | sort -u > "$WORK/provides-index.txt"
  log "  índice provides: $(wc -l < "$WORK/provides-index.txt") entradas"

  # BFS sobre DEPENDS. Resolución: nombre exacto en main.json; si no, fallback
  # por el índice provides. Los nombres del stack del proyecto se ignoran (los
  # provee gh-pages). Las deps sin resolver son FATAL (assert 93/0).
  local -a queue=() unresolved=()
  local -A seen=() resolved=()
  local name resolved_name provider dep

  queue+=("${BASE_PKGS[@]}" "${CURATED_DEPS[@]}")

  while [ "${#queue[@]}" -gt 0 ]; do
    name="${queue[0]}"
    queue=("${queue[@]:1}")
    [ -n "$name" ] || continue
    [ -n "${seen[$name]:-}" ] && continue
    seen[$name]=1

    if in_project_stack "$name"; then
      log "  (dep del stack del proyecto ignorada: $name — viene de gh-pages)"
      continue
    fi

    resolved_name=""
    if jq -e --arg n "$name" 'has($n)' "$WORK/main.json" >/dev/null 2>&1; then
      resolved_name="$name"
    else
      provider="$(lookup_provide "$name")"
      if [ -n "$provider" ]; then
        resolved_name="$provider"
        log "  dep '$name' resuelta vía PROVIDES → $provider"
      fi
    fi

    if [ -n "$resolved_name" ]; then
      # M6: si la resolución vía PROVIDES cae en un paquete del stack del
      # proyecto (rpm, libsolv...), ignorarlo como en el check inicial (evita
      # duplicados; esos .rpm vienen de gh-pages).
      if in_project_stack "$resolved_name"; then
        log "  (dep del stack del proyecto ignorada tras resolver: $resolved_name — viene de gh-pages)"
        continue
      fi
      if [ -z "${resolved[$resolved_name]:-}" ]; then
        resolved[$resolved_name]=1
        # encolar sus DEPENDS (campo string o array en main.json)
        while IFS= read -r dep; do
          [ -n "$dep" ] || continue
          dep="$(dep_name "$dep")"
          if [ -z "${seen[$dep]:-}" ]; then
            queue+=("$dep")
          fi
        done < <(jq -r --arg n "$resolved_name" '(.[$n].DEPENDS // []) | if type == "array" then .[] else . end' "$WORK/main.json")
      fi
    else
      unresolved+=("$name")
    fi
  done

  if [ "${#unresolved[@]}" -gt 0 ]; then
    die "ASSERT: deps sin resolver (${#unresolved[@]}): ${unresolved[*]}"
  fi
  log "  set final de termux-pacman: ${#resolved[@]} paquetes"

  # Manifest (auditoría, CA-9): name|version|filename|sha256|origen
  : > "$WORK/manifest.txt"
  : > "$WORK/pkg-table.txt"
  local n v f s
  for n in $(printf '%s\n' "${!resolved[@]}" | sort); do
    v="$(jq -r --arg n "$n" '.[$n].VERSION // empty' "$WORK/main.json")"
    f="$(jq -r --arg n "$n" '.[$n].FILENAME // empty' "$WORK/main.json")"
    s="$(jq -r --arg n "$n" '.[$n].SHA256SUM // empty' "$WORK/main.json")"
    printf '%s|%s|%s|%s|termux-pacman\n' "$n" "$v" "$f" "$s" >> "$WORK/manifest.txt"
    printf '%s\t%s\t%s\n' "$n" "$f" "$s" >> "$WORK/pkg-table.txt"
  done
  log "  manifest escrito en $WORK/manifest.txt ($(wc -l < "$WORK/manifest.txt") líneas)"
}

# --- PASO 3: descarga de .pkg -------------------------------------------------
download_pkgs() {
  log "PASO 3/14 — descargando .pkg.tar.xz"
  local name filename sha ok=0 nowarn=0 n=0
  while IFS=$'\t' read -r name filename sha; do
    [ -n "$filename" ] || { warn "  $name sin FILENAME en main.json"; continue; }
    n=$((n+1))
    log "  [${n}] $name → $filename"
    curl -fL "$REPO_URL/$filename" -o "$WORK/pkgs/$filename" \
      || die "falló la descarga de $filename"
    if [ -n "$sha" ]; then
      if printf '%s  %s\n' "$sha" "$WORK/pkgs/$filename" | sha256sum -c - >/dev/null 2>&1; then
        ok=$((ok+1))
      else
        die "SHA256SUM no coincide para $filename"
      fi
    else
      warn "  $filename sin SHA256SUM en main.json — no se valida"
      nowarn=$((nowarn+1))
    fi
  done < "$WORK/pkg-table.txt"
  log "  descargados: $(ls "$WORK/pkgs" | wc -l) (sha256 verificados: $ok, sin checksum: $nowarn)"
}

# --- firma (paso 4, C4/M9) ---------------------------------------------------
sign_rpms() {
  log "  firmando RPMs convertidos (siempre; no existe --no-sign — M9)"
  # 1. clave privada en ~/.gnupg con el fingerprint fijo (m5)
  if ! gpg --batch --list-keys --with-colons "$GPG_KEY_FINGERPRINT" >/dev/null 2>&1; then
    die "falta la clave privada '$GPG_KEY_FINGERPRINT' en ~/.gnupg (impórtala: gpg --batch --import <clave.asc>)"
  fi
  # 2. macros de firma (patrón probado de deploy.yml, C4): %__gpg_sign_cmd en
  #    ~/.rpmmacros (escape %% en el printf para expansión DIFERIDA), gpg con
  #    ruta ABSOLUTA resuelta en runtime (rpm --addsign NO hereda el PATH del
  #    shell).
  local gpg_bin
  gpg_bin="$(command -v gpg)"
  printf '%%_gpg_name %s\n%%__gpg_sign_cmd %s --batch --no-tty --no-verbose --no-armor --output %%{__signature_filename} --detach-sign --local-user %%{_gpg_name} %%{__plaintext_filename}\n' "$GPG_KEY_NAME" "$gpg_bin" > "$HOME/.rpmmacros"
  # 3. clave pública en la rpmdb LOCAL ($HOME/rpmdb) ANTES de rpm -K (C4):
  #    rpm -K valida contra su propio keyring, no contra ~/.gnupg.
  #    --sign-key acepta un .gpg (se importa) o el propio $HOME/rpmdb (en CI la
  #    clave ya se importó antes con: gpg --export | rpm --import).
  if [ -n "$SIGN_KEY" ]; then
    if [ -f "$SIGN_KEY" ]; then
      mkdir -p "$HOME/rpmdb"
      rpm --define "_dbpath $HOME/rpmdb" --import "$SIGN_KEY"
      log "  clave pública importada en $HOME/rpmdb desde $SIGN_KEY"
    elif [ -d "$SIGN_KEY" ]; then
      log "  clave pública ya presente en la rpmdb $SIGN_KEY"
    else
      die "--sign-key: no existe $SIGN_KEY"
    fi
  elif [ ! -d "$HOME/rpmdb" ]; then
    die "no hay clave pública en $HOME/rpmdb y no se pasó --sign-key (pasa --sign-key <termux-rpm.gpg>)"
  fi
  # 4. firmar todos los convertidos
  rpm --addsign "$WORK/rpms/"*.rpm
  # 5. verificar con rpm -K (usa la rpmdb local)
  local total ok
  total="$(ls "$WORK/rpms/"*.rpm | wc -l)"
  ok="$(rpm -K --define "_dbpath $HOME/rpmdb" "$WORK/rpms/"*.rpm | grep -c 'signatures OK' || true)"
  [ "$ok" -eq "$total" ] || die "solo $ok/$total RPMs convertidos con 'signatures OK'"
  log "  OK: $ok/$total RPMs convertidos firmados y verificados"
}

# --- PASO 4: conversión .pkg → .rpm + firma -----------------------------------
convert_pkgs() {
  log "PASO 4/14 — conversión .pkg → .rpm (fix arch=any + pkg2rpm.sh) y firma"
  # ruta absoluta del convertidor (se invoca desde cualquier cwd)
  local pkg2rpm="$SCRIPT_DIR/scripts/pkg2rpm.sh"
  [ -f "$pkg2rpm" ] || die "no existe $pkg2rpm"
  local src fixed n=0
  for src in "$WORK/pkgs/"*.pkg.tar.xz; do
    [ -e "$src" ] || continue
    n=$((n+1))
    fixed="$(fix_any_arch_pkg "$src")"
    log "  [${n}] $(basename "$src")"
    bash "$pkg2rpm" "$fixed" "$WORK/rpms"
  done
  local npkg nrpm
  npkg="$(ls "$WORK/pkgs/"*.pkg.tar.xz | wc -l)"
  nrpm="$(ls "$WORK/rpms/"*.rpm | wc -l)"
  [ "$nrpm" -eq "$npkg" ] || die "se esperaban $npkg .rpm convertidos, hay $nrpm"
  log "  conversión completa: $nrpm .rpm"
  sign_rpms
}

# --- PASO 5: RPMs del proyecto (gh-pages) -------------------------------------
download_project_rpms() {
  log "PASO 5/14 — descargando 8 .rpm del proyecto desde gh-pages"
  curl -fL "$PROJECT_RPM_URL/repodata/repomd.xml" -o "$WORK/repomd.xml" \
    || die "no se pudo descargar repomd.xml de $PROJECT_RPM_URL"
  # href del primary.xml desde repomd (bloque <data type="primary">)
  local primary_href
  primary_href="$(sed -n '/<data type="primary">/,/<\/data>/p' "$WORK/repomd.xml" \
    | grep -oP '<location href="\K[^"]+')"
  [ -n "$primary_href" ] || die "repomd.xml sin <data type=\"primary\">"
  curl -fL "$PROJECT_RPM_URL/$primary_href" -o "$WORK/primary.xml.gz"
  gunzip -f "$WORK/primary.xml.gz"

  local name n=0
  for name in "${PROJECT_STACK[@]}"; do
    local href b h
    href=""
    # grep ANCLADO (M8): los <location href=...> de gh-pages NO llevan barra
    # inicial ("dnf5-5.4.2.1-1.aarch64.rpm"), así que se ancla por basename con
    # "$name"-<dígito> (evita casar dnf-hello/libdnf5); además se filtra por
    # basename que empiece por "$name-".
    while IFS= read -r h; do
      b="$(basename "$h")"
      case "$b" in
        "$name"-[0-9]*) href="$h"; break ;;
      esac
    done < <(grep -oP 'href="\K[^"]*'"$name"'-'"[0-9]"'[^"]*\.rpm' "$WORK/primary.xml")
    [ -n "$href" ] || die "no se encontró el .rpm de '$name' en primary.xml (gh-pages)"
    n=$((n+1))
    log "  [${n}] $name → $(basename "$href")"
    curl -fL "$PROJECT_RPM_URL${href#/}" -o "$WORK/rpms-project/$(basename "$href")" \
      || die "falló la descarga de $href"
  done
  local nr
  nr="$(ls "$WORK/rpms-project/"*.rpm | wc -l)"
  [ "$nr" -eq "${#PROJECT_STACK[@]}" ] || die "se esperaban ${#PROJECT_STACK[@]} .rpm del proyecto, hay $nr"
  log "  OK: $nr .rpm del proyecto descargados"
}

# --- PASO 6: población de la rpmdb ---------------------------------------------
populate_rpmdb() {
  log "PASO 6/14 — poblando la rpmdb sqlite con rpm --root ($SUDO)"
  # dbpath RELATIVO al root (rpm >= 4.16 lo une a --root; M1: verificación final
  # también con --root).
  $SUDO rpm --initdb --root "$ROOTFS" --dbpath "$DBREL" \
    || die "rpm --initdb falló"
  $SUDO rpm -ivh --root "$ROOTFS" --dbpath "$DBREL" \
        --ignorearch --nodeps --noscripts \
        "$WORK/rpms/"*.rpm "$WORK/rpms-project/"*.rpm \
    || die "rpm -ivh (población) falló"
  # Clave pública del repo en la rpmdb del rootfs (gpgcheck sin prompt en el
  # dispositivo). Se descarga de gh-pages junto con los rpms del proyecto;
  # termux.repo exige gpgcheck=1 → fallo de descarga es FATAL.
  curl -fL "$PROJECT_RPM_URL/termux-rpm.gpg" -o "$WORK/termux-rpm.gpg" \
    || die "no se pudo descargar termux-rpm.gpg desde $PROJECT_RPM_URL (requerido: gpgcheck=1)"
  if [ -s "$WORK/termux-rpm.gpg" ]; then
    $SUDO rpm --root "$ROOTFS" --dbpath "$DBREL" --import "$WORK/termux-rpm.gpg" \
      || die "importación de la clave pública en la rpmdb falló"
  else
    die "termux-rpm.gpg descargado pero vacío desde $PROJECT_RPM_URL"
  fi
  # El rootfs queda con ficheros propiedad de root; se normaliza al usuario del
  # runner para poder leer/zipear (la propiedad no importa en el dispositivo).
  $SUDO chown -R "$(id -u):$(id -g)" "$ROOTFS"
  log "  rpmdb poblada"
}

# --- PASO 7: conffiles de dnf5 (verificar, no reescribir) -----------------------
# verify_termux_repo <path>: greps de verificación comunes (conffile o fallback).
verify_termux_repo() {
  local repo="$1"
  grep -q "Leonisaurov.github.io/dnf-for-termux/rpm/" "$repo" \
    || die "termux.repo no apunta a gh-pages (Leonisaurov.github.io/dnf-for-termux/rpm/)"
  grep -q 'gpgcheck=1' "$repo" || die "termux.repo sin gpgcheck=1"
  grep -q 'repo_gpgcheck=1' "$repo" || die "termux.repo sin repo_gpgcheck=1"
  grep -q 'termux-rpm.gpg' "$repo" || die "termux.repo sin gpgkey termux-rpm.gpg"
}

configure_dnf5() {
  log "PASO 7/14 — verificando conffiles de dnf5"
  local repo="$USR/etc/yum.repos.d/termux.repo"
  local conf="$USR/etc/dnf/dnf.conf"

  # termux.repo lo instala el .rpm de dnf5: SOLO se verifica que exista y apunte
  # a gh-pages con gpgcheck=1 repo_gpgcheck=1 y la gpgkey de termux-rpm.gpg.
  if [ -f "$repo" ]; then
    verify_termux_repo "$repo"
    log "  $repo OK (gh-pages, gpgcheck=1 repo_gpgcheck=1, gpgkey termux-rpm.gpg)"
  else
    warn "  $repo NO existe (el .rpm de dnf5 debería haberlo instalado) — generando termux.repo correcto"
    mkdir -p "$USR/etc/yum.repos.d"
    # Fallback con contenido CORRECTO: config/yum.repos.d/termux.repo apunta a
    # packages.termux.dev/rpm/ (404) con repo_gpgcheck=0, NO vale. Baseurl de
    # gh-pages + gpgcheck=1 + repo_gpgcheck=1 + gpgkey de termux-rpm.gpg.
    printf '# termux.repo - repositorio dnf-for-termux (gh-pages)\n[termux]\nname=Termux RPM Repository\nbaseurl=https://Leonisaurov.github.io/dnf-for-termux/rpm/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://Leonisaurov.github.io/dnf-for-termux/rpm/termux-rpm.gpg\n' > "$repo"
    # re-ejecutar las mismas verificaciones tras escribirlo
    verify_termux_repo "$repo"
    log "  $repo generado OK (gh-pages, gpgcheck=1 repo_gpgcheck=1, gpgkey termux-rpm.gpg)"
  fi

  if [ -f "$conf" ]; then
    log "  $conf OK"
  else
    warn "  $conf NO existe — copiando de config/ con @PREFIX@"
    mkdir -p "$USR/etc/dnf"
    sed "s#@PREFIX@#/data/data/com.termux/files/usr#g" \
      "$SCRIPT_DIR/config/dnf/dnf.conf" > "$conf"
  fi
}

# --- PASO 8: limpieza de la rpmdb (M2) -----------------------------------------
cleanup_rpmdb() {
  log "PASO 8/14 — limpieza de la rpmdb (wal/shm) + integrity_check"
  local dbdir="$USR/var/lib/rpm"
  rm -f "$dbdir/Packages.sqlite-wal" "$dbdir/Packages.sqlite-shm"
  local out
  out="$(sqlite3 "$dbdir/Packages.sqlite" "PRAGMA integrity_check;" 2>&1 || true)"
  if [ "$(printf '%s\n' "$out" | head -1)" != "ok" ]; then
    die "PRAGMA integrity_check falló en Packages.sqlite: $out"
  fi
  log "  integrity_check: ok"
}

# --- PASO 9: auditoría DT_NEEDED estática (C6) ----------------------------------
dt_needed_audit() {
  log "PASO 9/14 — auditoría DT_NEEDED con readelf (estático; no se ejecuta ningún ELF)"
  : > "$WORK/dt-needed-audit.txt"
  local libdir="$USR/lib" libexecdir="$USR/libexec"
  local -A have=()
  local f elf need fail=0 nelf=0 nneed=0
  # sonames disponibles en lib/ y libexec/
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    have[$(basename "$f")]=1
  done < <(find "$libdir" "$libexecdir" -maxdepth 1 -type f -name '*.so*' 2>/dev/null)

  # ELF en bin/, lib/, libexec/ (file los identifica aunque sean aarch64)
  while IFS= read -r elf; do
    [ -n "$elf" ] || continue
    nelf=$((nelf+1))
    while IFS= read -r need; do
      [ -n "$need" ] || continue
      nneed=$((nneed+1))
      if [ -n "${have[$need]:-}" ]; then
        printf 'OK   %s -> %s\n' "${elf#$USR/}" "$need" >> "$WORK/dt-needed-audit.txt"
      elif in_bionic_libs "$need"; then
        printf 'SYS  %s -> %s (bionic del dispositivo)\n' "${elf#$USR/}" "$need" >> "$WORK/dt-needed-audit.txt"
      else
        printf 'MISS %s -> %s\n' "${elf#$USR/}" "$need" >> "$WORK/dt-needed-audit.txt"
        warn "DT_NEEDED sin resolver: $need (en ${elf#$USR/})"
        fail=1
      fi
    done < <(readelf -d "$elf" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
  done < <(find "$USR/bin" "$libdir" "$libexecdir" -type f -print0 2>/dev/null \
           | xargs -0 file 2>/dev/null | grep -i 'ELF' | cut -d: -f1 | sort -u)

  if [ "$fail" -ne 0 ]; then
    die "hay DT_NEEDED sin resolver (ver $WORK/dt-needed-audit.txt)"
  fi
  log "  OK: $nelf ELF auditados, $nneed NEEDED resueltos (log: $WORK/dt-needed-audit.txt)"
}

# --- PASO 10: SYMLINKS.txt (formato target←path) --------------------------------
generate_symlinks() {
  log "PASO 10/14 — SYMLINKS.txt (formato target←path) y borrado de symlinks"
  (
    cd "$USR"
    while read -r -d '' link; do
      echo "$(readlink "$link")←${link#./}" >> SYMLINKS.txt
      rm -f "$link"
    done < <(find . -type l -print0)
  )
  local n
  n="$(wc -l < "$USR/SYMLINKS.txt")"
  log "  SYMLINKS.txt: $n entradas (paths relativos a \$PREFIX, sin prefijo data/)"
  [ "$n" -gt 0 ] || warn "  no se encontraron symlinks en el árbol"
}

# --- PASO 11: auditoría bin/ sin gestores de paquetes ajenos (m1) ---------------
audit_no_pkg_managers() {
  log "PASO 11/14 — auditoría bin/: sin apt/pacman/dpkg/makepkg (m1)"
  local bad
  bad="$(find "$USR/bin" -maxdepth 1 \( -type f -o -type l \) -printf '%f\n' 2>/dev/null \
         | grep -Ex 'apt|apt-get|apt-cache|dpkg|pacman|makepkg|repo-add' || true)"
  if [ -n "$bad" ]; then
    die "bin/ contiene gestores de paquetes no deseados: $(printf '%s ' $bad)"
  fi
  log "  OK: bin/ sin apt/pacman/dpkg/makepkg/repo-add"
}

# --- PASO 12: empaquetado zip ----------------------------------------------------
package_zip() {
  log "PASO 12/14 — empaquetando zip (entries relativos a \$PREFIX)"
  local zipfile="$OUT_DIR/bootstrap-$ARCH.zip"
  rm -f "$zipfile"
  ( cd "$USR" && zip -9r "$zipfile" . -x 'var/cache/*' 'tmp/*' )
  # entries sin prefijo data/ ni ./; SYMLINKS.txt presente
  if unzip -l "$zipfile" | grep -qE '(^| )data/'; then
    die "el zip contiene entries con prefijo data/ — revisar el empaquetado"
  fi
  if ! unzip -l "$zipfile" | grep -q 'SYMLINKS.txt'; then
    die "SYMLINKS.txt ausente en el zip"
  fi
  local first
  first="$(unzip -l "$zipfile" | awk 'NR>=4 {print $4; exit}')"
  case "$first" in
    bin/*|etc/*|lib/*|libexec/*|share/*|var/*|SYMLINKS.txt) : ;;
    *) die "primer entry inesperado en el zip: $first" ;;
  esac
  log "  zip creado: $zipfile"
}

# --- PASO 13: verificaciones finales ---------------------------------------------
verify_outputs() {
  log "PASO 13/14 — verificaciones finales"
  local zipfile="$OUT_DIR/bootstrap-$ARCH.zip" count size npub
  unzip -l "$zipfile" | tail -1
  # M1: rpm -qa con --root (sudo cuando aplica); rango [90,200] (m3) y clave
  # pública importada (gpg-pubkey >= 1): cota inferior alta para detectar un
  # cierre roto (el fix de DEPENDS debe dar ~93 + 8 proyecto + gpg-pubkey).
  count="$($SUDO rpm -qa --root "$ROOTFS" --dbpath "$DBREL" 2>/dev/null | wc -l)"
  if [ "$count" -lt 90 ] || [ "$count" -gt 200 ]; then
    die "rpm -qa count fuera de [90,200]: $count (m3)"
  fi
  npub="$($SUDO rpm -qa --root "$ROOTFS" --dbpath "$DBREL" 2>/dev/null | grep -c '^gpg-pubkey-' || true)"
  [ "$npub" -ge 1 ] || die "rpmdb del rootfs sin gpg-pubkey (se importó termux-rpm.gpg?)"
  log "  rpm -qa (rootfs): $count paquetes — rango [90,200] OK (m3); gpg-pubkey: $npub"
  # tamaño < 300MB (m2; warning)
  size="$(stat -c %s "$zipfile")"
  if [ "$size" -gt $((300*1024*1024)) ]; then
    warn "  tamaño del zip: $((size/1024/1024)) MB ≥ 300 MB (m2)"
  else
    log "  tamaño del zip: $((size/1024/1024)) MB (< 300 MB OK, m2)"
  fi
  # sha256 (m4) para las release notes
  sha256sum "$zipfile" | awk '{print $1}' > "$WORK/bootstrap-$ARCH.sha256"
  # manifest viaja con el artifact (CA-9: reproducibilidad)
  cp "$WORK/manifest.txt" "$OUT_DIR/manifest.txt"
  log "  sha256 escrito en $WORK/bootstrap-$ARCH.sha256"
  log "  manifest copiado a $OUT_DIR/manifest.txt"
}

# --- PASO 14: resumen --------------------------------------------------------------
summary() {
  log "PASO 14/14 — resumen"
  local zipfile="$OUT_DIR/bootstrap-$ARCH.zip" npkgs size
  npkgs="$(wc -l < "$WORK/manifest.txt")"
  size="$(stat -c %s "$zipfile")"
  log "  paquetes termux-pacman (manifest): $npkgs"
  log "  rpm del proyecto (gh-pages):        ${#PROJECT_STACK[@]}"
  log "  total rpm -qa (rootfs):             $($SUDO rpm -qa --root "$ROOTFS" --dbpath "$DBREL" 2>/dev/null | wc -l)"
  log "  tamaño del zip:                     $((size/1024/1024)) MB"
  log "  sha256:                             $(cat "$WORK/bootstrap-$ARCH.sha256")"
  log "  salidas:"
  log "    zip:    $zipfile"
  log "    sha256: $WORK/bootstrap-$ARCH.sha256"
  log "    work:   $WORK (pkgs/, rpms/, rpms-project/, rootfs/, manifest.txt)"
}

# --- main -------------------------------------------------------------------------
main() {
  parse_args "$@"
  require jq curl zip unzip rpm rpmbuild sqlite3 readelf gpg bsdtar file sha256sum gunzip
  [ -n "$SUDO" ] && require sudo
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  prepare_dirs
  resolve_package_set
  download_pkgs
  convert_pkgs
  download_project_rpms
  populate_rpmdb
  configure_dnf5
  cleanup_rpmdb
  dt_needed_audit
  generate_symlinks
  audit_no_pkg_managers
  package_zip
  verify_outputs
  summary
}

main "$@"
