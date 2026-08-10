# Diseño: Generador de bootstrap dnf5 para Termux

## Estado de implementación

> **2026-08-10 — PUBLICADO.** El generador (`scripts/generate-bootstrap-dnf5.sh`)
> y el workflow (`.github/workflows/bootstrap.yml`) están implementados, el CI
> (`bootstrap.yml`) corrió **SUCCESS** y el **primer release quedó publicado**:
> `bootstrap-2026.08.10-r1+dnf5.android-7` (asset `bootstrap-aarch64.zip` ~73 MB,
> sha256 `55ed99682afa91b3d1c9bfd68e6fd11e269fa4b84cbf2b97dfb3f29809776081`).
> Este bloque marca las correcciones del code-review ya aplicadas; el resto del
> documento se mantiene como spec de referencia.

**Correcciones aplicadas en el código (C1–C6, M1–M9, m1–m5):**

- **C1**: versiones resueltas por `FILENAME` del `main.json` con jq (no regex de pkgrel).
- **C2**: `publish` descarga el artifact con `actions/download-artifact@v4` (name `bootstrap-aarch64`) antes de `gh release`.
- **C3**: permissions — build `{ contents: read, actions: write }`; publish `{ contents: write, actions: read }`.
- **C4**: bloque de firma completo (patrón de `deploy.yml`): `~/.rpmmacros` con `%__gpg_sign_cmd` (macros `%%{...}`), `GPG_BIN="$(command -v gpg)"`, `%_gpg_name dnf-for-termux`, clave pública importada en `$HOME/rpmdb` (`rpm --define "_dbpath $HOME/rpmdb" --import`) ANTES de `rpm -K | grep 'signatures OK'`. Secret: `RPM_SIGNING_KEY`.
- **C5**: cierre transitivo BFS sobre `DEPENDS` con fallback por índice `provides→paquete`.
- **C6**: auditoría DT_NEEDED estática con `readelf` (sin ejecutar los ELF), resuelve cada `NEEDED` contra `$USR/lib` (+`libexec`), falla si no resuelve; log `dt-needed-audit.txt`.
- **M1**: verificaciones con `sudo rpm -qa --root` (cuando `$SUDO` aplica).
- **M2**: tras instalar, `rm -f Packages.sqlite-wal/-shm` + `sqlite3 ... "PRAGMA integrity_check;"`.
- **M4**: lista base de **30** paquetes (bash, bzip2, command-not-found, coreutils, curl, dash, diffutils, findutils, gawk, grep, gzip, less, procps, psmisc, sed, tar, termux-core, termux-exec, termux-tools, util-linux, xz-utils, ed, dos2unix, inetutils, lsof, nano, net-tools, patch, unzip, termux-am). `termux-keyring` **excluido**.
- **M6**: documentado rpm 4.18.2 del runner (Ubuntu 24.04) — esquema sqlite compatible con el 4.18.1 del dispositivo.
- **M7**: `concurrency: { group: bootstrap-release, cancel-in-progress: false }`.
- **M8**: grep de href de gh-pages anclado con `/[^/"]*$name-[0-9]`.
- **M9**: **no existe `--no-sign`**: el generador **siempre firma**; el flag `--sign-key <path>` es solo para desarrollo local.
- **m1**: auditoría de que `bin/` no contenga `apt|apt-get|apt-cache|dpkg|pacman|makepkg|repo-add` (falla si aparece).
- **m2**: tamaño del zip `< 300MB` (warning si no).
- **m3**: `rpm -qa` count en `[50,200]`.
- **m4**: sha256 del zip en las release notes.
- **m5**: `gpg --export --armor` con fingerprint fijo `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9`.

**Decisiones de implementación (verificadas en la investigación):**

- Cierre transitivo probado: **93 paquetes finales, 0 sin resolver** (nombre exacto; el índice provides quedó como fallback). `python` es aceptado en el cierre.
- **arch=any (CRÍTICO)**: `termux-am` y `ca-certificates` son `arch=any`; `rpmbuild --target aarch64` falla con ellos. Implementado el helper **`fix_any_arch_pkg()`** que re-empaqueta una copia del `.pkg` con el `.PKGINFO` parcheado a `arch = aarch64` antes de convertir.
- **Conffile**: el `.rpm` de dnf5 ya instala `$PREFIX/etc/yum.repos.d/termux.repo` apuntando a gh-pages con `gpgcheck=1 repo_gpgcheck=1` + gpgkey; el generador **solo verifica** (fallback: copia de `config/` sustituyendo `@PREFIX@`). `$PREFIX/etc/dnf/dnf.conf` igual.
- `termux-keyring` **excluido** (el keyring de dnf5 es la clave pública en la rpmdb + `gpgkey` del repo).
- `--no-sign` **eliminado**: el bootstrap publicado siempre va firmado; `--sign-key` para desarrollo.

---

> Proyecto: `Leonisaurov/dnf-for-termux` · Fecha: 2026-08-09 · Estado: **DISEÑO (pendiente de aprobación)**
> Este documento es la especificación para el builder. No implementa código.
> Fuentes verificadas en el repo: `scripts/pkg2rpm.sh`, `scripts/install-dnf-termux.sh`,
> `.github/workflows/{build,deploy}.yml`, `packages/*/build.sh`, `config/dnf/dnf.conf`,
> `config/yum.repos.d/termux.repo`, `REPORT.md`/`PROGRESS.md` + contexto del orquestador
> (formato de bootstrap de `TermuxInstaller.java` y modelo `generate-bootstraps.sh`).

