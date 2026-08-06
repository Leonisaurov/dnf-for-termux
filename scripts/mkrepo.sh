#!/usr/bin/env bash
# mkrepo.sh — genera metadatos de repositorio dnf/yum (repodata/) para un directorio de .rpm.
#
# Uso: mkrepo.sh <dir_con_rpms>
#   Crea <dir>/repodata/ con repomd.xml + primary.xml.gz + filelists.xml.gz + other.xml.gz.
#   Sin dependencias externas: solo rpm, sha256sum, gzip, date, find, sort.
#   Pensado para dnf5/librepo en Termux (sin createrepo_c).
set -euo pipefail

DIR="${1:?uso: mkrepo.sh <dir_con_rpms>}"
if [ ! -d "$DIR" ]; then
  echo "error: $DIR no es un directorio" >&2
  exit 1
fi

REPODATA="$DIR/repodata"
mkdir -p "$REPODATA"
WORK="$(mktemp -d "$TMPDIR/mkrepo.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- lista de .rpm (solo primer nivel) ---
mapfile -t RPMS < <(find "$DIR" -maxdepth 1 -type f -name '*.rpm' | sort)
if [ "${#RPMS[@]}" -eq 0 ]; then
  echo "error: no hay .rpm en $DIR" >&2
  exit 1
fi
N="${#RPMS[@]}"

# --- utilidades ---
# xml_esc <texto>: escapa caracteres especiales XML
xml_esc() {
  printf '%s' "$1" \
    | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}

# now: timestamp unix
now="$(date +%s)"

# parse_evr <evr> : imprime "epoch|version|release". evr puede ser "ver-rel", "ver", "epoch:ver-rel".
parse_evr() {
  local evr="$1" epoch="0" ver rel
  if [[ "$evr" == *:* ]]; then
    epoch="${evr%%:*}"
    evr="${evr#*:}"
  fi
  if [[ "$evr" == *-* ]]; then
    ver="${evr%%-*}"
    rel="${evr#*-}"
  else
    ver="$evr"
    rel="0"
  fi
  printf '%s|%s|%s' "$epoch" "$ver" "$rel"
}

# entry_from_dep <linea>: convierte "name [<= | >= | < | > | =] evr" en XML <rpm:entry .../>
entry_from_dep() {
  local line="$1" name flags="" rest evr epoch ver rel
  name="${line%% *}"
  rest="${line#* }"
  if [[ "$rest" == *" <= "* ]]; then flags="LE"; evr="${rest#* <= }"; rest="${rest% <= *}"; fi
  if [[ "$rest" == *" >= "* ]]; then flags="GE"; evr="${rest#* >= }"; rest="${rest% >= *}"; fi
  if [[ "$rest" == *" < "* ]]; then flags="LT"; evr="${rest#* < }"; rest="${rest% < *}"; fi
  if [[ "$rest" == *" > "* ]]; then flags="GT"; evr="${rest#* > }"; rest="${rest% > *}"; fi
  if [[ "$rest" == *" = "* ]]; then flags="EQ"; evr="${rest#* = }"; rest="${rest% = *}"; fi
  if [ -z "$flags" ]; then
    printf '      <rpm:entry name="%s"/>\n' "$(xml_esc "$name")"
    return
  fi
  read -r epoch ver rel <<<"$(parse_evr "$evr")"
  printf '      <rpm:entry name="%s" flags="%s" epoch="%s" ver="%s" rel="%s"/>\n' \
    "$(xml_esc "$name")" "$flags" "$epoch" "$(xml_esc "$ver")" "$(xml_esc "$rel")"
}

# --- generación de archivos de metadatos ---
# Cada archivo se crea como XML plano en $WORK, se calculan hashes/tamaños
# y se mueve a repodata/ con nombre "<sha256>-<tipo>.xml.gz".

PRIMARY="$WORK/primary.xml"
FILELISTS="$WORK/filelists.xml"
OTHER="$WORK/other.xml"

: >"$PRIMARY"
: >"$FILELISTS"
: >"$OTHER"

{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="%s">\n' "$N"
} >>"$PRIMARY"
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<filelists xmlns="http://linux.duke.edu/metadata/filelists" packages="%s">\n' "$N"
} >>"$FILELISTS"
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<otherdata xmlns="http://linux.duke.edu/metadata/other" packages="%s">\n' "$N"
} >>"$OTHER"

