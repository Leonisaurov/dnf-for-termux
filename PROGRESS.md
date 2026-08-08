# PROGRESS.md — Port de DNF5 a Termux (termux-packages)

Registro de progreso de la sesión. Estado consolidado y verificado contra el repo real
(`packages/*`, `.github/workflows/build.yml`, `scripts/mkrepo.sh`, `git log`,
`gh run list/view`).
Fecha del registro: 2026-08-07 (última actualización 2026-08-07, Fase 1.0 — dnf5 funcional y
sin errores en el dispositivo: `createrepo_c` portado a Termux y repo local/remoto resueltos;
previas: Fase 0.9 — repo RPM remoto en GitHub Pages operativo y resoluble desde la URL; Fase
0.8 — dnf5 funcional en el dispositivo: instala y ejecuta RPMs reales; Fase 0.7 — repo RPM
local funcional; Fase 0.6 — dnf5 validado en dispositivo).

## Resumen ejecutivo

El proyecto porta el stack de DNF5 a Termux usando el sistema oficial termux-packages.
El objetivo de la Fase 0 era demostrar que los binarios se cross-compilan a aarch64 real
(el intento previo del proyecto compilaba todo para x86_64 y se rompía al pasar a aarch64).
ESTADO: 5/5 paquetes del stack compilan y verifican AArch64 en CI (zchunk, libcomps, libsolv,
librepo, dnf5 5.4.2.1 ✅). Se iteraron 36 runs de CI en la sesión (33 con fallo, 3 exitosos
con la matriz previa a dnf5); los 13 runs de la iteración de dnf5 están documentados con su
causa raíz en la tabla más abajo. El último fix exitoso (ad550f0) eliminó la causa raíz del
  fallo del try-compile: las comillas dobles heredadas al shell de CMake desde los overrides
  `-DCMAKE_EXE_LINKER_FLAGS`/`-DCMAKE_SHARED_LINKER_FLAGS` vía `TERMUX_PKG_EXTRA_CONFIGURE_ARGS`.
  Después del HITO, la sesión continuó (Fase 0.6): el CI pasó a emitir paquetes **PACMAN**
  (no deb) y una prueba real en dispositivo reveló 2 bugs de empaquetado/enlazado, ya fijados
  (commits `7c5592f`, `805410d`), validados en CI y **confirmados en el dispositivo: dnf5
  arranca y funciona** (2026-08-05, `.pkg` del run `31071605356`). La Fase 0 queda CERRADA de
  verdad (ver sección "Fase 0.6").
  Después (Fase 0.7): se creó un **repo RPM local funcional** (`$HOME/dnf-repo/`, 6 RPMs
  convertidos on-device con rpmbuild desde los `.pkg`, `AutoReqProv: no`) con `repodata/`
  generada por el nuevo `scripts/mkrepo.sh` (commit `4bfb93e`), y la cadena repo→repoquery fue
  validada contra el dnf5 5.4.2.1 real del dispositivo (ver sección "Fase 0.7").
  Y después (Fase 0.8, 2026-08-06): **HITO — dnf5 INSTALA y EJECUTA RPMs reales en el
  dispositivo**. `dnf5 --disablerepo='*' install ./dnf-hello-1.0-1.aarch64.rpm` + ejecución de
  `dnf-hello` confirmada por el usuario; ciclo completo cerrado de verdad. Se requirió un **rpm
  4.18.1-2 patcheado** (`termux-rootless-unpack.patch`, commits `ac354d0`, `3c6532b`,
  `197f036`) horneado en `librpm.so`, validado por el run `31221704266` (7/7 jobs success) e
  instalado en el dispositivo (ver sección "Fase 0.8").
  Y después (Fase 0.9, 2026-08-06/07): la **Fase 2 quedó INICIADA** con un **repo RPM remoto
  OPERATIVO en GitHub Pages** (`https://Leonisaurov.github.io/dnf-for-termux/rpm/`, rama
  `gh-pages` commit `d14d2fc`, metadatos con sha256 idéntico a la `repodata` local) que dnf5
  resuelve desde la URL; el fix `058d61e` de `scripts/mkrepo.sh` **resolvió** el
  `nothing provides rpmlib(...)` (instalaciones desde repo) y `termux.repo` quedó apuntando a la
  URL real con `gpgcheck=0` + dnf5 REVISION=1 (`52528a6`, rebuild en curso). Firma GPG pospuesta
  por decisión del usuario (ver sección "Fase 0.9").

## Stack de paquetes

| Paquete | Versión | Estado CI | AArch64 verificado | .deb |
|---|---|---|---|---|
| zchunk | 1.5.3 | ✅ | ✅ | ✅ |
| librepo | 1.20.0 | ✅ | ✅ | ✅ |
| libcomps | 0.1.24 | ✅ | ✅ | ✅ |
| libsolv | 0.7.39-1 (REVISION=1, `-DENABLE_COMPLEX_DEPS=ON`) | ✅ | ✅ | ✅ |
| dnf5 | 5.4.2.1 | ✅ | ✅ | ✅ |

Nota: libsolv lleva `TERMUX_PKG_REVISION=1` con `-DENABLE_COMPLEX_DEPS=ON` porque dnf5
requiere `solv/pool_parserpmrichdep.h` + `pool_parserpmrichdep()` (ver tabla de runs).

## Arquitectura del proyecto

- **Modelo: repo overlay (NO fork).** El CI clona `termux/termux-packages` (depth 1), copia
  `packages/*` del overlay encima y compila con el sistema oficial.
- **`.github/workflows/build.yml`**:
  - `matrix.pkg: [zchunk, libcomps, libsolv, librepo, dnf5]` con `fail-fast: false`.
  - Job `validate`: `bash -n` sobre todos los `packages/*/build.sh`.
  - Job `build`: step `Materialize` (clona termux-packages, copia overlay, y aplica el tweak
    no-fatal del toolchain `c++/v1` con python regex), step `Build` vía
    `./scripts/run-docker.sh -d ./build-package.sh -I -C -a aarch64 <pkg>`. Para `dnf5`,
    primero compila **nuestro** libsolv (`-DENABLE_COMPLEX_DEPS=ON`) dentro del container.
  - Step `Verify AArch64`: itera TODOS los `*.deb` bajo `termux-packages/`, extrae con
    `dpkg-deb -x` y verifica con `file` que cada ELF (`*.so*` o ejecutable) sea aarch64.
  - Steps `Stage` + `Upload artifact`: sube el `.deb` como artifact `${{ matrix.pkg }}-aarch64`.