---

## 1. Propósito

Generar un **bootstrap de Termux** (zip que la app Termux acepta como sistema base) cuyo
gestor de paquetes nativo sea **dnf5**, reemplazando a pacman/apt.

- El zip contiene el árbol **relativo a `$PREFIX`** (`/data/data/com.termux/files/usr`):
  `bin/`, `etc/`, `lib/`, `libexec/`, `share/`, `var/`, `SYMLINKS.txt`, …
- **TODO el contenido va como RPMs** (decisión del usuario): el stack dnf5 (8 RPMs del
  proyecto, ya firmados en gh-pages) + el resto del sistema convertido a RPM.
- **NO se reconstruye nada desde fuente**: los paquetes base se toman como `.pkg.tar.zst`
  de la última versión del repo binario de termux-pacman
  (`https://sync.termux-pacman.dev/main/`) y se convierten a `.rpm` con el convertidor
  existente (`scripts/pkg2rpm.sh`). Solo arquitectura **aarch64**.
- La **rpmdb** (`$PREFIX/var/lib/rpm`, sqlite) viaja **pre-poblada** con todos los paquetes
  como instalados, para que dnf5 sepa qué hay en el sistema sin necesidad de una
  transacción inicial.
- La integración del build system termux que genere RPMs nativamente queda **PENDIENTE**
  (fuera de alcance).

### Entregables del diseño

1. Lista exacta de paquetes (origen y rol).
2. Estructura del rootfs/zip.
3. Estrategia de población de la rpmdb en CI.
4. Algoritmo de `scripts/generate-bootstrap-dnf5.sh` (pseudocódigo).
5. Estructura del workflow `.github/workflows/bootstrap.yml`.
6. Decisiones justificadas, riesgos/mitigaciones y criterios de aceptación verificables.

---

## 2. Lista de paquetes del bootstrap

El set se compone de **tres conjuntos**:

| Conjunto | Origen | Mecanismo |
|---|---|---|
| **A. Stack dnf5 (8)** | gh-pages del proyecto (`https://leonisaurov.github.io/dnf-for-termux/rpm/`) | Descargar los `.rpm` **ya firmados** (resolviendo versión actual vía `repodata/primary.xml.gz`) |
| **B. Base termux-pacman (29)** | `https://sync.termux-pacman.dev/main/` | Descargar `.pkg.tar.zst` → convertir a `.rpm` |
| **C. Dependencias runtime del stack + cierre de B** | ídem | Curated (ver abajo) + cierre transitivo vía la metadata del repo |

### A. Stack dnf5 — del repo RPM del proyecto (8 paquetes, ya firmados)

| Paquete | Versión (repo) | Rol |
|---|---|---|
| `dnf5` | 5.4.2.1-1 | El gestor (CLI + libdnf5). Trae `etc/dnf/dnf.conf` y `etc/yum.repos.d/termux.repo` como confiles |
| `rpm` | 4.18.1-4 | librpm/rpmdb (sqlite). **Patcheado para Android rootless** (obligatorio, no vale el oficial) |
| `libpopt` | 1.19-4 | Dep de rpm (parche anti-SIGSYS). **Obligatorio el del overlay** |
| `libsolv` | 0.7.39-1 | SAT solver (`ENABLE_COMPLEX_DEPS=ON`) |
| `librepo` | 1.20.0-0 | Descarga de repos/metadata (libcurl + gpgme) |
| `libcomps` | 0.1.24-0 | Grupos de paquetes |
| `zchunk` | 1.5.3-0 | Metadata comprimida |
| `createrepo-c` | 1.2.4-0 | Generación de `repodata/` (plugin local de dnf5) |

> `dnf-hello` (1.0-1) **NO se incluye** en el bootstrap mínimo (es el paquete de prueba del
> proyecto). Añadirlo es trivial si se desea (está en el mismo repo).

**Nota crítica sobre la firma**: estos 8 RPMs ya están **firmados con la clave del repo**
(`E4AC7735BD60196E19123DB6247EEE5F6AA25EC9`). Los RPMs **convertidos** (conjuntos B y C)
NO llevan firma → el generador debe **firmarlos con la misma clave** (secret
`RPM_SIGNING_KEY`) para que `gpgcheck=1` funcione de extremo a extremo (decisión en §6-D3).

### B. Base termux-pacman — 29 paquetes (lista del bootstrap de termux-pacman, menos `pacman`)

`bash, bzip2, command-not-found, coreutils, curl, dash, diffutils, findutils, gawk, grep,
gzip, less, procps, psmisc, sed, tar, termux-core, termux-exec, termux-keyring, termux-tools,
util-linux, xz-utils, ed, dos2unix, inetutils, lsof, nano, net-tools, patch, unzip`

> `termux-keyring` se conserva (compat con el ecosistema) pero no es estrictamente necesario
> para dnf5: el keyring de dnf5 es la clave pública importada en la rpmdb + `gpgkey` del repo.
> Se puede eliminar para adelgazar (decisión abierta menor, no bloqueante).

### C. Dependencias runtime del stack (curated) — desde termux-pacman

Extraídas de los `TERMUX_PKG_DEPENDS` reales de `packages/*/build.sh` del repo (verificado):

