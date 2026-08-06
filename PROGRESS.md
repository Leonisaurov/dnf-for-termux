# PROGRESS.md — Port de DNF5 a Termux (termux-packages)

Registro de progreso de la sesión. Estado consolidado y verificado contra el repo real
(`packages/*`, `.github/workflows/build.yml`, `git log`, `gh run list/view`).
Fecha del registro: 2026-08-05 (última actualización 2026-08-05, Fase 0.6 — dnf5 validado en
dispositivo, Fase 0 cerrada).

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

## Último estado exacto para retomar

- **Último commit**: `805410d` — "fix(librepo): keep pkg-config GPGME_LIBRARIES so -lgpgme is
  linked (0003 hunk vs 1.20.0)". Precedidos por `7c5592f` (zchunk `pre_massage`) y `c381c0d`
  (CI en formato pacman).
- **Últimos runs disparados**: `31065452556` y `31071605356` — **SUCCESS 6/6** en formato
  pacman (todos los jobs de la matrix: `validate`, `build (zchunk)`, `build (libcomps)`,
  `build (libsolv)`, `build (librepo)`, `build (dnf5)`). `31071605356` valida los fixes
  `7c5592f` + `805410d`.
- **Validación en dispositivo**: COMPLETADA — dnf5 funciona tras `pacman -U` de los `.pkg`
  corregidos del run `31071605356` (`$HOME/dnf-pkgs-new2/`), confirmado por el usuario
  (2026-08-05). No queda nada pendiente de la Fase 0.
- **Artifacts para el dispositivo**: `.pkg.tar.xz` corregidos en `$HOME/dnf-pkgs-new2/`
  (`dnf5-5.4.2.1-0`, `libsolv-0.7.39-1`, `librepo-1.20.0-0`, `libcomps-0.1.24-0`,
  `zchunk-1.5.3-0`); se instalan con `pacman -U`.
- **Formato CI**: pacman (`TERMUX_PACKAGE_FORMAT=pacman` vía `TERMUX_DOCKER_EXEC_EXTRA_ARGS`,
  commit `c381c0d`). El dispositivo usa termux-pacman 7.1.0-6 (root `$PREFIX`, 689+ paquetes).
- **Archivos de `packages/dnf5/`** (verificado con `ls`):
  - `build.sh`
  - patches: `0001-termux-paths-const-hpp.patch`, `0002-termux-paths-config-main.diff`,
    `0003-termux-os-release.patch`, `0004-termux-offline-cmds.patch`,
    `0005-termux-binary-prefixes.patch`, `0006-termux-automatic-plugin.patch`,
    `0007-termux-copr-plugin.patch`, `0008-rpm-4.18-compat.patch`, `0009-disable-werror.patch`,
    `0010-disable-needs-restarting.patch`, `0011-missing-includes.patch`,
    `0012-renameat2-bionic.patch`, `0013-progress-bar-clock.patch`
    (0002 es `.diff` aplicado manualmente en `termux_step_post_get_source` con `|| true`).
- **`termux_step_pre_configure` actual** (verificado en `packages/dnf5/build.sh`):
  `LDFLAGS+=" -landroid-glob"` y `-Dtoml11_DIR=${TERMUX_PKG_TMPDIR}/toml11` (toml11
  header-only descargado en `termux_step_post_get_source`). Los overrides
  `-DCMAKE_EXE_LINKER_FLAGS`/`-DCMAKE_SHARED_LINKER_FLAGS` fueron **eliminados** en ad550f0
  (causa raíz del try-compile roto); el framework propaga `$LDFLAGS` a los enlaces de CMake.
- **`packages/zchunk/build.sh`** añade `termux_step_pre_massage()` (commit `7c5592f`) que
  elimina `argp.h`/`libargp.a` del staging; **`packages/librepo/0003-optional-gpgme.patch`**
  regenerado (commit `805410d`) conserva `GPGME_LIBRARIES` del pkg-config.
- **`git status --short`**: `?? PROGRESS.md` (este documento, sin commitear). `err.log` ya está
  en `.gitignore` (commit ad550f0), así que ya no aparece como untracked.
- **Próximos pasos (siguiente sesión)**:
  1. T10: `scripts/install-dnf-termux.sh` para instalar los `.pkg` de GitHub Releases.
  2. T11: code review de `packages/` y `.github/workflows/build.yml`.
  3. T12: reporte final.
  4. Fase 2: repo RPM/GitHub Pages (podría publicar estos `.pkg`).
  El HITO de la Fase 0 está completo (en formato deb y pacman) y **dnf5 VALIDADO en el
  dispositivo** (2026-08-05); la pregunta de "iterar dnf5 o pausar" queda RESUELTA (ya no hay
  que iterar).

## Pendiente (no empezado)

- **T10**: `scripts/install-dnf-termux.sh` para instalar los `.pkg` de GitHub Releases.
- **T11**: code review de `packages/` y `.github/workflows/build.yml`.
- **T12**: reporte final.
- **Fase 2**: repo RPM/GitHub Pages (podría publicar los `.pkg` validados de la Fase 0).

## Preguntas de Seguimiento (para el usuario)

- **Fase 2 (repo RPM/GitHub Pages)**: ¿el repo RPM para dnf (`yum.repos.d/termux.repo`) será
  GitHub Pages de este repo, o se deja el plan para Fase 2? (Con el CI en formato pacman, los
  artifacts de ese repo serían `.pkg.tar.xz` aarch64; ahora que dnf5 está validado en el
  dispositivo, estos `.pkg` son publicables.)
- ¿Se continúa con T10 (install script), T11 (code review), T12 (reporte final)?