- Los `.deb` quedan en `termux-packages/output/` y se suben como artifacts `*-aarch64.zip`.

## Infraestructura CI resuelta (lecciones)

Formato: **Problema → Solución**.

1. **Rutas en container jobs** → `working-directory` no expande variables; usar `$GITHUB_WORKSPACE`
   en `run:` y hacer `cd` en el run (o el patrón oficial `run-docker.sh`).
2. **NDK no encontrado** → los container jobs de GHA usan `$HOME=/github/home` pero la imagen
   guarda el NDK en `/home/builder/lib`; resolver con `ln -sfn /home/builder/lib "$HOME/lib"`.
3. **fuse-overlayfs no disponible en container jobs** → usar `./scripts/run-docker.sh` (patrón
   oficial; inyecta `/dev/fuse` + `CAP_SYS_ADMIN`). (commit 2cfa1f8)
4. **`buildorder.py`** → `DEPENDS` separado por COMAS (no espacios) y nombres de paquetes reales
   (`zstd` NO `libzstd`, `libexpat` NO `expat`). (commits dbc391d, 0eba0a9)
5. **Licencias BSD no están en termux-licenses** → usar `TERMUX_PKG_LICENSE_FILE` apuntando al
   `LICENSE` del source (`LICENSE.BSD` en libsolv, `LICENSE` en zchunk). (commit 0eba0a9)
6. **Pipelines del framework con `patch --silent` pueden fallar mudos** → renombrar el overlay a
   `.diff` y aplicarlo explícitamente en `termux_step_post_get_source` con `|| true`.
   (libcomps: `0001-skip-python-bindings.diff`; dnf5: `0002-termux-paths-config-main.diff`).
   (commits 435aeb3, 34672a8)
7. **Muerte silenciosa en `MAKE_PROGRAM_PATH=$(command -v ninja)` en flujo custom** → replicar el
   flujo normal del framework: `termux_setup_cmake` + `termux_setup_ninja` dentro del
   `termux_step_configure` custom antes de `termux_step_configure_cmake`.
   (commits 38db709, eca1d4f, 6400643)
8. **CMakeLists en subdir (libcomps)** → `termux_step_configure` reasignando
   `TERMUX_PKG_SRCDIR="$TERMUX_PKG_SRCDIR/libcomps"`. (commit 0eba0a9)
9. **Toolchain `c++/v1` tweak silencioso** → parchear el script clonado en el step `Materialize`
   con python regex (no-fatal), en vez de un patch que era no-op. (commits fc4e54e, b7f3d7e)
10. **No sobrescribir `CMAKE_*_LINKER_FLAGS` desde `TERMUX_PKG_EXTRA_CONFIGURE_ARGS`** → se
    expande con word-splitting y las comillas/espacios rompen el try-compile de CMake; usar
    `LDFLAGS+=` (el framework propaga `$LDFLAGS` a los enlaces de CMake). (commit ad550f0)

## Estado de dnf5 (resuelto)

Historia completa de la iteración, verificada contra `gh run view --log-failed` y
`git log --oneline` (los commits se mapean 1:1 con los runs por timestamp).

### Tabla de runs (13 runs verificados)

| Run ID | Hora (UTC) | Fallo observado (log) | Causa raíz | Fix aplicado (commit) |
|---|---|---|---|---|
| 30616671760 | 08:32 | `reldep.cpp:30: fatal error: 'solv/pool_parserpmrichdep.h' file not found` | libsolv oficial sin `ENABLE_COMPLEX_DEPS` (no instala el header rich deps) | 7badb4e: libsolv con `-DENABLE_COMPLEX_DEPS=ON` + REVISION=1 + job dnf5 compila nuestro libsolv primero |
| 30617866274 | 08:52 | `curl: (22) The requested URL returned error: 503` descargando `foot` 1.27.0 | codeberg caído (foot, fuente-src de ncurses — daño colateral) | — transitorio (resuelto solo) |
| 30619675317 | 09:22 | ídem `503` codeberg (foot) | transitorio | — (retry sin commit) |
| 30620984885 | 09:43 | ídem `503` codeberg (foot) | transitorio | — (retry sin commit) |
| 30622197279 | 10:03 | ídem `503` codeberg (foot) | transitorio | — (retry sin commit) |
| 30623914828 | 10:32 | `config_utils.cpp:67:24: implicit instantiation of undefined template 'std::basic_ostringstream<char>'` | faltan `<sstream>`/`<fstream>` (libc++ NDK r29) | 1904c45: patch 0011-missing-includes (18 archivos) |
| 30627647561 | 11:36 | `Hunk #2 FAILED at 239` (config_main.cpp) + `use of undeclared identifier 'renameat2'` (rotating_file_logger.cpp:192) | overlay 0002 no aplica limpio contra 5.4.2.1 + bionic sin `renameat2` | 34672a8: guard `linux/android` para `renameat2` + regenerar config-main diff para 5.4.2.1 |
| 30630528316 | 12:25 | `progress_bar.cpp:314/321/327/355: invalid operands ... time_point<steady_clock> vs time_point<system_clock>` | mismatch de clocks en progress_bar | f1acb22: patch 0013-progress-bar-clock (unificar a `steady_clock`) |
| 30647948936 | 16:38 | `ERROR: ./lib/libdnf5.so contains undefined symbols` (glob/globfree) | bionic no provee `glob()`/`globfree()` | 989191f: dep `libandroid-glob` + LDFLAGS + CMAKE linker flags |
| 30651241786 | 17:27 | try-compile CMake: `ld.lld: error: unable to find library -landroid-glob` | los flags `-D` reemplazaban el `-L` del framework (no resolvía la lib) | 3d1f2ac: enlazar `libandroid-glob.so` por ruta absoluta |
| 30653857024 | 18:06 | link `libdnf5-cli.so`: `unable to find library -lfmt / -lsmartcols / -ljson-c` | se pierde `-L${TERMUX_PREFIX}/lib` en los enlaces de libs compartidas | d2084b3: CMAKE linker flags con `-L${TERMUX_PREFIX}/lib` + glob por ruta absoluta |
| 30657768918 | 19:05 | try-compile CMake: `/bin/sh: 1: Syntax error: Unterminated quoted string` (en la línea del link del test de compilador) | comillas dobles dentro de `CMAKE_*_LINKER_FLAGS` vía `TERMUX_PKG_EXTRA_CONFIGURE_ARGS` (CMake las hereda literalmente a la shell) | ad550f0: eliminar los overrides `-DCMAKE_*_LINKER_FLAGS` (las comillas dobles heredadas al try-compile eran la causa) |
| 31060791791 | — | ✅ SUCCESS — todos los jobs de la matrix, incluido `build (dnf5)` con `Verify AArch64 architecture` | Causa raíz de los 3 fallos previos (30651241786, 30653857024, 30657768918): los overrides `-DCMAKE_EXE_LINKER_FLAGS`/`-DCMAKE_SHARED_LINKER_FLAGS` vía TERMUX_PKG_EXTRA_CONFIGURE_ARGS eran innecesarios y dañinos (pierden el -L del framework y las comillas dobles rompen el try-compile) | Fix aplicado: ad550f0 (eliminar los overrides; conservar `LDFLAGS+=" -landroid-glob"`, patrón oficial del framework) |