| Paquete (pacman) | Lo requiere | Notas |
|---|---|---|
| `libc++` | dnf5, libdnf5, libdnf5-cli | **CRÍTICO**: los binarios C++ enlazan `libc++_shared.so`; sin él no arranca nada |
| `libsqlite` | dnf5, rpm, createrepo-c | rpmdb sqlite |
| `json-c` | dnf5 | |
| `fmt` | dnf5 | |
| `glib` | dnf5, librepo, createrepo-c | |
| `libxml2` | dnf5, librepo, libcomps, createrepo-c | |
| `zstd` | dnf5, rpm, zchunk, createrepo-c | |
| `liblzma` | dnf5, rpm, createrepo-c | subpkg de xz; se incluye aparte |
| `openssl` | dnf5, rpm, zchunk, librepo, createrepo-c | libssl/libcrypto |
| `zlib` | dnf5, rpm, libsolv, libcomps, zchunk, createrepo-c | |
| `libsmartcols` | dnf5 | subpkg de util-linux |
| `libandroid-glob` | dnf5, libpopt | `glob()`/`globfree()` de bionic |
| `libcurl` | librepo, zchunk, createrepo-c | subpkg de curl (lib compartida) |
| `gpgme` | librepo | verificación GPG de metadata (spawn de `gpg`) |
| `libexpat` | libcomps | |
| `libarchive` | rpm | |
| `libandroid-spawn` | rpm | |
| `libbz2` | rpm, createrepo-c | subpkg de bzip2 |
| `libgcrypt` | rpm | |
| `libiconv` | rpm | |
| `lua54` | rpm | scriptlets (no se ejecutan, pero librpm lo enlaza) |
| `readline` | rpm | |
| `file` | rpm | libmagic |
| `ca-certificates` | librepo/curl | **HTTPS**: sin el bundle de CAs, dnf5 no alcanza gh-pages |
| `gnupg` | gpgme (runtime) | el binario `gpg` que gpgme invoca |
| `gettext` | glib | `libintl` en runtime |

> El conjunto B también arrastra deps transitivas (p. ej. `ncurses`/`libncursesw` desde
> `less`/`procps`/`nano`, etc.). El generador **calcula el cierre transitivo** leyendo el campo
> `%DEPENDS%` de la metadata del repo pacman (§5-A3) partiendo de B+C; los nombres que no
> existan como paquete o sean provides (`sh`, `bash`, `glibc`, `rpmlib(...)`, …) se ignoran
> con warning. **Cantidad esperada total: ~70–80 RPMs.**

---

## 3. Estructura del rootfs y del zip

### 3.1 Staging del generador

```
$TMP/bootstrap.XXXXXX/                      # staging (bajo $TMPDIR, nunca /tmp en Termux)
├── rootfs/                                 # RAÍZ del rootfs = $ROOTFS
│   └── data/data/com.termux/files/usr/     # $USR  ← árbol real de $PREFIX
│       ├── bin/  etc/  lib/  libexec/  share/  var/
│       ├── SYMLINKS.txt                    # generado en el paso de symlinks (¡se incluye en el zip!)
│       └── ... (todo el contenido instalado)
├── project-rpms/                           # los 8 .rpm firmados de gh-pages
├── pacman-pkgs/                            # .pkg.tar.zst descargados de termux-pacman
├── convert-rpms/                           # .rpm convertidos por pkg2rpm.sh (B+C)
└── termux-rpm.gpg                          # clave pública exportada
```

**Por qué `$ROOTFS/data/data/com.termux/files/usr`**: los `.pkg` de termux-pacman llevan el
layout `data/data/com.termux/files/usr/...` dentro del tar (lo verifica `pkg2rpm.sh`, línea
45), y `pkg2rpm.sh` reempaqueta el contenido en rutas **absolutas**
`/data/data/com.termux/files/usr/...` (`%files`, líneas 87 y 108-110). Por tanto:

- `rpm -i --root "$ROOTFS"` instala cada archivo en
  `$ROOTFS/data/data/com.termux/files/usr/...` **automáticamente** (rpm antepone el root al
  path del payload). No hay que re-mapear rutas.
- El **zip se crea desde `$USR`** (`cd "$USR" && zip -r … .`), de modo que los entries quedan
  relativos a `$PREFIX` (`bin/…`, `etc/…`, `SYMLINKS.txt`…), que es lo que exige
  `TermuxInstaller.java`. **Nunca** debe quedar un prefijo `data/` en el zip.

### 3.2 Contenido del zip final

```
bootstrap-aarch64.zip
├── SYMLINKS.txt            # OBLIGATORIO: cada línea "target←link" (readlink←path)
├── bin/  etc/  lib/  libexec/  share/  var/
└── ... (sin symlinks; sin caches; sin .rpm/.pkg)
```

Reglas de la app que el diseño respeta (verificado, `TermuxInstaller.java`):

- El zip **debe** contener `SYMLINKS.txt` en su raíz; sin él la app aborta.
- Los symlinks se **eliminan del zip** y se registran en `SYMLINKS.txt`; la app los recrea
  (y el flujo manual de la wiki los recrea con
  `cat SYMLINKS.txt | awk -F "←" '{system("ln -s \""$1"\" \""$2"\"")}'`).
- La app hace `chmod 0700` a los entries que empiecen por `bin/`, `libexec`,
  `lib/apt/apt-helper`, `lib/apt/methods`. Los ejecutables fuera de esas rutas pueden perder
  el bit de ejecución → **auditoría en CI**: verificar que ningún ejecutable viva fuera de
  `bin/|libexec/` (riesgo R7).
- La app ignora `usr/tmp`, `usr/etc/termux/termux.env.tmp`, `usr/etc/termux/termux.env` para
  el chequeo de "$PREFIX vacío".