for rpm in "${RPMS[@]}"; do
  base="$(basename "$rpm")"

  # --- metadatos del paquete ---
  IFS='|' read -r NAME VERSION RELEASE ARCH SUMMARY LICENSE GROUP SIZE EPOCH BUILDTIME ARCHIVESIZE SOURCERPM < <(
    rpm -qp --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}|%{SUMMARY}|%{LICENSE}|%{GROUP}|%{SIZE}|%{EPOCH}|%{BUILDTIME}|%{ARCHIVESIZE}|%{SOURCERPM}\n' "$rpm"
  )
  [ "$EPOCH" = "(none)" ] && EPOCH="0"
  [ -z "$ARCHIVESIZE" ] && ARCHIVESIZE="$SIZE"
  [ -z "$SOURCERPM" ] && SOURCERPM="-"
  desc="$(rpm -qp --qf '%{DESCRIPTION}' "$rpm" | tr '\n' ' ' | tr -s ' ')"
  chk="$(sha256sum "$rpm" | awk '{print $1}')"
  fmtime="$(stat -c %Y "$rpm")"
  pkg_size="$(stat -c %s "$rpm")"

  # --- provides / requires ---
  prov_xml=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    prov_xml+="$(entry_from_dep "$line")\n"
  done < <(rpm -qp --provides "$rpm")
  req_xml=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    req_xml+="$(entry_from_dep "$line")\n"
  done < <(rpm -qp --requires "$rpm")

  # --- bloque en primary.xml ---
  {
    printf '  <package type="rpm">\n'
    printf '    <name>%s</name>\n' "$(xml_esc "$NAME")"
    printf '    <arch>%s</arch>\n' "$(xml_esc "$ARCH")"
    printf '    <version epoch="%s" ver="%s" rel="%s"/>\n' "$EPOCH" "$(xml_esc "$VERSION")" "$(xml_esc "$RELEASE")"
    printf '    <checksum type="sha256" pkgid="YES">%s</checksum>\n' "$chk"
    printf '    <summary>%s</summary>\n' "$(xml_esc "$SUMMARY")"
    printf '    <description>%s</description>\n' "$(xml_esc "$desc")"
    printf '    <packager></packager>\n'
    printf '    <url></url>\n'
    printf '    <time file="%s" build="%s"/>\n' "$fmtime" "$BUILDTIME"
    printf '    <size package="%s" installed="%s" archive="%s"/>\n' "$pkg_size" "$SIZE" "$ARCHIVESIZE"
    printf '    <location href="%s"/>\n' "$(xml_esc "$base")"
    printf '    <format>\n'
    printf '      <rpm:license>%s</rpm:license>\n' "$(xml_esc "$LICENSE")"
    printf '      <rpm:group>%s</rpm:group>\n' "$(xml_esc "$GROUP")"
    printf '      <rpm:buildhost>localhost</rpm:buildhost>\n'
    printf '      <rpm:sourcerpm>%s</rpm:sourcerpm>\n' "$(xml_esc "$SOURCERPM")"
    printf '      <rpm:provides>\n'
    printf '%b' "$prov_xml"
    printf '      </rpm:provides>\n'
    printf '      <rpm:requires>\n'
    printf '%b' "$req_xml"
    printf '      </rpm:requires>\n'
    printf '    </format>\n'
    printf '  </package>\n'
  } >>"$PRIMARY"

  # --- bloque en filelists.xml ---
  {
    printf '  <package pkgid="%s" name="%s" arch="%s">\n' "$chk" "$(xml_esc "$NAME")" "$(xml_esc "$ARCH")"
    printf '    <version epoch="%s" ver="%s" rel="%s"/>\n' "$EPOCH" "$(xml_esc "$VERSION")" "$(xml_esc "$RELEASE")"
    while IFS= read -r f; do
      printf '    <file>%s</file>\n' "$(xml_esc "$f")"
    done < <(rpm -qlp "$rpm")
    printf '  </package>\n'
  } >>"$FILELISTS"

  # --- bloque en other.xml ---
  {
    printf '  <package pkgid="%s" name="%s" arch="%s">\n' "$chk" "$(xml_esc "$NAME")" "$(xml_esc "$ARCH")"
    printf '    <version epoch="%s" ver="%s" rel="%s"/>\n' "$EPOCH" "$(xml_esc "$VERSION")" "$(xml_esc "$RELEASE")"
    printf '  </package>\n'
  } >>"$OTHER"
done

{
  printf '</metadata>\n'
} >>"$PRIMARY"
{
  printf '</filelists>\n'
} >>"$FILELISTS"
{
  printf '</otherdata>\n'
} >>"$OTHER"

# --- comprimir y renombrar con hash; registrar datos para repomd ---
declare -a DATA_TYPES=(primary filelists other)
declare -A CHK OPEN_CHK SIZE OPEN_SIZE HREF

for t in "${DATA_TYPES[@]}"; do
  xml="$WORK/$t.xml"
  gz="$WORK/$t.xml.gz"
  open_chk="$(sha256sum "$xml" | awk '{print $1}')"
  open_size="$(stat -c %s "$xml")"
  gzip -9 -c "$xml" >"$gz"
  chk="$(sha256sum "$gz" | awk '{print $1}')"
  size="$(stat -c %s "$gz")"
  final="$REPODATA/${chk}-$t.xml.gz"
  mv "$gz" "$final"
  CHK[$t]="$chk"
  OPEN_CHK[$t]="$open_chk"
  SIZE[$t]="$size"
  OPEN_SIZE[$t]="$open_size"
  HREF[$t]="repodata/${chk}-$t.xml.gz"
done

# --- repomd.xml ---
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<repomd xmlns="http://linux.duke.edu/metadata/repo" xmlns:rpm="http://linux.duke.edu/metadata/rpm">\n'
  printf '  <revision>%s</revision>\n' "$now"
  for t in "${DATA_TYPES[@]}"; do
    printf '  <data type="%s">\n' "$t"
    printf '    <checksum type="sha256">%s</checksum>\n' "${CHK[$t]}"
    printf '    <open-checksum type="sha256">%s</open-checksum>\n' "${OPEN_CHK[$t]}"
    printf '    <location href="%s"/>\n' "${HREF[$t]}"
    printf '    <timestamp>%s</timestamp>\n' "$now"
    printf '    <size>%s</size>\n' "${SIZE[$t]}"
    printf '    <open-size>%s</open-size>\n' "${OPEN_SIZE[$t]}"
    printf '  </data>\n'
  done
  printf '</repomd>\n'
} >"$REPODATA/repomd.xml"

echo "repodata generado en $REPODATA ($N paquetes):"
ls -la "$REPODATA"