### Resumen cronológico de los fixes (commits verificados en `git log`)

1. `pool_parserpmrichdep.h` faltante → **7badb4e**: libsolv con `-DENABLE_COMPLEX_DEPS=ON` +
   `TERMUX_PKG_REVISION=1`; el job `dnf5` de CI compila nuestro libsolv antes de dnf5.
2. HTTP 503 codeberg (`foot`, fuente-src de ncurses — daño colateral) → **transitorio**, resuelto
   (4 runs de retry con el mismo 503 hasta que codeberg volvió).
3. `config_utils.cpp` sin `<sstream>` → **1904c45**: patch `0011-missing-includes` (18 archivos).
4. `renameat2` (bionic) → **34672a8**: patch `0012-renameat2-bionic` (guard linux/android) +
   regeneración del diff `0002-termux-paths-config-main` para 5.4.2.1.
5. Mismatch de clocks en progress_bar → **f1acb22**: patch `0013-progress-bar-clock`
   (`steady_clock`).
6. Symbols `glob`/`globfree` sin resolver → **989191f**: dep `libandroid-glob` + LDFLAGS +
   flags de enlace CMake.
7. Try-compile roto (los flags reemplazaban el `-L` del framework) → **3d1f2ac**: ruta absoluta
   del `.so` de libandroid-glob.
8. Link de `libdnf5-cli` sin `-L` del prefix (`unable to find -lfmt/-lsmartcols/-ljson-c`) →
   **d2084b3**: CMAKE linker flags con `-L${TERMUX_PREFIX}/lib` + glob por ruta absoluta.
   → **Validado: rompe el try-compile** (comillas dobles heredadas literalmente).