### 3.3 Rutas clave de dnf5 dentro del rootfs (deben existir tras el bootstrap)

```
$PREFIX/etc/dnf/dnf.conf               # lo trae el paquete dnf5 (confiles)
$PREFIX/etc/yum.repos.d/termux.repo    # ídem → apunta a gh-pages, gpgcheck=1 repo_gpgcheck=1
$PREFIX/var/lib/rpm/                   # rpmdb sqlite (se genera en CI con rpm --root)
$PREFIX/var/lib/dnf/                   # persistdir (crear dir vacío)
$PREFIX/var/cache/dnf/                 # cachedir (crear dir vacío; excluir del zip)
$PREFIX/etc/dnf/vars/                  # varsdir (crear dir vacío)
```

> `dnf.conf` y `termux.repo` **ya vienen dentro del `.rpm` de dnf5** (los escribe
> `termux_step_post_make_install()` de `packages/dnf5/build.sh` con las rutas reales de
> `$PREFIX`; el `%files` de `pkg2rpm.sh` los incluye). El generador solo **verifica** que
> existan y apunten a la URL correcta (no los reescribe).

---

## 4. Población de la rpmdb (sqlite) en CI

**Opción elegida (A, recomendada por la investigación)**: usar el `rpm` de la distro del
runner con `--root` para instalar los `.rpm` **convertidos** (no los `.pkg`; el runner no
tiene pacman y no lo necesita). Los headers RPM y el esquema sqlite de la rpmdb son
portables entre rpm 4.16/4.18; el runner debe ser **Ubuntu 24.04** (rpm 4.18.1, el mismo
major que el rpm del dispositivo 4.18.1-4 → mismo esquema sqlite, sin migración).

### 4.1 Comando clave

```bash
# dbpath ABSOLUTO dentro del rootfs: rpm >= 4.18 RECHAZA --dbpath relativo
# ("arguments to --dbpath must begin with '/'") y une el absoluto a --root, con lo
# que en disco queda $ROOTFS/data/data/... (idéntico al layout relativo anterior).
# El dispositivo lo verá en $PREFIX/var/lib/rpm. (decisión D8/R1 corregida)
SUDO=${SUDO:-}   # en CI: "sudo" (passwordless en runners); local sin root: vacío
DBREL="/data/data/com.termux/files/usr/var/lib/rpm"
$SUDO rpm -ivh --root "$ROOTFS" \
       --dbpath "$DBREL" \
       --nodeps --ignorearch --noscripts --notriggers --nosignature --noverify \
       "$TMP/convert-rpms/"*.rpm "$TMP/project-rpms/"*.rpm
```

- `--nodeps --ignorearch --noscripts --notriggers`: los `.rpm` convertidos no declaran
  Requires (`AutoReqProv: no`) y no llevan scriptlets; los del proyecto tampoco los
  necesitan en un rootfs estático. `--nosignature --noverify`: no comprobar firmas en el
  rootfs (se comprueban en el dispositivo).
- El **dbpath resultante** es `$ROOTFS/data/data/com.termux/files/usr/var/lib/rpm/Packages`
  (sqlite) → viaja dentro del zip en `var/lib/rpm/`. Alternativa equivalente:
  `--define "_dbpath /data/data/com.termux/files/usr/var/lib/rpm"` (con `--root`, rpm lo
  une al root). Se documentan ambas; se implementa la **absoluta** (el relativo fue la
  decisión original D8, pero **rpm ≥ 4.18 lo rechaza** — corregido en el generador).
- **`--ignorearch` no es estrictamente necesario en runner arm64** (el host es aarch64),
  pero se mantiene por robustez (si algún día se corre en x86_64, no rompe).

### 4.2 ¿Por qué hace falta `sudo`?

El runner no corre como root y los RPMs declaran `%defattr(-,root,root)`: `rpm -i` intenta
`chown` a uid 0 y falla como usuario normal. Los runners de GitHub tienen `sudo` sin
contraseña → el paso de población usa `$SUDO`. Tras instalar, `$SUDO chown -R
"$(id -u):$(id -g)" "$ROOTFS"` para que el zip/lecturas sean del usuario del runner
(la propiedad no importa en el dispositivo; la app extrae como app user).

> Alternativa sin `sudo` (documentada, no elegida): `fakeroot rpm -ivh …` (intercepta
> chown/chmod vía LD_PRELOAD). Más frágil con sqlite; se prefiere sudo en CI.

### 4.3 Importación de la clave pública en la rpmdb

```bash
$SUDO rpm --root "$ROOTFS" --dbpath "/data/data/com.termux/files/usr/var/lib/rpm" \
     --import "$TMP/termux-rpm.gpg"
```

Con esto `gpgcheck=1` de dnf5 **valida las firmas de paquetes sin prompt** (usa el keyring
de la rpmdb). El `repo_gpgcheck=1` (metadata) usa el keyring de librepo
(`<cachedir>/<repoid>/pubring`), que se puebla en el primer uso vía auto-import de la
`gpgkey` (patch 0015 del proyecto, flujo ya validado en dispositivo).

### 4.4 Verificación de la rpmdb en CI

```bash
count=$(rpm -qa --root "$ROOTFS" --dbpath "/data/data/com.termux/files/usr/var/lib/rpm" | wc -l)
[ "$count" -ge 60 ]                      # ~70-80 esperados
rpm -qa --root "$ROOTFS" --dbpath "/data/data/com.termux/files/usr/var/lib/rpm" | grep -c '^gpg-pubkey-'   # ≥ 1 (clave importada)
rpm -qa --root "$ROOTFS" --dbpath "/data/data/com.termux/files/usr/var/lib/rpm" | grep -q '^dnf5-'         # el stack está
```

---

## 5. Algoritmo del script `scripts/generate-bootstrap-dnf5.sh`

### 5.1 Interfaz

```bash
scripts/generate-bootstrap-dnf5.sh [opciones]

  --arch aarch64          # única arquitectura soportada (default: aarch64)
  --out-dir DIR           # dir de salida del zip (default: $PWD)
  --offline DIR           # modo offline: usa .pkg/.rpm de DIR + manifest; sin red ni cierre
  --no-sign               # no firmar los RPMs convertidos (implica termux.repo con gpgcheck=0)
  --keep-staging          # no borrar el staging al terminar (debug)
  --verbose               # traza de pasos
  --help

Entorno (env):
  TMPDIR                  # obligatorio en Termux; en CI puede ser /tmp (runner Linux)
  RPM_SIGNING_KEY         # (si --sign, default) clave privada GPG del repo
  SUDO                    # "" por defecto; CI pasa "sudo"
  PROJECT_RPM_URL         # default https://leonisaurov.github.io/dnf-for-termux/rpm/
  PACMAN_REPO_URL         # default https://sync.termux-pacman.dev/main/
```

Estilo del repo: `#!/usr/bin/env bash`, `set -euo pipefail`, staging bajo `$TMPDIR`
(fallback `: "${TMPDIR:=/tmp}"` para runners), mensajes en español, `trap` de limpieza.

### 5.2 Pseudocódigo

```
PASO 0 — preparación
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap.XXXXXX"); trap 'cleanup' EXIT
  ROOTFS=$TMP/rootfs ; USR=$ROOTFS/data/data/com.termux/files/usr
  mkdir -p "$ROOTFS" "$OUT"
  require: rpm rpmbuild bsdtar zip gpg curl zstd file  (fallo claro si falta alguno)

PASO 1 — RPMs del proyecto (gh-pages) [online]
  repomd=$(curl -fsSL $PROJECT_RPM_URL/repodata/repomd.xml)
  primary_href=<location href de type=primary>                    # desde repomd
  curl -fsSL "$PROJECT_RPM_URL/repodata/$primary_href" | gunzip > primary.xml
  for name in dnf5 rpm libpopt libsolv librepo libcomps zchunk createrepo-c; do
      href=$(grep -oP '<location href="\K[^"]*'"$name"'[^"]*\.rpm' primary.xml | head -1)
      curl -fsSL "$PROJECT_RPM_URL/$href" -o "$TMP/project-rpms/$(basename $href)"
  done
  assert: 8 .rpm descargados
  [offline]: copiar los .rpm de --offline dir (patrón "*-aarch64.rpm")

PASO 2 — paquetes base de termux-pacman + cierre transitivo [online]
  curl -fsSL "$PACMAN_REPO_URL/main.db" -o $TMP/main.db        # fallback: main.db.tar.gz
  bsdtar -xf $TMP/main.db -C "$TMP/pacman-db"                  # dirs "<name>-<ver>-<arch>/desc"
  resolve_latest <name>:  # en pacman-db, dirs ^<name>-[^-]+-aarch64$; toma el de
                          # mayor versión (sort -V sobre el segmento ver); lee %FILENAME%
  # set inicial = BASE_PKGS (29, §2-B) + CURATED_DEPS (§2-C, 26)
  # cierre transitivo: cola = inicial; para cada pkg: lee %DEPENDS% de su desc;
  #   si el dep existe como paquete → encolar; si no (provides: sh, glibc, rpmlib…) → warning.
  #   Se EXCLUYEN los nombres del stack A (los provee gh-pages).
  for name in $resuelto; do
      fname=$(resolve_latest $name); curl -fsSL "$PACMAN_REPO_URL/$fname" -o "$TMP/pacman-pkgs/$fname"
  done
  manifest="$TMP/pacman-manifest.txt"   # name|version|source|sha256 (reproducibilidad)
  [offline]: usar los .pkg de --offline dir + manifest previo (sin cierre)

PASO 3 — conversión .pkg → .rpm
  for pkg in "$TMP/pacman-pkgs/"*.pkg.tar.*; do
      bash scripts/pkg2rpm.sh "$pkg" "$TMP/convert-rpms"
  done
  assert: nº de .rpm == nº de .pkg

PASO 4 — firma de los RPMs convertidos (salvo --no-sign)
  [ -z "$RPM_SIGNING_KEY" ] && fail "RPM_SIGNING_KEY no definido (o usa --no-sign)"
  echo "$RPM_SIGNING_KEY" | gpg --batch --import
  # patrón probado de deploy.yml: %__gpg_sign_cmd en ~/.rpmmacros, gpg ABSOLUTO,
  # --batch --no-tty --no-armor, clave sin passphrase
  rpm --addsign "$TMP/convert-rpms/"*.rpm
  rpm -K "$TMP/convert-rpms/"*.rpm | grep -c 'signatures OK'   # assert == nº
  gpg --export --armor > "$TMP/termux-rpm.gpg"

PASO 5 — población de la rpmdb (§4)
  DBREL="/data/data/com.termux/files/usr/var/lib/rpm"   # ABSOLUTO (rpm ≥ 4.18 rechaza relativo)
  $SUDO rpm -ivh --root "$ROOTFS" --dbpath "$DBREL" \
        --nodeps --ignorearch --noscripts --notriggers --nosignature --noverify \
        "$TMP/convert-rpms/"*.rpm "$TMP/project-rpms/"*.rpm
  $SUDO rpm --root "$ROOTFS" --dbpath "$DBREL" --import "$TMP/termux-rpm.gpg"
  verify: rpm -qa --root "$ROOTFS" --dbpath "$DBREL"  (count ≥ 60, gpg-pubkey ≥ 1, dnf5 presente)
  $SUDO chown -R "$(id -u):$(id -g)" "$ROOTFS"

PASO 6 — configuración de dnf5 (verificación + dirs vacíos)
  assert: $USR/etc/dnf/dnf.conf existe
  assert: $USR/etc/yum.repos.d/termux.repo apunta a gh-pages con gpgcheck=1
  mkdir -p $USR/var/lib/dnf $USR/var/cache/dnf $USR/etc/dnf/vars

PASO 7 — SYMLINKS.txt (réplica de create_bootstrap_archive)
  cd "$USR"
  find . -type l -printf '%l←%p\n' | sed 's#^\./##' > SYMLINKS.txt
  count_links=$(wc -l < SYMLINKS.txt)
  find . -type l -delete
  assert: find . -type l | wc -l == 0
  # Nota: symlinks con target ABSOLUTO (/data/data/...) o RELATIVO se registran igual
  # (readlink); la app (y el awk de la wiki) los recrean tal cual.

PASO 8 — zip
  (cd "$USR" && zip -9r "$OUT/bootstrap-aarch64.zip" . -x 'var/cache/dnf/*')
  unzip -l "$OUT/bootstrap-aarch64.zip" | head     # entries SIN prefijo data/, SYMLINKS.txt presente

PASO 9 — verificación estática CI
  - ELF aarch64: patrón "Verify AArch64" de build.yml (file sobre *.so*/ejecutables del zip)
  - ejecutables fuera de bin/|libexec/ → warning/error (R7)
  - imprimir manifest + tamaños; si --keep-staging, no borrar $TMP
```