9. Try-compile roto por las comillas dobles de los overrides → **ad550f0** (último): eliminar
   los overrides `-DCMAKE_EXE_LINKER_FLAGS`/`-DCMAKE_SHARED_LINKER_FLAGS` de
   `termux_step_pre_configure` (causa raíz del try-compile roto); `LDFLAGS+=" -landroid-glob"`
   basta porque el framework termux-packages propaga `$LDFLAGS` a los enlaces de CMake (vía env
   `LDFLAGS` → `CMAKE_*_LINKER_FLAGS_INIT` y vía `-DCMAKE_LINKER=... $LDFLAGS`), patrón
   verificado en polybar/putty.
   → **NOTA IMPORTANTE para el futuro**: el diagnóstico previo de la sesión era erróneo ("el
   framework NO propaga $LDFLAGS a los targets cmake") y llevó a los overrides que rompían el
   try-compile; el run 30647948936 (sin esos `-D` flags) ya pasaba try-compile y enlazaba.

**Conclusión**: dnf5 compila/enlaza/verifica AArch64 en CI (run 31060791791, commit ad550f0) →
**HITO 5/5**. La Fase 0 (demostrar cross-compilación aarch64 real de todo el stack) queda
COMPLETADA.

## Fase 0.6 — CI en formato pacman y validación real en dispositivo

Sesión posterior al HITO 5/5 (2026-08-05/06). El CI pasó de emitir `.deb` a emitir paquetes
**PACMAN** (`.pkg.tar.xz`, el formato real del dispositivo) y una prueba real del usuario en
Termux reveló 2 bugs de empaquetado/enlazado, ya fijados y validados en CI. Estado verificado
contra `git log`, `.github/workflows/build.yml`, `packages/*/build.sh` y `gh run`.

### Runs recientes

| Run ID | Formato | Resultado | Artifacts | Notas |
|---|---|---|---|---|
| 31060791791 | deb | ✅ SUCCESS 6/6 | `.deb` (artifacts corruptos) | dnf5-aarch64 contenía `freetype-static`; librepo/zchunk contenían `zchunk-static` (duplicado) → `.deb` de dnf5 irrecuperable; motivó la migración a pacman |
| 31065452556 | pacman | ✅ SUCCESS 6/6 | `.pkg` correctos | commit `c381c0d`; `dnf5-5.4.2.1-0`, `libsolv-0.7.39-1`, `librepo-1.20.0-0`, `libcomps-0.1.24-0`, `zchunk-1.5.3-0` |
| 31071605356 | pacman | ✅ SUCCESS 6/6 | `.pkg` corregidos | valida los fixes `7c5592f` (zchunk) + `805410d` (librepo); copiados a `$HOME/dnf-pkgs-new2/` |

### Migración a PACMAN (commit `c381c0d`)

- `build.yml` inyecta `TERMUX_PACKAGE_FORMAT=pacman` al container vía
  `TERMUX_DOCKER_EXEC_EXTRA_ARGS` (`run-docker.sh` lo pasa a `docker exec`).
- Fix del staging de artifacts: `find -name "${{ matrix.pkg }}-[0-9]*.pkg.tar.*"` en vez del
  `find | head -1` anterior, que subía el primer `.deb` de cualquier dependencia.
- El dispositivo usa **PACMAN** (termux-pacman 7.1.0-6, root `$PREFIX`, 689+ paquetes), NO
  apt → los `.pkg` se instalan con `pacman -U`.

### Bugs revelados por la prueba real en dispositivo

| Bug | Síntoma | Causa raíz | Fix (commit) | Verificación |
|---|---|---|---|---|
| A — conflicto de empaquetado (zchunk) | conflicto de archivos con el paquete `argp` de Termux | zchunk bundlea `argp.h`/`libargp.a` (bionic no trae argp) y meson los instala en el paquete | `7c5592f`: `termux_step_pre_massage()` en `packages/zchunk/build.sh` elimina `$TERMUX_PKG_MASSAGEDIR/$TERMUX_PREFIX_CLASSICAL/include/argp.h` y `.../lib/libargp.a` | hook verificado en build-package.sh master (L390-393 def, L790 invocación); run `31071605356` 6/6; sin `DEPENDS argp` (bundle estático en los CLIs, el runtime no lo necesita) |
| B — enlazado (librepo) | `CANNOT LINK EXECUTABLE "dnf5": cannot locate symbol "gpgme_data_new_from_fd"` | `librepo.so` tenía 23 símbolos `gpgme_*` UND sin `DT_NEEDED libgpgme.so`; el patch `0003-optional-gpgme.patch` sobrescribía `GPGME_LIBRARIES` con `GPGME_VANILLA_LIBRARIES` (vacía en la ruta pkg-config) | `805410d`: patch 0003 regenerado contra el tag 1.20.0 (0 fuzz, `git apply --check` OK) con guard `IF(GPGME_VANILLA_LIBRARIES)` + `FIND_PACKAGE(Gpgme QUIET)` + `SET(USE_GPGME OFF)` | run `31071605356`: `DT_NEEDED libgpgme.so` presente en `librepo.so` |

### Auditoría UND/NEEDED de los 37 ELF de los 5 `.pkg`

- `librepo.so` era el ÚNICO `.so` roto (Bug B).
- `libdnf5.so`, `libdnf5-cli.so`, `libsolv.so`, `libsolvext.so`, `libcomps.so`, `libzck.so`,
  `bin/dnf5` y todos los binarios/plugins tienen **0 UND sin cobertura**.
- Los 8 cmd plugins resuelven `dnf5::*` contra el ejecutable (mecanismo normal).

### Estado de la prueba en dispositivo (COMPLETADO — VALIDADO)

- **2026-08-05 — dnf5 VALIDADO en el dispositivo.** El usuario reinstaló los `.pkg` corregidos
  de `librepo` y `zchunk` (run `31071605356`, `$HOME/dnf-pkgs-new2/`) con `pacman -U` y
  confirmó que `dnf5` arranca y funciona ("Funciona! Ya lo instale").
- Cadena de bugs resuelta documentada arriba: Bug A (zchunk, conflicto `argp.h`, fix
  `7c5592f`) y Bug B (librepo, `gpgme_data_new_from_fd`, fix `805410d`).
- Historial de la instalación: primero se instalaron los 5 `.pkg` con un zchunk local saneado
  manualmente (re-empaquetado sin `argp.h`, `.MTREE` regenerado y backup `.orig`); después se
  reinstalaron los `.pkg` corregidos de `librepo` y `zchunk` con `pacman -U`.
- Contexto de la instalación: `rpm 4.18.1-2` instalado desde repos; lock huérfano `db.lck`
  borrado por el usuario; `pacman.conf` intacto (SigLevel `DatabaseRequired PackageOptional` /
  `LocalFileSigLevel Optional` → `.pkg` sin firma OK).

**Conclusión (Fase 0.6)**: ciclo completo cerrado — cross-compilación **aarch64 real** →
`.pkg.tar.xz` → `pacman -U` → **dnf5 funciona**. La Fase 0 queda CERRADA de verdad
(cross-compilación + empaquetado pacman + instalación real + ejecución real de dnf5). La
Fase 2 (repo RPM/GitHub Pages) sigue pendiente y podría publicar estos `.pkg`.

## Fase 0.7 — Repo RPM local y "cómo se le ponen paquetes" a dnf5

Sesión posterior a la validación de la Fase 0.6 (2026-08-05). Con dnf5 5.4.2.1 ya ejecutándose
en el dispositivo, esta fase responde operativamente a la pregunta "¿cómo se le ponen paquetes
a dnf5 en Termux?": se creó un repo RPM local y se validó la cadena repo→repoquery contra el
propio dnf5. Estado verificado contra `git log`, `scripts/mkrepo.sh`,
`ls $HOME/dnf-repo/` y `$PREFIX/etc/yum.repos.d/`.

### Repo RPM local funcional: `$HOME/dnf-repo/`

Se creó `$HOME/dnf-repo/` con 6 RPMs y `repodata/` completa. Los 5 RPMs del stack se
**convirtieron on-device** desde los `.pkg` con `rpmbuild` (`AutoReqProv: no`); el 6º
(`dnf-hello`) es un paquete de prueba.

| RPM | Versión | Origen | Arch |
|---|---|---|---|
| dnf-hello | 1.0-1 | paquete de prueba (hello world de dnf) | aarch64 |
| zchunk | 1.5.3-0 | convertido desde `.pkg` | aarch64 |
| libcomps | 0.1.24-0 | convertido desde `.pkg` | aarch64 |
| libsolv | 0.7.39-1 | convertido desde `.pkg` | aarch64 |
| librepo | 1.20.0-0 | convertido desde `.pkg` | aarch64 |
| dnf5 | 5.4.2.1-0 | convertido desde `.pkg` | aarch64 |

`repodata/` contiene `repomd.xml` + `primary.xml.gz` + `filelists.xml.gz` + `other.xml.gz`
(nombrados con hash sha256 de su contenido).

### `scripts/mkrepo.sh` (commit `4bfb93e`, feat(scripts))

Genera `repodata/` (repomd.xml + primary/filelists/other `.xml.gz`) **sin `createrepo_c`**
(no existe en Termux). Validado contra el dnf5 5.4.2.1 real del dispositivo:

- `dnf5 repoquery --refresh 'dnf-hello'` → `dnf-hello-0:1.0-1.aarch64`
- `dnf5 repoquery --refresh 'zchunk'` → `zchunk-0:1.5.3-0`
- `dnf5 repolist` muestra el repo `termux-local`

Bug corregido durante la validación: `rpm -qip` vs `rpm -qp` con `IFS='|'` (el `-i` en
`rpm -qp --qf ...` inyectaba la cabecera de formato y rompía el parseo de los campos).

### Cómo se le ponen paquetes a dnf5 (respuesta operativa)

1. **Directo** — `dnf5 install ./<pkg>.rpm`: instala un RPM individual por ruta de archivo.
2. **Repo local** — archivo `$PREFIX/etc/yum.repos.d/termux-local.repo` con:
   ```
   [termux-local]
   name=Termux Local RPM Repository
   baseurl=file://$HOME/dnf-repo
   gpgcheck=0
   ```
   y luego `dnf5 install dnf-hello` (o `dnf5 install zchunk`) resuelve e instala por nombre
   desde el repo.

Nota: el repo `termux` del sistema (`$PREFIX/etc/yum.repos.d/termux.repo`,
`baseurl=https://packages.termux.dev/rpm/`, `gpgcheck=1`) sigue siendo un **placeholder 404**;
la pregunta de convertir el ecosistema Termux completo a RPM queda para la Fase 2.

### Herramientas del dispositivo

`rpm`, `rpmbuild`, `rpm2cpio`, `gpg` (GnuPG 2.5.17) y `dnf5` están **completos** en el
dispositivo. `createrepo_c` **NO existe** (mitigado con `scripts/mkrepo.sh`).

**Conclusión (Fase 0.7)**: la cadena "RPMs → `repodata/` → repo `file://` → `dnf5 repoquery`"
funciona de extremo a extremo contra el dnf5 real del dispositivo. El mecanismo operativo para
alimentar dnf5 en Termux queda documentado y validado; la Fase 2 (repo GitHub Pages firmado +
CI que emita RPMs) tiene ahora su base técnica probada.

## Fase 0.8 — dnf5 funcional en el dispositivo (instala y ejecuta RPMs)

Sesión posterior a la Fase 0.7 (2026-08-06). El paso que quedó pendiente en la Fase 0.7
(`dnf5 install` real en el dispositivo) se completó. Estado verificado contra `git log`,
`packages/rpm/`, `.github/workflows/build.yml`, `gh run view 31221704266` y
`ls $HOME/dnf-pkgs-new4/`.

### ✅ HITO — dnf5 INSTALA y EJECUTA RPMs reales en el dispositivo (2026-08-06)

Confirmado por el usuario en el dispositivo:

```
dnf5 --disablerepo='*' install ./dnf-hello-1.0-1.aarch64.rpm
dnf-hello    # ejecuta correctamente el programa instalado
```

Ciclo completo cerrado de verdad: cross-compilación aarch64 → `.pkg.tar.xz` → `pacman -U` →
`dnf5 install <archivo .rpm>` → ejecución real del paquete instalado.

### Fixes encadenados (commits)

| Commit | Área | Qué hace |
|---|---|---|
| `ac354d0` | dnf5 | patch `0014-termux-bootc-nonfhs.patch`: `bootc::is_writable()` apunta a TERMUX_PREFIX (fix "Failed to stat /usr" en sistema non-FHS) |
| `3c6532b` | rpm | **nuevo `packages/rpm/`** (rpm 4.18.1-2 patcheado, REVISION=2) con `termux-rootless-unpack.patch`: en `lib/fsm.c` `ensureDir()` re-ancla la caminata en TERMUX_PREFIX cuando `open("/")` falla EACCES por SELinux en Android rootless (evita el EBADF); ruta fuera del prefix → rechazo con `failed to open dir %s: %s` |
| `197f036` | CI | `build.yml`: añade `rpm` a la matrix (emite artifact `rpm-4.18.1-2-aarch64.pkg.tar.xz`) |

`packages/rpm/` incluye además `errno.patch` y `goto_declaration.patch` (compat bionic) y
`build.sh` con `LDFLAGS+=" -llua5.4 -landroid-spawn $($CC -print-libgcc-file-name)"`.

### Run CI `31221704266` — 7/7 jobs success

Todos los jobs de la matrix en verde: `validate`, `build (zchunk)`, `build (libcomps)`,
`build (libsolv)`, `build (librepo)`, **`build (rpm)`** y `build (dnf5)` (todos con
`Verify AArch64 architecture`).

Artifacts (copiados a `$HOME/dnf-pkgs-new4/`):

- `rpm-4.18.1-2-aarch64.pkg.tar.xz` — rpm **patcheado**: el `termux-rootless-unpack.patch`
  está **horneado en `librpm.so`** (la cadena `failed to open dir %s: %s` está presente en el
  binario).
- `dnf5-5.4.2.1-0-aarch64.pkg.tar.xz` — dnf5 del run.

**Ambos instalados en el dispositivo.** El rpm parcheado es **OBLIGATORIO**: dnf5 enlaza
`librpm.so` dinámico; el `-I` del CI descarga el rpm oficial de termux-main, ABI-compatible pero
**sin el patch** (rompería la instalación de RPMs en Android rootless).

### PENDIENTE (Fase 2)

1. **Repo RPM remoto publicable**: GitHub Pages + firma GPG + `termux.repo` con URL real (hoy
   apunta a `https://packages.termux.dev/rpm/` → 404).
2. **`createrepo_c`** para el plugin local de dnf5: en CI se puede `apt-get install
   createrepo-c` en el container Ubuntu; en el dispositivo habría que empaquetarlo.
3. **Resolución desde REPO**: persiste `nothing provides rpmlib(...)` para instalaciones desde
   repo; la de archivo directo funciona (el fallback SYSTEMSOLVABLE de libsolv no engrana en
   nuestro build, pendiente de diagnosticar).

**Conclusión (Fase 0.8)**: el flujo de archivo directo (`dnf5 install ./<pkg>.rpm`) funciona de
extremo a extremo en el dispositivo → **HITO alcanzado**. La Fase 2 queda definida como: repo
remoto publicable + resolución por nombre desde repo + `createrepo_c`.

## Fase 0.9 — Repo RPM remoto en GitHub Pages (Fase 2 iniciada)

Sesión posterior a la Fase 0.8 (2026-08-06/07). La Fase 2 (repo RPM remoto publicable) quedó
**INICIADA** y su primera piedra está **OPERATIVA**: un repo RPM remoto en GitHub Pages que dnf5
resuelve desde la URL. Estado verificado contra `git log`, la rama `gh-pages` (commit `d14d2fc`),
`curl` sobre `https://Leonisaurov.github.io/dnf-for-termux/rpm/repomd.xml` (HTTP 200) y las
pruebas del dispositivo.

### ✅ Repo RPM remoto OPERATIVO (GitHub Pages)

- **URL**: `https://Leonisaurov.github.io/dnf-for-termux/rpm/` (rama `gh-pages`, commit
  `d14d2fc`; contenido publicado bajo `rpm/`).
- **Metadatos verificados**: `repomd.xml` responde **200**; los metadatos remotos tienen **sha256
  idéntico** a la `repodata` local corregida.
- **dnf5 resuelve desde la URL remota**: `dnf5 repolist`, `dnf5 repoquery` e
  `dnf5 install --assumeno` desde la URL **OK**. El único fallo anterior era un `$TMPDIR` literal
  **no expandido** en el config del usuario, no un problema del repo.

### Fixes de la Fase 0.9 (commits)

| Commit | Área | Qué hace |
|---|---|---|
| `058d61e` | `scripts/mkrepo.sh` | **fix de `entry_from_dep()`/`parse_evr()`** (operador al inicio de `rest` + EVR por el último guion + `IFS='|'`): las deps versionadas emiten `flags/epoch/ver/rel` → **ARREGLADO el `nothing provides rpmlib(...)`** en instalaciones **desde repo** (libsolv resuelve vía SYSTEMSOLVABLE) |
| `52528a6` | `termux.repo` + dnf5 | `baseurl=https://Leonisaurov.github.io/dnf-for-termux/rpm/` + `gpgcheck=0` (`gpgkey` comentada) + `TERMUX_PKG_REVISION=1` (dnf5 `5.4.2.1-1`). Rebuild en curso (run por verificar) |
| `d14d2fc` | rama `gh-pages` | publica el repo RPM remoto bajo `rpm/` en GitHub Pages |

### Firma GPG del repo (pospuesta por decisión del usuario)

- Clave lista: homedir `$HOME/dnf-gpg`, fingerprint
  `228A7E23748A40F925E7DEECFAAA6809B0971ADC`.
- La firma de `repomd.xml` es **válida con `gpgv`**, pero `repo_gpgcheck=1` en dnf5 la **rechaza**
  (librepo no usa el keyring de rpm).
- Decisión: **`gpgcheck=0` por ahora**; firma GPG **pospuesta** hasta que el usuario la quiera.

### Decisiones del usuario (2026-08-06/07)

- **Hosting**: GitHub Pages (elegido). **Firma**: sin firma por ahora.
- **Siguiente**: rebuild dnf5 (rev 1) → instalar → test `dnf5 install` desde URL; luego
  `createrepo_c` (plugin local de dnf5), T10 (install script), T11 (code review), T12 (reporte).

**Conclusión (Fase 0.9)**: la Fase 2 queda **iniciada** con un repo RPM remoto publicable y
resoluble desde la URL; el bloqueo de resolución desde repo (`nothing provides rpmlib(...)`) está
**resuelto** (commit `058d61e`) y queda por **verificar tras el rebuild** de dnf5 (`52528a6`).

## Fase 1.0 — dnf5 funcional y sin errores (cierre de la Fase 2 operativa)

Sesión posterior a la Fase 0.9 (2026-08-07). La Fase 2 operativa quedó **CERRADA**:
`createrepo_c` fue **portado a Termux** (nuevo `packages/createrepo-c/`) y dnf5 funciona **100%
sin errores** en el dispositivo — el repo local del plugin y el repo remoto de GitHub Pages
quedaron totalmente operativos (resolución e install/reinstall OK). Estado verificado contra
`git log`, `packages/createrepo-c/build.sh`, `.github/workflows/build.yml` (matrix de 7
paquetes), `gh run view 31236591563` y las pruebas del dispositivo.

### ✅ `createrepo_c` 1.2.4 PORTADO a Termux

- Nuevo `packages/createrepo-c/build.sh` (commit `424533d`, feat) + añadido a la matrix del CI
  (commit `c8f88e5`).
- Run CI **`31236591563` — SUCCESS 8/8 jobs**: `validate` + `build (zchunk)`, `build (libcomps)`,
  `build (libsolv)`, `build (librepo)`, `build (rpm)`, **`build (createrepo-c)`** y
  `build (dnf5)`, todos con `Verify AArch64`.

Flags de `TERMUX_PKG_EXTRA_CONFIGURE_ARGS` (validados contra el CMakeLists.txt del tag 1.2.4):

| Flag | Valor | Motivo |
|---|---|---|
| `WITH_LIBMODULEMD` | OFF | evita portar libmodulemd |
| `ENABLE_DRPM` | OFF | sin delta RPM |
| `ENABLE_PYTHON` | OFF | sin bindings de python |
| `ENABLE_BASHCOMP` | OFF | bug upstream ELSEIF en CMakeLists: instalaría bajo `/etc/bash_completion.d` |
| `BUILD_DOC_C` | OFF | `find_package(Doxygen REQUIRED)` rompería el configure sin doxygen |
| `WITH_ZCHUNK` | ON | con zchunk (paquete local del overlay) |

Deps (`TERMUX_PKG_DEPENDS`): `libbz2, libcurl, libxml2, openssl, zlib, glib, liblzma, libsqlite,
rpm (REQUIRED), zstd, zchunk`.

Validación: build local aarch64 (`tcr`) + auditoría de paths — **NO necesita parches de paths**:
cero I/O runtime FHS, temporales vía `g_get_tmp_dir()`.

### ✅ dnf5 100% sin errores en el dispositivo

| Error residual | Resolución |
|---|---|
| `Createrepo_c process exited with code 255` | **resuelto con el port de createrepo-c** |
| `Curl error (37)` de `_dnf_local_nogpgcheck` | **resuelto inicializando el repo local del plugin**: `$PREFIX/var/lib/dnf/plugins/local-nogpgcheck/` con `createrepo_c`; el plugin `[createrepo] enabled=true` de `$PREFIX/etc/dnf/libdnf5-plugins/local.conf` **regenera el repo automáticamente** |

- **Repo remoto GitHub Pages operativo**: `termux.repo` → URL real con `gpgcheck=0`; la
  **resolución desde repo quedó OK** (fix `058d61e` de `scripts/mkrepo.sh`) e **install/reinstall
  OK** en el dispositivo.

### Commits y runs de la Fase 1.0

| Commit | Área | Qué hace |
|---|---|---|
| `424533d` | createrepo-c | **port de createrepo_c 1.2.4** (`packages/createrepo-c/build.sh`, `WITH_LIBMODULEMD=OFF`, validado aarch64) |
| `c8f88e5` | CI | añade `createrepo-c` a la matrix (7 paquetes) |

| Run ID | Resultado | Notas |
|---|---|---|
| `31236591563` | ✅ SUCCESS 8/8 | todos los jobs de la matrix, incluido `build (createrepo-c)` |

**Conclusión (Fase 1.0)**: la Fase 2 operativa queda **cerrada** — dnf5 funciona en el
dispositivo sin errores (repo local del plugin resuelto y repo remoto resoluble con
install/reinstall OK) y `createrepo_c` queda portado a Termux (puede reemplazar a
`scripts/mkrepo.sh` como generador de `repodata/` cuando convenga). Pendientes: firma GPG
(pospuesta), T12 (reporte final) y ecosistema completo (más paquetes RPM en el repo).

## Último estado exacto para retomar

- **Último commit**: `c8f88e5` — `ci(build): add createrepo-c to matrix` (matrix de 7 paquetes).
  Le precede `424533d` — port de **createrepo_c 1.2.4** (`packages/createrepo-c/build.sh`),
  validado por el run `31236591563` (8/8 SUCCESS). Más atrás en la historia reciente:
  `889eb4e`/`af949a1`/`e541907` (review T11: 4 MAJOR resueltos M1/M2/M3/M4), `0568f9e` (install
  script como pacman bootstrap), `52528a6`/`058d61e`/`d14d2fc` (Fase 0.9), `197f036` (rpm en
  matrix), `3c6532b`/`ac354d0` (fixes de la Fase 0.8), `37b5864` (docs: Fase 0.7), `4bfb93e`
  (mkrepo.sh), `c381c0d`/`7c5592f`/`805410d` (Fase 0.6) y `ad550f0` (fix try-compile, HITO 5/5).
- **Último run verificado**: `31236591563` — **SUCCESS 8/8** (Fase 1.0): `validate` + `build
  (zchunk)`, `build (libcomps)`, `build (libsolv)`, `build (librepo)`, `build (rpm)`,
  **`build (createrepo-c)`** y `build (dnf5)`; todos con `Verify AArch64`. Runs previos de
  referencia: `31221704266` (SUCCESS 7/7, Fase 0.8), `31065452556` y `31071605356` (SUCCESS 6/6,
  Fase 0.6).
- **Validación en dispositivo**: COMPLETADA (**Fase 1.0**, 2026-08-07) — **dnf5 100% sin
  errores**: el `Createrepo_c process exited with code 255` quedó **resuelto con el port de
  createrepo-c** y el `Curl error (37)` de `_dnf_local_nogpgcheck` quedó **resuelto
  inicializando el repo local del plugin** (`$PREFIX/var/lib/dnf/plugins/local-nogpgcheck/` con
  `createrepo_c`; el plugin `[createrepo] enabled=true` de
  `$PREFIX/etc/dnf/libdnf5-plugins/local.conf` lo regenera automáticamente). Repo remoto GitHub
  Pages **operativo**: `termux.repo` → URL real con `gpgcheck=0`, **resolución desde repo OK**
  (fix `058d61e`) e **install/reinstall OK**. Histórico: **HITO Fase 0.8** (2026-08-06) —
  `dnf5 --disablerepo='*' install ./dnf-hello-1.0-1.aarch64.rpm` y **`dnf-hello` funciona**
  (requiere el **rpm 4.18.1-2 patcheado**, instalado desde `$HOME/dnf-pkgs-new4/`). Fase 0.7:
  `dnf5 repoquery --refresh` contra `$HOME/dnf-repo/` devuelve `dnf-hello-0:1.0-1.aarch64` y
  `zchunk-0:1.5.3-0`, y `dnf5 repolist` muestra `termux-local`.
- **Artifacts para el dispositivo**: en `$HOME/dnf-pkgs-new4/` (run `31221704266`):
  `rpm-4.18.1-2-aarch64.pkg.tar.xz` (parcheado, **obligatorio**) y
  `dnf5-5.4.2.1-0-aarch64.pkg.tar.xz`; **ambos ya instalados** en el dispositivo con `pacman -U`.
  Históricos de Fase 0.6 (anteriores) en `$HOME/dnf-pkgs-new2/`.
- **Formato CI**: pacman (`TERMUX_PACKAGE_FORMAT=pacman` vía `TERMUX_DOCKER_EXEC_EXTRA_ARGS`,
  commit `c381c0d`). El dispositivo usa termux-pacman 7.1.0-6 (root `$PREFIX`, 689+ paquetes).
- **Archivos de `packages/dnf5/`** (verificado con `ls`):
  - `build.sh`
  - patches: `0001-termux-paths-const-hpp.patch`, `0002-termux-paths-config-main.diff`,
    `0003-termux-os-release.patch`, `0004-termux-offline-cmds.patch`,
    `0005-termux-binary-prefixes.patch`, `0006-termux-automatic-plugin.patch`,
    `0007-termux-copr-plugin.patch`, `0008-rpm-4.18-compat.patch`, `0009-disable-werror.patch`,
    `0010-disable-needs-restarting.patch`, `0011-missing-includes.patch`,
    `0012-renameat2-bionic.patch`, `0013-progress-bar-clock.patch`,
    `0014-termux-bootc-nonfhs.patch`
    (0002 es `.diff` aplicado manualmente en `termux_step_post_get_source` con `|| true`).
- **`packages/rpm/`** (nuevo, commit `3c6532b`, rpm 4.18.1-2 REVISION=2): `build.sh`,
  `errno.patch`, `goto_declaration.patch` y `termux-rootless-unpack.patch` (re-ancla
  `ensureDir()` de `lib/fsm.c` en TERMUX_PREFIX cuando `open("/")` da EACCES por SELinux en
  Android rootless; ruta fuera del prefix → rechazo `failed to open dir %s: %s`). Se añadió a la
  matrix del CI (commit `197f036`).
- **`termux_step_pre_configure` actual** (verificado en `packages/dnf5/build.sh`):
  `LDFLAGS+=" -landroid-glob"` y `-Dtoml11_DIR=${TERMUX_PKG_TMPDIR}/toml11` (toml11
  header-only descargado en `termux_step_post_get_source`). Los overrides
  `-DCMAKE_EXE_LINKER_FLAGS`/`-DCMAKE_SHARED_LINKER_FLAGS` fueron **eliminados** en ad550f0
  (causa raíz del try-compile roto); el framework propaga `$LDFLAGS` a los enlaces de CMake.
- **`packages/zchunk/build.sh`** añade `termux_step_pre_massage()` (commit `7c5592f`) que
  elimina `argp.h`/`libargp.a` del staging; **`packages/librepo/0003-optional-gpgme.patch`**
  regenerado (commit `805410d`) conserva `GPGME_LIBRARIES` del pkg-config.
- **`git status --short`**: solo ` M PROGRESS.md` (este documento, por commitear). PROGRESS.md
  está commiteado en docs previos (`db58129`, `37b5864`, `4269a3b`, `1756fbe`) y el debris de
  investigación (`up-*.sh`, `err.log`) ya está en `.gitignore` (commit `8f3ef23`, que además
  eliminó los `patches/` legados y scripts rotos).
- **Próximos pasos (siguiente sesión)**:
  1. **Firma GPG del repo (opcional, pospuesta)**: clave lista (`$HOME/dnf-gpg`); la firma de
     repomd es válida con `gpgv`, pero dnf5 la rechaza con `repo_gpgcheck=1` (librepo no usa el
     keyring de rpm) → se mantiene `gpgcheck=0` hasta que el usuario la quiera.
  2. **T12: reporte final.**
  3. **Ecosistema completo**: más paquetes RPM en el repo (conversión del ecosistema Termux a
     RPM en CI; los 689+ paquetes del dispositivo tendrían que pasar por rpmbuild/CI).
  4. **Test del install script**: probar `scripts/install-dnf-termux.sh` (commit `0568f9e`,
     reescrito como pacman bootstrap: `gh download` + `pacman -U`) de extremo a extremo.
  La Fase 2 operativa quedó **CERRADA**: **dnf5 funciona 100% sin errores en el dispositivo**
  (2026-08-07, repo local del plugin y repo remoto GitHub Pages resueltos; install/reinstall OK)
  y `createrepo_c` está **portado a Termux** (`packages/createrepo-c/`, commit `424533d`, run
  `31236591563` 8/8). T10/T11 completadas (`0568f9e` y review con 4 MAJOR resueltos:
  `889eb4e` M1/M2, `af949a1` M3, `e541907` M4).

## Pendiente (no empezado)

- **Fase 2 — firma GPG del repo**: clave lista (`$HOME/dnf-gpg`, fingerprint
  `228A7E23748A40F925E7DEECFAAA6809B0971ADC`); la firma de repomd es válida con `gpgv` pero dnf5
  la rechaza con `repo_gpgcheck=1` (librepo no usa el keyring de rpm) → se mantiene `gpgcheck=0`
  hasta que el usuario la quiera.
- **Ecosistema completo**: más paquetes RPM en el repo — el gran reto de la Fase 2 (los 689+
  paquetes del dispositivo tendrían que pasar por rpmbuild/CI y `scripts/mkrepo.sh` o
  `createrepo_c`).
- **T12**: reporte final.
- **Test del install script**: `scripts/install-dnf-termux.sh` (commit `0568f9e`, reescrito como
  pacman bootstrap: `gh download` + `pacman -U`) — implementado, falta probarlo de extremo a
  extremo.

## Preguntas de Seguimiento (para el usuario)

- **(a) Firmado GPG**: decidido `gpgcheck=0` por ahora; la clave está lista
  (`$HOME/dnf-gpg`, fingerprint `228A7E23748A40F925E7DEECFAAA6809B0971ADC`) y la firma de repomd
  es válida con `gpgv`, pero dnf5 la rechaza con `repo_gpgcheck=1` (librepo no usa el keyring de
  rpm) — ¿se retoma la firma cuando el usuario la quiera?
- **(b) Resolución desde REPO (rpmlib)**: **RESUELTO y VERIFICADO** (commit `058d61e`, deps
  versionadas con `flags/epoch/ver/rel`; libsolv resuelve vía SYSTEMSOLVABLE) — install/reinstall
  **OK** desde la URL remota en la Fase 1.0.
- **(c) `createrepo_c`**: **RESUELTO** — portado a Termux (`packages/createrepo-c/`, commit
  `424533d`, run `31236591563` 8/8). Queda elegir si reemplaza a `scripts/mkrepo.sh` como
  generador de `repodata/`.
- **(d) Ecosistema completo**: ¿convertir el resto del ecosistema Termux a RPM en CI? Es el gran
  reto de la Fase 2 (los 689+ paquetes del dispositivo tendrían que pasar por
  rpmbuild/`scripts/mkrepo.sh` o `createrepo_c`).
- **T12 (reporte final)**: T10 y T11 completadas (`0568f9e` install script; review T11 con 4
  MAJOR resueltos: `889eb4e` M1/M2, `af949a1` M3, `e541907` M4) — ¿se continúa con T12 y el
  test del install script?