**Modo offline**: se documenta para reproducibilidad local en Termux (donde correr el
generador completo es posible: bsdtar, rpm, zip existen; la firma necesita la clave
`$HOME/dnf-for-termux-signing-key.asc`). En CI el modo normal (online) es el de referencia.

---

## 6. Workflow `.github/workflows/bootstrap.yml` (diseño)

Modelo: `bootstrap_archives.yml` de termux/termux-packages (build genera el zip →
publish hace `gh release create bootstrap-… + upload`).

```yaml
name: bootstrap
on:
  workflow_dispatch: {}                          # manual
  schedule: [{ cron: '0 3 * * 1' }]              # semanal (lunes 03:00 UTC) — opcional

jobs:
  build:
    runs-on: ubuntu-24.04-arm                    # ⚠️ arm64 OBLIGATORIO (rpmbuild necesita
                                                 #    macros de platform aarch64; lección
                                                 #    de deploy.yml, commit b41589d)
    permissions: { contents: read }
    steps:
      - Checkout (actions/checkout@v5)
      - Instalar herramientas:
          sudo apt-get update && sudo apt-get install -y \
            rpm libarchive-tools zip curl gpg zstd xz-utils file
      - Importar clave de firma (RPM_SIGNING_KEY)     # mismo patrón que deploy.yml; aborta si falta
      - Ejecutar generador:
          env: { SUDO: sudo, RPM_SIGNING_KEY: ${{ secrets.RPM_SIGNING_KEY }} }
          run: bash scripts/generate-bootstrap-dnf5.sh \
                 --out-dir "$GITHUB_WORKSPACE/bootstrap-out"
      - Sanity checks del zip:
          unzip -l; test -f SYMLINKS.txt; conteo rpm -qa (lo hace el script, refuerzo aquí)
      - Upload artifact: actions/upload-artifact@v4
          name: bootstrap-aarch64
          path: bootstrap-out/                 # zip en bootstrap-out/bootstrap-aarch64.zip

  publish:
    needs: [ build ]
    runs-on: ubuntu-latest
    permissions: { contents: write, actions: read }
    steps:
      - Checkout (actions/checkout@v4)
      - Download artifact: actions/download-artifact@v4
          name: bootstrap-aarch64
          path: bootstrap-aarch64/             # zip en bootstrap-aarch64/bootstrap-aarch64.zip
      - Calcular tag:
          # tag = bootstrap-YYYY.MM.DD-rN+dnf5.android-7
          # rN: mayor N existente para la fecha de hoy (gh api releases/tags); si la
          # fecha cambia → r1.
      - gh release create "$TAG" bootstrap-aarch64/bootstrap-aarch64.zip \
            --title "Bootstrap archives for Termux application (dnf5.android-7)" \
            --notes "<manifest + sha256 + instrucciones>"
          # necesita GH_TOKEN=${{ github.token }} (permissions contents: write)

```

Consideraciones del diseño:

- **¿x86_64 con `rpm --root` basta?** Para *instalar* en el rootfs sí (no se ejecutan
  binarios del payload), pero el paso de **conversión** (`pkg2rpm.sh` → `rpmbuild
  --target aarch64`) **falla en x86_64** ("No compatible architectures found", probado en
  deploy.yml). Por eso todo el job corre en **`ubuntu-24.04-arm`** (host aarch64 → macros
  nativas + rpm 4.18.1, el mismo major que el dispositivo).
- **Firma**: se firma con el **mismo** `RPM_SIGNING_KEY` del deploy (D3). Si el secret no
  existe, el job falla con mensaje claro (igual que deploy.yml). La opción `--no-sign`
  existe para pruebas locales, pero el bootstrap publicado **siempre firmado**.
- El zip se sube como **artifact y como GitHub Release** (los releases no expiran y son
  la fuente oficial de descarga; artefacto útil para re-descargas en la misma sesión CI).

---

## 7. Decisiones clave

| # | Decisión | Elegida | Alternativas | Razón |
|---|---|---|---|---|
| D1 | Origen del sistema base | `.pkg.tar.zst` de termux-pacman (última versión) → `pkg2rpm.sh` | Recompilar desde fuente; clonar termux-packages | Decisión del usuario: NO reconstruir; conversión de formato probada en deploy.yml |
| D2 | Origen del stack dnf5 | Los **8 .rpm firmados de gh-pages** (resueltos vía `primary.xml`) | Reusar artifacts del CI (build.yml) y convertirlos | Los de gh-pages ya están firmados con la clave del repo y son siempre la versión publicada |
| D3 | Firma de los RPMs convertidos | **Firmar con `RPM_SIGNING_KEY`** + `gpgcheck=1 repo_gpgcheck=1` + clave pre-importada en la rpmdb | `gpgcheck=0` | Consistente con la configuración validada en el dispositivo; sin defaults inseguros; la clave ya vive en el repo (deploy.yml) |
| D4 | Población de la rpmdb | `rpm -i --root` (rpm 4.18 del runner, Ubuntu 24.04) sobre los **.rpm convertidos** | Instalar `.pkg` con pacman en el runner; escribir la db a mano | El runner no tiene pacman; headers/sqlite portables entre 4.16/4.18; esquema idéntico en 24.04 (rpm 4.18.1) |
| D5 | Runner del generador | **`ubuntu-24.04-arm`** | x86_64 | `rpmbuild --target aarch64` necesita macros de platform aarch64 (lección deploy.yml b41589d) |
| D6 | Resolución de versiones de termux-pacman | Parsear `main.db` (metadata oficial del repo) → `%FILENAME%` | Clonar el repo de paquetes; manifest fijo | Ligero, oficial, y da el cierre transitivo por `%DEPENDS%`; manifest de salida para reproducibilidad |
| D7 | Layout del rootfs | `$ROOTFS/data/data/com.termux/files/usr` (zip desde `$USR`) | rootfs con árbol directo `bin/…` | Los payloads de los .rpm usan rutas absolutas `/data/…/usr/…` → `rpm --root` los coloca correctamente; el zip sale relativo a `$PREFIX` |
| D8 | `--dbpath` | **Absoluto** (`/data/data/com.termux/files/usr/var/lib/rpm`) con `--root` | Relativo; `%_dbpath` | Originalmente se eligió el relativo (D8 corregida: **rpm ≥ 4.18 rechaza `--dbpath` relativo** — "arguments to --dbpath must begin with '/'"); el absoluto se une a `--root`, dejando en disco `$ROOTFS/data/data/...` (mismo layout en el zip) |
| D9 | Ejecución de verificación de dnf5 en CI | **NO** (solo estática: `file`, `rpm -qa`, `unzip -l`) | `chroot`/qemu en el runner | Los binarios son aarch64/Android (bionic): no corren en Ubuntu; la validación funcional es on-device (criterio CA-8) |
| D10 | `dnf-hello` en el bootstrap | **Excluido** | Incluirlo | Es el paquete de prueba; el bootstrap mínimo no lo necesita (añadirlo es 1 línea) |

---

## 8. Riesgos y mitigaciones

| # | Riesgo | Impacto si falla | Mitigación / Plan B |
|---|---|---|---|
| R1 | **Esquema sqlite de la rpmdb 4.16 vs 4.18** (incompatibilidad de migración) | dnf5 no lee la rpmdb | Runner Ubuntu **24.04** (rpm 4.18.1, mismo major que el dispositivo 4.18.1-4); verificar `rpm --version` en CI; usar `--dbpath` **absoluto** (rpm ≥ 4.18 lo exige; el relativo de la decisión D8 original fallaba con "arguments to --dbpath must begin with '/'") |
| R2 | **Rutas de los .rpm convertidos** (¿`/data/…/usr/` correctas?) | archivos fuera de lugar en el zip | `pkg2rpm.sh` ya emite rutas absolutas verificadas (deploy.yml); assert en el generador: `$USR/bin/dnf5` existe y `unzip -l` no muestra prefijo `data/` |
| R3 | **`chown` a root como usuario no-root** en `rpm -i --root` | fallo del paso de población | `SUDO` en CI (passwordless); alternativa documentada: `fakeroot rpm` |
| R4 | **Firma falla / clave ausente** | bootstrap sin firma → gpgcheck rompe o hay que degradar | Abortar con error claro si falta `RPM_SIGNING_KEY`; patrón `%__gpg_sign_cmd` + gpg absoluto ya probado (deploy.yml); `--no-sign` solo para desarrollo local |
| R5 | **Resolución de versiones de termux-pacman** (formato de `main.db`, renombrados/subpaquetes) | descarga errónea o paquete no encontrado | Parseo de `%FILENAME%` oficial + `sort -V`; fail-fast con mensaje del nombre y versión; fallback `main.db.tar.gz`; manifest de salida para auditoría |
| R6 | **Sin `ca-certificates`** → dnf5/librepo no resuelven https de gh-pages | primer `dnf5 repolist` falla | `ca-certificates` en el set curado C + verificación https con curl en CI |
| R7 | **Ejecutables fuera de `bin/|libexec/`** pierden el bit de ejecución al extraer (la app solo chmod 0700 a `bin/`, `libexec`, …) | comandos no ejecutables | Auditoría en CI: `find $USR -type f -perm /111` fuera de `bin/|libexec/` → error; si aparece un caso legítimo, documentarlo y evaluar parche de la app |
| R8 | **Scripts `%post` que no corren** (los .rpm convertidos no llevan scriptlets; tampoco los .pkg→.rpm) | faltan pasos post-install (keyring, dirs) | El generador crea los dirs de dnf5 explícitamente (§5 PASO 6); documentar que cualquier post-step necesario se hace en tiempo de generación |
| R9 | **Tamaño del zip** (~70-80 paquetes, decenas de MB) | descarga lenta/fallos en el dispositivo | `zip -9`; excluir `var/cache/dnf/*`; set mínimo (sin `dnf-hello`, sin doc/man); GitHub Release tolera hasta 2 GB |
| R10 | **`LD_PRELOAD` de termux-exec ausente al ejecutar dnf5** | subprocesos de dnf5 sin el preload | El usuario ejecuta dnf5 desde una shell Termux (bash/dash ya pre-cargan `libtermux-exec.so`); los .rpm convertidos no tienen scriptlets → sin subprocesos críticos. Riesgo bajo, documentado |
| R11 | **El repo gh-pages solo tiene 8 paquetes**: tras el bootstrap, `dnf5 install` solo puede instalar lo que exista en el repo | el sistema base es estático hasta que el ecosistema crezca | **FUERA DE ALCANCE** (decisión del usuario): la conversión del ecosistema completo a RPM es el siguiente hito (REPORT.md §7). Nota para el orquestador |
| R12 | **Coexistencia de symlinks en la rpmdb**: el registro de rpm incluye symlinks que no estarán en el zip (la app los recrea) | `rpm -V` reportaría ficheros ausentes (cosmético) | Aceptado; documentar; no afecta instalaciones (dnf5 no verifica por defecto) |

---

## 9. Criterios de aceptación verificables (para el builder)

| # | Criterio | Cómo se verifica |
|---|---|---|
| CA-1 | El generador corre en CI (`ubuntu-24.04-arm`) y produce `bootstrap-aarch64.zip` | Job `build` verde + artifact descargable |
| CA-2 | Entries del zip relativos a `$PREFIX` | `unzip -l` no muestra ningún `data/` en los paths; empiezan por `bin/ etc/ lib/ …` |
| CA-3 | `SYMLINKS.txt` presente en la raíz del zip y líneas `target←link` | `unzip -p bootstrap-aarch64.zip SYMLINKS.txt | head`; nº líneas == nº symlinks eliminados (assert del script) |
| CA-4 | rpmdb poblada | `rpm -qa --root $ROOTFS --dbpath …` ≥ 60 paquetes; incluye `dnf5-*`, `rpm-*`, `gpg-pubkey-*` |
| CA-5 | Stack completo | los 8 nombres de §2-A en `rpm -qa` |
| CA-6 | Todo ELF es aarch64 | patrón "Verify AArch64" de build.yml sobre el contenido del zip |
| CA-7 | Config de dnf5 correcta | `etc/dnf/dnf.conf` y `etc/yum.repos.d/termux.repo` existen en el zip; `termux.repo` apunta a gh-pages con `gpgcheck=1` |
| CA-8 | **On-device (aceptación final, manual asistida)** | flujo de la wiki: crear `usr-n/` junto a `usr/`, descomprimir, recrear symlinks con el awk, sesión FAILSAFE, `rm -fr usr/; mv usr-n/ usr/`; abrir sesión nueva → `dnf5 --version` OK, `dnf5 repolist` muestra `termux`, `dnf5 -y install dnf-hello` funciona con `gpgcheck=1` |
| CA-9 | Reproducibilidad | `manifest.txt` (nombre|versión|origen|sha256) generado y publicado en el release notes |

---

## 10. Notas para el Orquestador

1. **Alcance**: este diseño cubre solo el generador + workflow. La integración del build
   system termux que genere RPMs nativos, y la conversión del ecosistema completo a RPM
   para que `dnf5 install` pueda gestionar el sistema entero, son **hitos posteriores**
   (R11).
2. **Dependencia de secretos**: el workflow necesita `RPM_SIGNING_KEY` (ya configurado
   según PROGRESS.md Fase 1.3). Si el orquestador prefiere no firmar el bootstrap, cambiar
   D3 a `gpgcheck=0` y quitar el paso de firma (más simple, menos seguro).
3. **Orden de implementación sugerido** (para el planificador):
   - T1: `scripts/generate-bootstrap-dnf5.sh` (pasos 0-3 + 8: descarga+conversión+zip, sin
     firma/rpmdb) → probar localmente en Termux con un subset pequeño.
   - T2: pasos 4-5 (firma + rpmdb) → CI verde en `ubuntu-24.04-arm`.
   - T3: `bootstrap.yml` (build + publish con tag de revisión).
   - T4: validación on-device CA-8 (requiere el dispositivo del usuario).
4. **Paralelismo con deploy.yml**: el generador reutiliza `pkg2rpm.sh` y el patrón de
   firma de `deploy.yml`; no duplicar lógica (extraer funciones compartidas a
   `scripts/lib-rpm-common.sh` si el builder lo ve limpio).
5. Este documento reemplaza/amplía la sección de bootstrap del esquema conceptual
   (`esquema.md`) y queda como spec de referencia para el builder.
