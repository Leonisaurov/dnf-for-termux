# PROGRESS.md — Port de DNF5 a Termux (termux-packages)

Registro de progreso de la sesión. Estado consolidado y verificado contra el repo real
(`packages/*`, `.github/workflows/build.yml`, `scripts/mkrepo.sh`, `git log`,
`gh run list/view`).
Fecha del registro: 2026-08-08 (última actualización 2026-08-08, Fase 1.4 — **fix del SIGSEGV
de `dnf5 history list`** con el backport del fix upstream 4.18.2 de rpm (commit `d018e756`):
patch `termux-remove-sqlite3-global-log.patch` (commit `04e5089`) que elimina el **callback
GLOBAL de sqlite3** que rpm 4.18.1 registraba en `lib/backend/sqlite.c`
(`sqlite3_config(SQLITE_CONFIG_LOG, errCb, rdb)` → use-after-free); **REVISION rpm → 4**
(commit `c1bb30e`), rebuild rpm+dnf5 (run `31296859502` SUCCESS) y **VALIDADO en el
dispositivo**: `dnf5 history list` lista las 17 transacciones EXIT=0 sin SIGSEGV con WAL
pendiente real (16 KB)); previa: Fase 1.3 — deploy automatizado del repo RPM en CI
**OPERATIVO**: workflow `deploy.yml` (disparo manual `workflow_dispatch`), run
`31276974715` SUCCESS (8 rpms convertidos y firmados con la clave del secret
`RPM_SIGNING_KEY`, "digests signatures OK", `repodata/` + `repomd.xml` firmado publicados a
gh-pages/rpm/, repo actualizado a `dnf5-5.4.2.1-1`) y **rotación de la clave de firma** (la
privada anterior `228A7E23...` se perdió con el `uninstall --purge`; clave nueva
`E4AC7735...` con backup en `$HOME/dnf-for-termux-signing-key.asc`); previa:
Fase 1.2 — firma de paquetes GPG CERRADA y VALIDADA en el dispositivo: el SIGSYS de rpm
resuelto con un patch de libpopt, los 7 RPMs del repo firmados con `rpm --addsign` en el
dispositivo (`rpm -K` → "digests signatures OK"), repomd re-firmado y publicado en gh-pages,
dnf5 con `gpgcheck=1 repo_gpgcheck=1` sin errores de firma y con la **instalación real
CONFIRMADA** (dnf5 pide la firma de paquetes y del metadata y ambas verificaciones
funcionan); previas:
Fase 1.1 — sistema de firma GPG del repo implementado y validado en el dispositivo:
`termux.repo` con `gpgcheck=1 repo_gpgcheck=1`, auto-import de la gpgkey vía patch 0015 y repo
firmado en gh-pages; Fase 1.0 — dnf5 funcional y sin errores en el dispositivo: `createrepo_c`
portado a Termux y repo local/remoto resueltos; Fase 0.9 — repo RPM remoto en GitHub Pages
operativo y resoluble desde la URL; Fase 0.8 — dnf5 funcional en el dispositivo: instala y
ejecuta RPMs reales; Fase 0.7 — repo RPM local funcional; Fase 0.6 — dnf5 validado en
dispositivo).

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
  Y después (Fase 1.1, 2026-08-08): el **sistema de firma GPG del repo** quedó **IMPLEMENTADO y
  VALIDADO en el dispositivo**: `termux.repo` con `gpgcheck=1 repo_gpgcheck=1` (`9b01c22`),
  `repomd.xml.asc` re-firmado en gh-pages (commit `1874325`), clave pública `termux-rpm.gpg`
  publicada y auto-import de la gpgkey disparado por el patch `0015` (`8509ddb`, librepo de
  Termux emite "Bad GPG signature" en vez de "Signing key not found"); **validado en el primer
  uso**: prompt de importación de la clave → aceptada → instalaciones funcionando vía GPG.
  Además el CI ganó una **caché anti-rebuilds por hash de inputs** (`92eaf7b`, fix `733b9d8`;
  run `31242682232` 8/8 que pobló la caché). Firma GPG CERRADA (ver sección "Fase 1.1").
  Y después (Fase 1.2, 2026-08-08): la **firma de paquetes GPG quedó CERRADA**. El SIGSYS que
  mataba a `rpm --addsign`/`--checksig`/etc. en Android se diagnosticó con `strace -k` y tenía
  su **causa raíz en libpopt** (`src/popt.c` `execCommand()`, ~498-526): llama
  `setgid(getgid()); setuid(getuid())` para soltar privilegios antes de `execvp()`, y el
  seccomp de Android bloquea `__NR_setgid` → SIGSYS (NO era gpg ni rpm). El fix:
  `packages/libpopt/` portado al overlay (REVISION=4 + `src-libpopt.vers.patch` +
  `termux-no-elevated-exec-drop.patch`), que solo suelta privilegios si
  `getuid()!=geteuid()||getgid()!=getegid()` (no-op en Android rootless; idéntico en sistemas
  con setuid real). Commits `84a667f` (paquete) + `a37f14b` (matrix), run CI `31271307345`
  (9/9). Con libpopt 1.19-4 instalado, `rpm --addsign` funciona en el dispositivo → **los 7
  .rpm del repo firmados** (`rpm -K` → "digests signatures OK"), repodata regenerada, repomd
  re-firmado y publicado en gh-pages (`392df86`, HTTP 200); dnf5 con `gpgcheck=1` +
  `repo_gpgcheck=1` resuelve sin errores de firma y la **instalación real está CONFIRMADA en
  el dispositivo** (2026-08-08): dnf5 pide la firma de los paquetes (gpgcheck) y la del
  metadata (repo_gpgcheck) y **ambas verificaciones funcionan** (ver sección "Fase 1.2").
  Además el instalador/desinstalador quedaron **simétricos** (commits `76c828a`/`cb47ebe`): el
  bootstrap instala los **8 paquetes** incl. **libpopt** antes de rpm y el uninstall elimina
  los 8 + config + rpmdb (backup) + caches + staging + clave GPG.
  Y después (Fase 1.3, 2026-08-08): el **deploy + la re-firma del repo RPM quedaron
  AUTOMATIZADOS y OPERATIVOS en CI** (workflow `deploy.yml`, disparo manual
  `workflow_dispatch`): los `.pkg` del último build exitoso de `build.yml` se convierten a
  `.rpm` (`scripts/pkg2rpm.sh`), se firman con la clave del secret `RPM_SIGNING_KEY`, se
  genera `repodata/` (`createrepo_c`), se firma `repomd.xml` y se publica a gh-pages/rpm/ —
  run `31276974715` SUCCESS (8 rpms, 8 "digests signatures OK"; repo actualizado:
  `dnf5-5.4.2.1-1` reemplaza al `-0` desactualizado). Además la **clave de firma fue rotada**
  (la privada anterior `228A7E23...` se perdió con el `uninstall --purge`): clave nueva
  `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9` (mismo UID, sin passphrase) con **backup** en
  `$HOME/dnf-for-termux-signing-key.asc` y el secret `RPM_SIGNING_KEY` configurado; el
  dispositivo quedó con el **stack 8/8 reinstalado y operativo** con la clave nueva (ver
  sección "Fase 1.3").
  Y después (Fase 1.4, 2026-08-08): el **SIGSEGV (139) de `dnf5 history list` quedó
  RESUELTO** — la causa raíz era un **callback GLOBAL de sqlite3** que rpm 4.18.1 registraba
  en el proceso (`lib/backend/sqlite.c`: `sqlite3_config(SQLITE_CONFIG_LOG, errCb, rdb)`,
  líneas 47-52 y 173) y que dereferenciaba `rdb->db_descr` ya liberado → **use-after-free**:
  cualquier otra conexión sqlite (la db de historial `transaction_history.sqlite` de dnf5)
  disparaba el callback sobre memoria reutilizada (`*(pArg+0x28)=0x2`) → `strlen(0x2)` →
  SIGSEGV. Fix: **backport del fix upstream 4.18.2** (commit `d018e756`) con el patch
  `termux-remove-sqlite3-global-log.patch` (commit `04e5089`, elimina `errCb` +
  `sqlite3_config`) y **REVISION rpm → 4** (commit `c1bb30e`); rebuild rpm+dnf5 (run
  `31296859502` SUCCESS) y **VALIDADO en el dispositivo**: `dnf5 history list` **lista las 17
  transacciones EXIT=0 sin SIGSEGV** (test CONCLUSIVO con WAL pendiente real de 16 KB;
  `librpm.so` sin referencias a `sqlite3_config` según readelf) (ver sección "Fase 1.4").

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

## Fase 1.1 — Sistema de firma GPG del repo (validado en dispositivo)

Sesión posterior a la Fase 1.0 (2026-08-08). El **sistema de firma GPG del repo** quedó
**IMPLEMENTADO y VALIDADO en el dispositivo**: el repo RPM remoto ya no se resuelve con
`gpgcheck=0`, sino que queda **firmado** y dnf5 valida metadatos y paquetes con auto-import de
la clave pública. Estado verificado contra `git log`, la rama `gh-pages` (commit `1874325`),
`packages/dnf5/0015-termux-gpg-import-trigger.patch`, `packages/dnf5/build.sh` (bloque
`termux.repo`), `.github/workflows/build.yml` (caché por hash de inputs),
`gh run view 31242682232` y la validación del usuario en el dispositivo.

### ✅ Sistema de firma GPG IMPLEMENTADO y VALIDADO

- **Repo firmado**: `repomd.xml.asc` re-firmado y publicado en gh-pages (commit `1874325`,
  firma válida "Good signature"); clave pública publicada como `rpm/termux-rpm.gpg` en
  `https://Leonisaurov.github.io/dnf-for-termux/rpm/termux-rpm.gpg`.
- **Patch `0015-termux-gpg-import-trigger.patch`** (commit `8509ddb`): dnf5 ahora dispara el
  auto-import de la `gpgkey` (`RepoPgp::import_key()`) cuando el librepo de Termux emite
  **"Bad GPG signature"** (antes solo el mensaje upstream "Signing key not found" — mismatch
  que rompía el import con `repo_gpgcheck=1`). Localizado en `libdnf5/repo/repo_sack.cpp:337`
  y en librepo `gpg_gpgme.c:294` (`LRE_BADGPG` cuando el keyring está vacío).
- **`termux.repo`** (commit `9b01c22`): `gpgcheck=1 repo_gpgcheck=1 gpgkey=.../termux-rpm.gpg`
  (antes `gpgcheck=0` con la `gpgkey` comentada).
- **VALIDADO EN DISPOSITIVO**: primer uso → **prompt de importación de la clave** → aceptada →
  **instalaciones funcionando vía GPG**.

### Caché anti-rebuilds (commits `92eaf7b` + fix `733b9d8`)

Hash de inputs por paquete (`build.sh` + patches del paquete y de sus DEPENDS del overlay) →
`actions/cache@v4`; en **cache-hit se SKIP el build** y el `.pkg` se restaura de la caché como
artifact (regla del usuario: no recompilar dnf5 sin cambios en sus parches); en cache-miss se
compila y el `.pkg` se guarda en `/tmp/cached-pkg`. El run `31242682232` (2026-08-08, **SUCCESS
8/8**) **pobló la caché**; el fix `733b9d8` hace que el paso `Verify AArch64` tolere la
ausencia de `/tmp/cached-pkg` en cache-miss.

### Diagnóstico técnico del GPG

- Homedir de verificación = `<cachedir>/<repoid>-<hash>/pubring` (librepo `LRO_GNUPGHOMEDIR`).
- libdnf5 solo auto-importaba la gpgkey con el mensaje upstream **"Signing key not found"**; el
  librepo de Termux reporta **"Bad GPG signature"** (`gpg_gpgme.c:294`, `LRE_BADGPG`) cuando el
  keyring está vacío → mismatch que rompía el import con `repo_gpgcheck=1`. El patch 0015
  amplía el chequeo para disparar el import también con "Bad GPG signature".

### Commits y run de la Fase 1.1

| Commit | Área | Qué hace |
|---|---|---|
| `8509ddb` | dnf5 | patch `0015-termux-gpg-import-trigger.patch` (auto-import de gpgkey con "Bad GPG signature") |
| `9b01c22` | dnf5 | `termux.repo` con `gpgcheck=1 repo_gpgcheck=1 gpgkey=.../termux-rpm.gpg` (repo firmado) |
| `92eaf7b` | CI | caché por hash de inputs por paquete; cache-hit skipea el build |
| `733b9d8` | CI | fix del paso `Verify`: tolera la ausencia de `/tmp/cached-pkg` en cache-miss |
| `1874325` | gh-pages | re-firma `repomd.xml` (firma válida) + publicación de `rpm/termux-rpm.gpg` |

| Run ID | Resultado | Notas |
|---|---|---|
| `31242682232` | ✅ SUCCESS 8/8 | todos los jobs con `Verify AArch64`; steps `Cache built package` + `Populate cache` (pobló la caché anti-rebuilds) |

**Conclusión (Fase 1.1)**: el sistema de firma GPG del repo queda **CERRADO** — repo firmado y
**validado en el dispositivo** con auto-import de la clave (`gpgcheck/repo_gpgcheck=1`).
Pendientes: automatizar **deploy + firma en CI** (secret con la clave privada), **crecer el
ecosistema** (más RPMs en el repo) y la **firma de paquetes individuales** (opcional, hoy
**CERRADA y VALIDADA** en la Fase 1.2).

## Fase 1.2 — Firma de paquetes GPG (gpgcheck=1 completo, parche libpopt, validado en dispositivo)

Sesión posterior a la Fase 1.1 (2026-08-08). El paso que quedó **opcional** en la Fase 1.1
(**firma de paquetes individuales**) quedó **CERRADO y VALIDADO en el dispositivo**: los **7
RPMs del repo firmados** con `rpm --addsign` en el dispositivo y la **instalación real con
`gpgcheck=1 repo_gpgcheck=1` confirmada** (2026-08-08). El obstáculo que lo bloqueaba — rpm
muriendo con **SIGSYS** en Android — quedó **resuelto con un patch de libpopt** (la causa raíz
NO era gpg ni rpm).
Estado verificado contra `git log`, `packages/libpopt/`, `.github/workflows/build.yml`,
`gh run view 31271307345`, la rama `gh-pages` (commit `392df86`) y el flujo de firma del
dispositivo.

### ✅ Diagnóstico del SIGSYS de rpm (causa raíz: libpopt)

`rpm --addsign`/`--checksig`/etc. morían con **SIGSYS** en Android. El diagnóstico con
`strace -k` localizó el origen **fuera de gpg y fuera de rpm**: **libpopt**
(`src/popt.c` `execCommand()`, ~líneas 498-526) llama `setgid(getgid()); setuid(getuid())`
para soltar privilegios antes de `execvp()`, y el **seccomp de Android bloquea
`__NR_setgid`** → SIGSYS.

### ✅ Fix: `packages/libpopt/` portado al overlay (REVISION=4)

- Commit `84a667f` — **port de libpopt 1.19-4 al overlay** con:
  - `build.sh` con `TERMUX_PKG_REVISION=4` (el oficial de termux-main es 1.19-3).
  - `src-libpopt.vers.patch` (version script).
  - `termux-no-elevated-exec-drop.patch`: en `src/popt.c` `execCommand()`, el bloque
    `HAVE_SETUID` (y el fallback `HAVE_SETREUID`) queda **envuelto en
    `if (getuid() != geteuid() || getgid() != getegid())`** — solo suelta privilegios cuando
    están realmente elevados. En **Android rootless es un no-op** (euid==uid && egid==gid) y
    en sistemas con setuid real el comportamiento es **idéntico** al original.
- Commit `a37f14b` — `ci(build)`: añade `libpopt` a la matrix.
- Run CI **`31271307345`** — **SUCCESS 9/9**: `validate` + `build (zchunk)`,
  `build (libcomps)`, `build (libsolv)`, `build (librepo)`, `build (rpm)`,
  `build (createrepo-c)`, **`build (libpopt)`** y `build (dnf5)`, todos con
  `Verify AArch64`.

### ✅ Resultado: los 7 RPMs del repo firmados y publicados

- **libpopt 1.19-4 instalado** en el dispositivo → **`rpm --addsign` funciona**.
- **Los 7 `.rpm` del repo firmados**: `rpm -K` → **"digests signatures OK"**.
- `repodata/` **regenerada** y `repomd.xml` **re-firmado**; publicado a **gh-pages**
  (commit `392df86` — "publish signed RPM repo (7 packages GPG-signed, repomd re-signed)",
  HTTP 200).
- **dnf5 con `gpgcheck=1` + `repo_gpgcheck=1` resuelve sin errores de firma**.
- **Flujo de firma en dispositivo** (documentado):
  ```
  GNUPGHOME=$HOME/dnf-gpg rpm --addsign --define "_gpg_name dnf-for-termux" *.rpm
  scripts/mkrepo.sh                              # regenerar repodata/
  gpg --detach-sign <repomd.xml>                 # re-firmar repomd.xml
  git push                                       # publicar en gh-pages
  ```
- **VALIDADO EN DISPOSITIVO (2026-08-08)**: la **instalación real con `gpgcheck=1` +
  `repo_gpgcheck=1` quedó CONFIRMADA** — dnf5 pide la firma de los paquetes (gpgcheck) y la
  del metadata (repo_gpgcheck) y **ambas verificaciones funcionan** (test del usuario).

### ✅ Instalación real VALIDADA en el dispositivo (2026-08-08)

- **CONFIRMADO**: con `termux.repo` en `gpgcheck=1 repo_gpgcheck=1`, una instalación real de
  `dnf5 install` desde el repo firmado hace que dnf5 **pida la firma de los paquetes
  (gpgcheck)** y **la firma del metadata (repo_gpgcheck)**, y **ambas verificaciones
  funcionan** (GPG OK).
- Con esto el **sistema de firmas GPG completo opera de extremo a extremo en el dispositivo**:
  metadata firmada (`repomd.xml.asc`, Fase 1.1) + **los 7 paquetes firmados** con
  `rpm --addsign` (Fase 1.2) + **auto-import de la clave pública** (patch `0015`, Fase 1.1).

### Commits y run de la Fase 1.2

| Commit | Área | Qué hace |
|---|---|---|
| `84a667f` | libpopt | **port de libpopt 1.19-4** al overlay (REVISION=4, `src-libpopt.vers.patch`, `termux-no-elevated-exec-drop.patch`) — fix del SIGSYS de rpm en Android |
| `a37f14b` | CI | añade `libpopt` a la matrix |
| `392df86` | gh-pages | publica el repo firmado: 7 RPMs GPG-firmados + `repomd.xml` re-firmado |

| Run ID | Resultado | Notas |
|---|---|---|
| `31271307345` | ✅ SUCCESS 9/9 | todos los jobs de la matrix, incluido `build (libpopt)` con `Verify AArch64` |

**Conclusión (Fase 1.2)**: la **firma de paquetes GPG queda CERRADA y VALIDADA en el
dispositivo** — `rpm --addsign` funciona en el dispositivo (patch de libpopt que evita el
SIGSYS), los **7 RPMs del repo están firmados**, el repo publicado en gh-pages valida con
`gpgcheck=1 repo_gpgcheck=1` sin errores de firma y la **instalación real está CONFIRMADA**
(dnf5 pide la firma de paquetes y metadata y ambas verificaciones funcionan). El **sistema de
firmas GPG completo opera** (metadata + 7 paquetes + auto-import de clave). Pendientes:
**automatizar la re-firma al publicar nuevos paquetes** (deploy + firma en CI) y **crecer el
ecosistema** (más RPMs en el repo).

## Fase 1.3 — Deploy automatizado del repo RPM en CI (y rotación de la clave de firma)

Sesión posterior a la Fase 1.2 (2026-08-08). El paso que quedó **pendiente** en la Fase 1.2
(**automatizar el deploy + la re-firma al publicar nuevos paquetes**) quedó **OPERATIVO**: el
workflow `deploy.yml` convierte los `.pkg` del último build exitoso de `build.yml` a `.rpm`,
los firma con la clave del secret `RPM_SIGNING_KEY`, genera `repodata/` con `createrepo_c`,
firma `repomd.xml` y publica el repo a gh-pages/rpm/. Además la **clave de firma GPG fue
rotada** (la privada anterior se perdió con el `uninstall --purge`). Estado verificado contra
`git log`, `.github/workflows/deploy.yml`, `scripts/pkg2rpm.sh`, `gh run view 31276974715`, el
secret `RPM_SIGNING_KEY`, `$HOME/dnf-for-termux-signing-key.asc` y la reinstalación del
dispositivo.

### ✅ Deploy automatizado OPERATIVO (workflow `deploy.yml`)

- **Disparo**: manual (`workflow_dispatch`) —
  https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/deploy.yml .
- **Pipeline**: convierte los `.pkg` del **último build exitoso** de `build.yml` a `.rpm`
  (`scripts/pkg2rpm.sh`, rpmbuild con `--target $ARCH`), **firma** los RPMs con la clave del
  secret `RPM_SIGNING_KEY`, genera `repodata/` con `createrepo_c`, **firma `repomd.xml`** y
  **publica** a gh-pages/rpm/.
- **Run `31276974715` — SUCCESS**: **8 rpms** firmados (8 "digests signatures OK"); el repo
  publicado quedó **actualizado**: `dnf5-5.4.2.1-1` reemplaza al `-0` desactualizado.

### Commits y run de la Fase 1.3

| Commit | Área | Qué hace |
|---|---|---|
| `5a4879a` | uninstall | `fix(uninstall)`: fingerprint de la **clave nueva** `E4AC7735...` (el uninstall borra la clave nueva) |
| `744387a` | scripts | **`pkg2rpm.sh`**: convierte `.pkg.tar.xz` de Termux a `.rpm` aarch64 |
| `ecb759c` | CI | **`deploy.yml`**: workflow de deploy — convertir, firmar (GPG), generar repodata, publicar repo a gh-pages |
| `4ec3f23` | scripts | `pkg2rpm.sh`: fallback a `/tmp` cuando `TMPDIR` no está definido (compat runner) |
| `fa5a369` | scripts | `pkg2rpm.sh`: `--target $ARCH` a rpmbuild (cross-build aarch64 en runner x86_64) |
| `b41589d` | CI | deploy en runner **arm64** — rpmbuild necesita macros aarch64 nativas (no hay cross en x86_64) |
| `3ec380c` | CI | firma headless: cmd gpg explícito (batch, no-tty, loopback, sin passphrase) |
| `4dca530` | CI | escape de macros rpm en el cmd gpg (`%%{...}`) + drop de pinentry loopback |
| `cd6ce52` | CI | `%__gpg_sign_cmd` definido en `~/.rpmmacros` del runner (las macros se expanden en runtime, no vacías en `--define`) |
| `09af991` | CI | gpg plano en el cmd de firma (evita `%{__gpg}` duplicado) + diagnósticos de firma |
| `03c16dc` | CI | ruta absoluta de gpg vía `command -v` en el cmd de firma (el env de rpm sign no hereda PATH) |
| `3a27f01` | CI | importar la pública en el keyring de rpm local (dbpath) para que `rpm -K` valide las firmas |

| Run ID | Resultado | Notas |
|---|---|---|
| `31276974715` | ✅ SUCCESS | deploy `workflow_dispatch`: 8 rpms firmados (8 "digests signatures OK"), `repodata/` + `repomd.xml` firmado publicados a gh-pages/rpm/ |

### ✅ Rotación de la clave de firma (2026-08-08)

- La **privada anterior** (`228A7E23...`, homedir `$HOME/dnf-gpg`, Fase 0.9) se **perdió** con
  el `uninstall --purge` (borra `$HOME/dnf-gpg`).
- Clave **nueva**: `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9` — **mismo UID, sin passphrase**.
- **Backup** en `$HOME/dnf-for-termux-signing-key.asc`.
- Secret **`RPM_SIGNING_KEY`** configurado en el repo (alimenta el deploy).
- El dispositivo **reimportó la clave nueva** (dnf5 repoquery OK); el uninstall ahora borra la
  clave nueva (commit `5a4879a`).

### ✅ Lecciones del deploy (para futuras iteraciones)

- `rpm --addsign` **no hereda PATH** → usar `command -v gpg` (fix `03c16dc`).
- Macros de firma definidas en **`~/.rpmmacros` del runner** (fix `cd6ce52`).
- **Importar la pública en el keyring de rpm local** (dbpath) para que `rpm -K` valide las
  firmas (fix `3a27f01`).

### ✅ Estado final del dispositivo

- El dispositivo quedó con el **stack 8/8 reinstalado y operativo** con la clave nueva.

**Conclusión (Fase 1.3)**: el **deploy + la re-firma quedan AUTOMATIZADOS y OPERATIVOS en CI**
(workflow `deploy.yml`, run `31276974715` SUCCESS: 8 rpms y "digests signatures OK"; repo
actualizado a `dnf5-5.4.2.1-1` en gh-pages/rpm/) — ya no es manual. La **clave de firma quedó
rotada** (nueva `E4AC7735...`) con **backup** y el secret `RPM_SIGNING_KEY` configurado, y el
dispositivo quedó reinstalado 8/8 y operativo. Pendientes: **T12** (reporte formal) y
**ecosistema completo** (más RPMs en el repo).

## Fase 1.4 — Fix del SIGSEGV de dnf5 history (callback global sqlite3 de librpm)

Sesión posterior a la Fase 1.3 (2026-08-08). El detallito residual del **historial de dnf5**
quedó **RESUELTO**: `dnf5 history list` crasheaba con **SIGSEGV (139)** cuando el WAL de
`transaction_history.sqlite` tenía frames pendientes. La causa raíz estaba en **rpm 4.18.1**
(`lib/backend/sqlite.c`), NO en dnf5, y se resolvió con un **backport del fix upstream
4.18.2**. Estado verificado contra `git log` (commits `04e5089`, `c1bb30e`),
`packages/rpm/` (patch `termux-remove-sqlite3-global-log.patch`, `build.sh` REVISION=4),
`gh run view 31296859502`, `readelf` sobre el `librpm.so` instalado y el test en el
dispositivo.

### ✅ Diagnóstico (gdb + investigación): callback GLOBAL de sqlite3 en rpm

- `dnf5 history list` moría con **SIGSEGV (139)** cuando el WAL de
  `transaction_history.sqlite` tenía frames pendientes.
- **Causa raíz**: `lib/backend/sqlite.c` de rpm 4.18.1 registra un callback **GLOBAL** de
  sqlite3 — `sqlite3_config(SQLITE_CONFIG_LOG, errCb, rdb)` (líneas 47-52 y 173) — que
  dereferencia `rdb->db_descr`. Al ser **config de proceso** y poder estar `rdb` **liberado**
  → **use-after-free**: cualquier **otra** conexión sqlite (la db de historial de dnf5)
  dispara el callback sobre memoria reutilizada (`*(pArg+0x28)=0x2`) → `strlen(0x2)` →
  SIGSEGV.
- NO era un bug de dnf5: el callback global que rpm dejaba registrado en el proceso mataba a
  cualquier proceso que abriera otra db sqlite.

### ✅ Fix: backport del fix upstream 4.18.2 (commit `d018e756`)

- Patch **`packages/rpm/termux-remove-sqlite3-global-log.patch`** (commit `04e5089`):
  backport del fix upstream **"Don't muck with per-process global sqlite configuration"**
  (4.18.2, commit `d018e756`); elimina `errCb` y la llamada `sqlite3_config`.
- **REVISION rpm → 4** (commit `c1bb30e`): `rpm-4.18.1-4` > `4.18.1-3` > el oficial
  `4.18.1-2` de termux-main.
- **Rebuild rpm + dnf5**: run **`31296859502`** — **todos los jobs SUCCESS**. dnf5
  recompiló por el **hash de deps que incluye los patches de rpm**: los paquetes que
  dependen de rpm (dnf5, librepo, libsolv, createrepo-c) recompilan porque su hash incluye
  los patches de rpm — **comportamiento correcto del mecanismo de caché anti-rebuilds**.

### ✅ Validación en el dispositivo

1. **Workaround `wal_checkpoint(TRUNCATE)`** aplicado y verificado (17 transacciones,
   EXIT=0).
2. **`librpm.so` instalado sin referencias a `sqlite3_config`** (verificado con `readelf`).
3. **Test CONCLUSIVO con WAL pendiente real (16 KB)**: `dnf5 history list` **lista las 17
   transacciones EXIT=0 sin SIGSEGV**.

### Commits y run de la Fase 1.4

| Commit | Área | Qué hace |
|---|---|---|
| `04e5089` | rpm | patch `termux-remove-sqlite3-global-log.patch`: elimina el callback global de sqlite3 (`errCb` + `sqlite3_config`) — backport del fix upstream 4.18.2 `d018e756` (fix del SIGSEGV de `dnf5 history list` en WAL recovery) |
| `c1bb30e` | rpm | **REVISION=4** (`4.18.1-4`) — bump por el nuevo patch (fix del SIGSEGV de dnf5 history) |

| Run ID | Resultado | Notas |
|---|---|---|
| `31296859502` | ✅ SUCCESS | rebuild de rpm (REVISION=4) + dnf5 (recompiló por el hash de deps con los patches de rpm); todos los jobs en verde |

**Conclusión (Fase 1.4)**: el **detallito del historial de dnf5 quedó RESUELTO** — el SIGSEGV
(139) de `dnf5 history list` con WAL pendiente quedó **fijado** con el backport del fix
upstream 4.18.2 de rpm (eliminar el callback GLOBAL de sqlite3 que causaba el use-after-free
en procesos que abren otras dbs sqlite) y **validado en el dispositivo**: `dnf5 history list`
lista las 17 transacciones EXIT=0 sin SIGSEGV (test CONCLUSIVO con WAL pendiente real de 16
KB). Pendientes: **T12** (reporte formal) y **ecosistema completo** (más RPMs en el repo).

## Fase 1.5 — dnf-hello restaurado y repo sincronizado

Sesión posterior a la Fase 1.4 (2026-08-08). Estado verificado contra `git log` (commits
`d0045c1`, `b418537`), `gh run view 31303160667` / `31303896890`, la firma del repo en
gh-pages (HTTP 200) y el test en el dispositivo.

### ✅ dnf-hello restaurado como paquete de primera clase

- **`packages/dnf-hello/`** (commits `d0045c1` + `b418537`): **script package** con
  `TERMUX_PKG_SKIP_SRC_EXTRACT`; instala `/usr/bin/dnf-hello` → imprime "dnf5 funciona en
  Termux!".
- Build run **`31303160667`** — **10/10 SUCCESS**; solo dnf-hello compiló (el resto,
  **cache-hit** de la caché anti-rebuilds).

### ✅ rpm-4.18.1-4 sincronizado y repo publicado

- **Dispositivo**: `pacman -Q rpm` = **4.18.1-4**; el **fix del SIGSEGV sigue activo**
  (`dnf5 history list` EXIT=0).
- **Repo remoto**: deploy **`31303896890`** — **9 rpms firmados** incl. `dnf-hello-1.0-1` y
  `rpm-4.18.1-4`; HTTP 200 en gh-pages.

### ✅ Hello world operativo

```sh
dnf5 -y install dnf-hello && dnf-hello
```

## Último estado exacto para retomar

- **Último commit**: `b418537` — `ci(build): add dnf-hello to matrix` (Fase 1.5, dnf-hello en
  la matrix del CI). Le precede `d0045c1` — `feat(dnf-hello): add hello world test package
  (script package, SKIP_SRC_EXTRACT)` (Fase 1.5, restaura **`packages/dnf-hello/`** como
  paquete de primera clase: script package que instala `/usr/bin/dnf-hello` → "dnf5 funciona
  en Termux!"). Le precede `c1bb30e` — `build(rpm): bump revision to 4 (sqlite3 global log
  callback removed — SIGSEGV fix)` (Fase 1.4, **REVISION rpm → 4**). Le precede `04e5089` —
  `fix(rpm): remove global sqlite3 log callback (backport 4.18.2 d018e756)` (el patch
  `termux-remove-sqlite3-global-log.patch` que elimina el **callback GLOBAL de sqlite3** de
  `lib/backend/sqlite.c` de rpm 4.18.1 — **fix del SIGSEGV de `dnf5 history list`** en WAL
  recovery). Más atrás: `3a27f01` — `fix(ci): import pubkey into rpm keyring (local dbpath)
  so rpm -K validates signatures` (Fase 1.3, último fix del pipeline de deploy). Le preceden
  los
  fixes del deploy: `03c16dc` (ruta absoluta de gpg vía `command -v`; el env de firma de rpm
  no hereda PATH), `09af991` (gpg plano en el cmd de firma + diagnósticos), `cd6ce52`
  (`%__gpg_sign_cmd` definido en `~/.rpmmacros` del runner), `4dca530` (escape de macros rpm
  `%%{...}` en el cmd gpg), `3ec380c` (firma headless: batch, no-tty, loopback, sin
  passphrase), `b41589d` (deploy en runner **arm64**; rpmbuild necesita macros aarch64
  nativas), `fa5a369`/`4ec3f23` (`pkg2rpm.sh`: `--target $ARCH` y fallback a `/tmp`),
  `ecb759c` (workflow `deploy.yml`) y `744387a` (`pkg2rpm.sh`); y `5a4879a` — `fix(uninstall)`
  con el fingerprint de la **clave nueva** `E4AC7735...` (rotación de clave). Más atrás:
  `cb47ebe` — `fix(uninstall): remove all 8 stack packages incl. libpopt + clean dnf caches
  and installer staging` (Fase 1.2, desinstalador **simétrico** del instalador). Le preceden
  `76c828a` — `fix(install): include patched libpopt in the bootstrap
  stack (8 packages, before rpm)` (instalador actualizado a los **8 paquetes** incl. **libpopt**
  antes de rpm) y `b3085c0` — `docs(progress)` de la Fase 1.2. Más atrás: `a37f14b` —
  `ci(build): add libpopt to matrix`, `84a667f` — port de libpopt 1.19-4 con
  `termux-no-elevated-exec-drop.patch` (fix del SIGSYS de rpm: solo suelta privilegios si
  `getuid()!=geteuid()||getgid()!=getegid()`) y `392df86` (gh-pages) — **publish signed RPM
  repo (7 packages GPG-signed, repomd re-signed)** (los 7 RPMs del repo firmados con
  `rpm --addsign` en el dispositivo; firma de paquetes GPG CERRADA y VALIDADA). Más atrás:
  `089171c` (uninstall script), `1dfc201` (createrepo-c en el bootstrap),
  `5529481` (docs Fase 1.1), `733b9d8`/`92eaf7b` (caché anti-rebuilds, Fase 1.1),
  `9b01c22`/`8509ddb`/`1874325` (sistema de firma GPG del repo), `4780780` (docs Fase 1.0),
  `c8f88e5`/`424533d` (createrepo-c en matrix y port), `889eb4e`/`af949a1`/`e541907` (review
  T11: 4 MAJOR resueltos M1/M2/M3/M4), `0568f9e` (install script como pacman bootstrap),
  `52528a6`/`058d61e`/`d14d2fc` (Fase 0.9), `197f036` (rpm en matrix),
  `3c6532b`/`ac354d0` (fixes de la Fase 0.8), `37b5864` (docs: Fase 0.7), `4bfb93e`
  (mkrepo.sh), `c381c0d`/`7c5592f`/`805410d` (Fase 0.6) y `ad550f0` (fix try-compile, HITO 5/5).
- **Último run verificado**: build **`31303160667`** — **SUCCESS 10/10** (Fase 1.5, dnf-hello
  en la matrix; solo dnf-hello compiló — el resto **cache-hit**) y deploy **`31303896890`** —
  **SUCCESS** (Fase 1.5, repo sincronizado a gh-pages: **9 rpms firmados** incl.
  `dnf-hello-1.0-1` y `rpm-4.18.1-4`, HTTP 200). **Hello world operativo**:
  `dnf5 -y install dnf-hello && dnf-hello`. Run previo de referencia: `31296859502` —
  **SUCCESS** (Fase 1.4, rebuild de rpm
  REVISION=4 tras el patch del callback sqlite3 + dnf5; todos los jobs en verde). dnf5
  recompiló por el **hash de deps que incluye los patches de rpm** — los paquetes que
  dependen de rpm (dnf5, librepo, libsolv, createrepo-c) recompilan por ese hash:
  **comportamiento correcto de la caché anti-rebuilds**. Run previo de referencia:
  `31276974715` — **SUCCESS** (Fase 1.3, deploy automatizado): 8 rpms convertidos y firmados
  (8 "digests signatures OK"), `repodata/` generada con `createrepo_c`, `repomd.xml` firmado
  y el repo publicado a gh-pages/rpm/ (`dnf5-5.4.2.1-1` reemplaza al `-0` desactualizado).
  Run CI previo de referencia: `31271307345` — **SUCCESS 9/9** (Fase 1.2): todos los jobs de
  la matrix, incluido **`build (libpopt)`** con
  `Verify AArch64` (valida el port que arregla el SIGSYS de rpm). Runs previos de referencia:
  `31242682232` (SUCCESS 8/8, Fase 1.1: caché anti-rebuilds poblada), `31236591563` (SUCCESS
  8/8, Fase 1.0: createrepo-c), `31221704266` (SUCCESS 7/7, Fase 0.8), `31065452556` y
  `31071605356` (SUCCESS 6/6, Fase 0.6).
- **Validación en dispositivo**: COMPLETADA (**Fase 1.4**, 2026-08-08) — **SIGSEGV de `dnf5
  history list` fijado**: `librpm.so` **4.18.1-4** instalado **sin referencias a
  `sqlite3_config`** (verificado con `readelf`) y **test CONCLUSIVO con WAL pendiente real
  (16 KB)**: `dnf5 history list` **lista las 17 transacciones EXIT=0 sin SIGSEGV** (el
  workaround `wal_checkpoint(TRUNCATE)` también quedó verificado: 17 transacciones, EXIT=0).
  Previa (**Fase 1.3**, 2026-08-08) — **rotación de clave de firma**: la privada anterior
  (`228A7E23...`) se perdió con el `uninstall --purge`; la
  clave **nueva** `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9` quedó **importada en el
  dispositivo** (dnf5 repoquery OK) y el **stack 8/8 quedó reinstalado y operativo** con la
  clave nueva. Previa (**Fase 1.2**, 2026-08-08) — **firma de paquetes
  GPG**: libpopt 1.19-4 instalado → **`rpm --addsign` funciona** → **los 7 RPMs del repo
  firmados** (`rpm -K` → "digests signatures OK"), `repodata/` regenerada, `repomd.xml`
  re-firmado y publicado en gh-pages (`392df86`, HTTP 200); dnf5 con
  `gpgcheck=1 repo_gpgcheck=1` resuelve sin errores de firma y la **instalación real está
  CONFIRMADA**: dnf5 pide la firma de los paquetes (gpgcheck) y la del metadata
  (repo_gpgcheck) y **ambas verificaciones funcionan**. El **sistema de firmas GPG completo
  opera** (metadata + 7 paquetes firmados + auto-import de clave). Previa (**Fase 1.1**,
  2026-08-08) —
  **sistema de firma GPG del repo VALIDADO**: primer uso → **prompt de importación de la
  clave** → aceptada → **instalaciones funcionando vía GPG** (`termux.repo` con
  `gpgcheck=1 repo_gpgcheck=1 gpgkey=.../termux-rpm.gpg`; auto-import vía patch `0015`). Previa
  (**Fase 1.0**, 2026-08-07) — **dnf5 100% sin errores**: el
  `Createrepo_c process exited with code 255` quedó **resuelto con el port de createrepo-c** y
  el `Curl error (37)` de `_dnf_local_nogpgcheck` quedó **resuelto inicializando el repo local
  del plugin** (`$PREFIX/var/lib/dnf/plugins/local-nogpgcheck/` con `createrepo_c`; el plugin
  `[createrepo] enabled=true` de `$PREFIX/etc/dnf/libdnf5-plugins/local.conf` lo regenera
  automáticamente). Repo remoto GitHub Pages **operativo** con `gpgcheck=1`, **resolución
  desde repo OK** (fix `058d61e`) e **install/reinstall OK**. Histórico: **HITO Fase 0.8**
  (2026-08-06) — `dnf5 --disablerepo='*' install ./dnf-hello-1.0-1.aarch64.rpm` y
  **`dnf-hello` funciona** (requiere el **rpm 4.18.1-2 patcheado**, instalado desde
  `$HOME/dnf-pkgs-new4/`). Fase 0.7: `dnf5 repoquery --refresh` contra `$HOME/dnf-repo/`
  devuelve `dnf-hello-0:1.0-1.aarch64` y `zchunk-0:1.5.3-0`, y `dnf5 repolist` muestra
  `termux-local`.
- **Artifacts para el dispositivo**: en `$HOME/dnf-pkgs-new4/` (run `31221704266`):
  `rpm-4.18.1-2-aarch64.pkg.tar.xz` (parcheado, **obligatorio**) y
  `dnf5-5.4.2.1-0-aarch64.pkg.tar.xz`; **ambos ya instalados** en el dispositivo con `pacman -U`.
  En la **Fase 1.4** el rpm instalado quedó actualizado a **`rpm-4.18.1-4`** (run
  `31296859502`, con el patch del callback sqlite3). Históricos de Fase 0.6 (anteriores) en
  `$HOME/dnf-pkgs-new2/`.
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
    `0014-termux-bootc-nonfhs.patch`, `0015-termux-gpg-import-trigger.patch`
    (0002 es `.diff` aplicado manualmente en `termux_step_post_get_source` con `|| true`).
- **`packages/rpm/`** (commit `3c6532b`, rpm 4.18.1 **REVISION=4**): `build.sh`,
  `errno.patch`, `goto_declaration.patch`, `termux-rootless-unpack.patch` (re-ancla
  `ensureDir()` de `lib/fsm.c` en TERMUX_PREFIX cuando `open("/")` da EACCES por SELinux en
  Android rootless; ruta fuera del prefix → rechazo `failed to open dir %s: %s`) y
  `termux-remove-sqlite3-global-log.patch` (Fase 1.4, commit `04e5089`: elimina el **callback
  GLOBAL de sqlite3** — backport del fix upstream 4.18.2 `d018e756`; REVISION→4 en el commit
  `c1bb30e`). Se añadió a la matrix del CI (commit `197f036`).
- **`packages/libpopt/`** (nuevo, commits `84a667f` + `a37f14b`, libpopt 1.19 REVISION=4):
  `build.sh` y los patches `src-libpopt.vers.patch` + `termux-no-elevated-exec-drop.patch`
  (envuelve el drop de privilegios de `execCommand()` en
  `if (getuid() != geteuid() || getgid() != getegid())` — no-op en Android rootless, evita el
  SIGSYS de `__NR_setgid` del seccomp; idéntico a upstream en sistemas con setuid real). Añadido
  a la matrix (commit `a37f14b`), run `31271307345` 9/9; **libpopt 1.19-4 instalado en el
  dispositivo** (requisito para `rpm --addsign`).
- **`scripts/install-dnf-termux.sh` y `scripts/uninstall-dnf-termux.sh` (simétricos)**:
  - `install-dnf-termux.sh` (commit `76c828a`): bootstrap del stack dnf5 desde los artifacts
    del CI (formato pacman). Descarga los **8 artifacts** y los instala con `pacman -U
    --needed` en el orden **libpopt → rpm → (libsolv, librepo, libcomps, zchunk,
    createrepo-c) → dnf5** — **libpopt va antes de rpm** porque rpm depende de él y debe
    usarse el artifact **parcheado del SIGSYS** (si no, pacman bajaría el oficial 1.19-3 sin
    parche). Staging en `$HOME/.cache/dnf-termux-install` (persiste para reinstalación
    offline con un directorio). Verificación final con `dnf5 --version`.
  - `uninstall-dnf-termux.sh` (commit `cb47ebe`, espejo del instalador): desinstala los **8
    paquetes** (dnf5, rpm, libpopt, libsolv, librepo, libcomps, zchunk, createrepo-c) con
    `pacman -Rdd --noconfirm` (solo los instalados), elimina la config/runtime de
    dnf5/libdnf5 (`$PREFIX/etc/yum.repos.d`, `$PREFIX/etc/dnf`, `$PREFIX/var/lib/dnf`,
    `$PREFIX/var/cache/dnf`, staging del instalador, `$HOME/.cache/libdnf5`,
    `$HOME/.local/state/dnf5.log`), hace **backup de la rpmdb en `$TMPDIR`** y la elimina, y
    borra la **clave GPG de prueba de `~/.gnupg`**. CONSERVA por defecto `$HOME/dnf-gpg` y
    los stagings de build; `--purge` los elimina también. Verificación final: ninguno de los
    8 paquetes sigue instalado.
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
  1. **T12: reporte formal.**
  2. **Ecosistema completo**: más paquetes RPM en el repo (conversión del ecosistema Termux a
     RPM en CI; los 689+ paquetes del dispositivo tendrían que pasar por rpmbuild/CI).
  El **deploy + la re-firma automatizados en CI** quedó **RESUELTO** (Fase 1.3, 2026-08-08):
  workflow `deploy.yml` operativo (run `31276974715` SUCCESS: 8 rpms, "digests signatures
  OK"), secret `RPM_SIGNING_KEY` configurado y repo publicado a gh-pages/rpm/ con
  `dnf5-5.4.2.1-1`. El **SIGSEGV de `dnf5 history list`** quedó **RESUELTO** (Fase 1.4,
  2026-08-08): backport del fix upstream 4.18.2 de rpm (patch
  `termux-remove-sqlite3-global-log.patch`, commit `04e5089`; REVISION rpm → 4, `c1bb30e`),
  rebuild rpm+dnf5 (run `31296859502` SUCCESS) y validado en el dispositivo (`dnf5 history
  list` lista las 17 transacciones EXIT=0 sin SIGSEGV). El **test del install/uninstall
  script** quedó **ejercitado de extremo a
  extremo** al reinstalar el stack **8/8** con la clave nueva (rotación de clave, Fase 1.3); el
  dispositivo quedó operativo.
  La firma de paquetes GPG quedó **CERRADA y VALIDADA** (Fase 1.2, 2026-08-08): el SIGSYS de
  rpm resuelto con el patch de libpopt (`84a667f` + `a37f14b`, run `31271307345` 9/9), **los 7
  RPMs del repo firmados** con `rpm --addsign` en el dispositivo (`rpm -K` → "digests
  signatures OK") y publicados en gh-pages (`392df86`), dnf5 con `gpgcheck=1 repo_gpgcheck=1`
  sin errores de firma y con la **instalación real CONFIRMADA** (dnf5 pide la firma de
  paquetes y metadata; ambas verificaciones funcionan). El sistema de firma GPG del repo quedó
  **CERRADO** (Fase 1.1, 2026-08-08): repo
  firmado y **validado en el dispositivo** con auto-import de la clave (`8509ddb`, `9b01c22`,
  `1874325`); caché anti-rebuilds en CI (`92eaf7b`, fix `733b9d8`; run `31242682232` 8/8 que
  pobló la caché). La Fase 2 operativa quedó **CERRADA** (Fase 1.0, 2026-08-07): **dnf5
  funciona 100% sin errores en el dispositivo** (repo local del plugin y repo remoto GitHub
  Pages resueltos; install/reinstall OK) y `createrepo_c` está **portado a Termux**
  (`packages/createrepo-c/`, commit `424533d`, run `31236591563` 8/8). T10/T11 completadas
  (`0568f9e` y review con 4 MAJOR resueltos: `889eb4e` M1/M2, `af949a1` M3, `e541907` M4).

## Pendiente (no empezado)

- **T12**: reporte final (formal) — siguiente paso (la Fase 1.3 quedó cerrada y validada).
- **Ecosistema completo**: más paquetes RPM en el repo — el gran reto de la Fase 2 (los 689+
  paquetes del dispositivo tendrían que pasar por rpmbuild/CI y `scripts/mkrepo.sh` o
  `createrepo_c`).
- **Automatizar la re-firma al añadir paquetes (deploy + firma en CI)**: **RESUELTO**
  (Fase 1.3, 2026-08-08) — workflow `deploy.yml` operativo: convierte los `.pkg` a `.rpm`,
  firma con el secret `RPM_SIGNING_KEY`, genera `repodata/` (`createrepo_c`), firma
  `repomd.xml` y publica a gh-pages/rpm/ (run `31276974715` SUCCESS: 8 rpms, "digests
  signatures OK").
- **Test del install/uninstall script**: **ejercitado de extremo a extremo** en la
  reinstalación del stack **8/8** con la clave nueva (rotación de clave, Fase 1.3, 2026-08-08)
  — el dispositivo quedó con el stack reinstalado y operativo.

## Preguntas de Seguimiento (para el usuario)

- **(a) Confirmación de instalación real `gpgcheck=1`**: **RESUELTO/CONFIRMADO (2026-08-08)** —
  la instalación real con `gpgcheck=1 repo_gpgcheck=1` quedó **validada en el dispositivo**:
  dnf5 **pide la firma de los paquetes (gpgcheck)** y **la firma del metadata
  (repo_gpgcheck)** y **ambas verificaciones funcionan** (los 7 RPMs firmados con
  `rpm --addsign`, `rpm -K` → "digests signatures OK"; repo publicado en gh-pages,
  `392df86`). El sistema de firmas GPG completo opera (metadata + 7 paquetes + auto-import de
  clave).
- **(b) Deploy + firma automatizados en CI**: **RESUELTO (2026-08-08, Fase 1.3)** — el workflow
  `deploy.yml` quedó **operativo** (disparo manual `workflow_dispatch`,
  https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/deploy.yml): convierte los
  `.pkg` del último build exitoso a `.rpm` (`scripts/pkg2rpm.sh`), firma con la clave del
  **secret `RPM_SIGNING_KEY`**, genera `repodata/` (`createrepo_c`), firma `repomd.xml` y
  publica a gh-pages/rpm/ — run `31276974715` SUCCESS (8 rpms, "digests signatures OK"; repo
  actualizado: `dnf5-5.4.2.1-1`). Ya no es manual.
- **(c) Resolución desde REPO (rpmlib)**: **RESUELTO y VERIFICADO** (commit `058d61e`, deps
  versionadas con `flags/epoch/ver/rel`; libsolv resuelve vía SYSTEMSOLVABLE) — install/reinstall
  **OK** desde la URL remota en la Fase 1.0 (ahora además con `gpgcheck=1`).
- **(d) `createrepo_c`**: **RESUELTO** — portado a Termux (`packages/createrepo-c/`, commit
  `424533d`, run `31236591563` 8/8). Queda elegir si reemplaza a `scripts/mkrepo.sh` como
  generador de `repodata/`.
- **(e) Ecosistema completo**: ¿convertir el resto del ecosistema Termux a RPM en CI? Es el gran
  reto de la Fase 2 (los 689+ paquetes del dispositivo tendrían que pasar por
  rpmbuild/`scripts/mkrepo.sh` o `createrepo_c`).
- **(f) `dnf5 history list` (el "detallito de history")**: **RESUELTO (2026-08-08, Fase 1.4)**
  — el **SIGSEGV (139)** al listar el historial con WAL pendiente en
  `transaction_history.sqlite` quedó **fijado** con el backport del fix upstream de rpm
  4.18.2 (commit `d018e756`, "Don't muck with per-process global sqlite configuration"):
  patch `termux-remove-sqlite3-global-log.patch` (commit `04e5089`) que elimina el callback
  **GLOBAL** de sqlite3 registrado por `lib/backend/sqlite.c` de rpm 4.18.1
  (`sqlite3_config(SQLITE_CONFIG_LOG, errCb, rdb)` → use-after-free en procesos que abren
  otras dbs sqlite). Rebuild rpm (**REVISION=4**, commit `c1bb30e`) + dnf5 (run
  `31296859502` SUCCESS) y **validado en el dispositivo**: `dnf5 history list` **lista las 17
  transacciones EXIT=0 sin SIGSEGV** (test CONCLUSIVO con WAL pendiente real de 16 KB).
- **T12 (reporte final)**: T10 y T11 completadas (install `76c828a` y uninstall `cb47ebe`
  **simétricos**; review T11 con 4 MAJOR resueltos: `889eb4e` M1/M2, `af949a1` M3,
  `e541907` M4), la **Fase 1.2 cerrada y validada en dispositivo** (gpgcheck/repo_gpgcheck
  confirmados), la **Fase 1.3 cerrada** (deploy automatizado + rotación de clave), la
  **Fase 1.4 cerrada** (SIGSEGV de `dnf5 history list` fijado) y el
  install/uninstall **ejercitado de extremo a extremo** en la reinstalación 8/8 — ¿se continúa
  con T12 formal y el ecosistema completo?

---

## Bootstrap dnf5 (bootstrap.zip)

**Estado: IMPLEMENTADO (script + workflow creados y verificados estáticamente); pendiente CI y validación on-device.**

- **Qué se construyó**:
  - `scripts/generate-bootstrap-dnf5.sh` (nuevo) — generador del bootstrap de Termux con dnf5
    como gestor nativo: descarga el set de termux-pacman (base 30 + deps curadas + cierre
    transitivo), convierte `.pkg` → `.rpm` (`scripts/pkg2rpm.sh`), firma siempre (M9), puebla la
    rpmdb sqlite con `rpm --root`, verifica conffiles, audita DT_NEEDED (readelf), genera
    `SYMLINKS.txt`, empaqueta `bootstrap-aarch64.zip` y verifica (unzip -l, rpm -qa en [90,200],
    tamaño < 300MB, sha256). 14 pasos, correcciones C1–C6/M1–M9/m1–m5 aplicadas.
  - `.github/workflows/bootstrap.yml` (nuevo) — CI: job `build` en `ubuntu-24.04-arm` (genera y
    sube artifact `bootstrap-aarch64`) + job `publish` (descarga con download-artifact@v4 y
    crea GitHub Release con tag `bootstrap-YYYY.MM.DD-rN+dnf5.android-7` y sha256 en las notas).
- **Verificaciones locales**: `bash -n` OK; YAML parseable (pyyaml). No se ha lanzado el CI ni
  se ha validado on-device (siguiente paso).
- **Decisiones clave**:
  - Cierre transitivo: **93 paquetes finales, 0 sin resolver** (nombre exacto; fallback por
    índice provides). `python` aceptado en el cierre.
  - **arch=any**: `termux-am` y `ca-certificates` se re-empaquetan con `fix_any_arch_pkg()`
    (`.PKGINFO` parcheado a `aarch64`) antes de convertir a `.rpm` (rpmbuild falla con arch=any).
  - **Conffile**: el `.rpm` de dnf5 ya instala `termux.repo` apuntando a gh-pages con
    `gpgcheck=1 repo_gpgcheck=1`; el generador solo lo verifica (no lo reescribe).
  - `termux-keyring` excluido del set base; `--no-sign` eliminado (siempre se firma).
- **Referencia**: spec completa en `BOOTSTRAP-DESIGN.md` (incluye el bloque "Estado de
  implementación" con todas las correcciones del code-review).

## Fase 1.6 — Bootstrap publicado y documentación de instalación (2026-08-10)

Sesión posterior a la Fase 1.5 (2026-08-10). El **bootstrap del sistema con dnf5 como único
gestor quedó PUBLICADO** y la documentación de instalación se añadió/actualizó. Estado
verificado contra el CI (`bootstrap.yml`), las Releases del repo y los docs actualizados.

### ✅ Workflow `bootstrap.yml` SUCCESS y primer release publicado

- El workflow `bootstrap.yml` (job `build` en `ubuntu-24.04-arm` + job `publish`) corrió
  **SUCCESS** tras una cadena de **11 fixes del CI** que dejaron el pipeline verde.
- **Primer release publicado**: tag
  `bootstrap-2026.08.10-r1+dnf5.android-7`
  (https://github.com/Leonisaurov/dnf-for-termux/releases/tag/bootstrap-2026.08.10-r1%2Bdnf5.android-7),
  asset **`bootstrap-aarch64.zip`** (~73 MB, 95+ paquetes RPM: stack dnf5 + base de
  termux-pacman convertida).
- **sha256 del asset**: `55ed99682afa91b3d1c9bfd68e6fd11e269fa4b84cbf2b97dfb3f29809776081`
  (incluido en las release notes, como exige m4).
- El generador (`scripts/generate-bootstrap-dnf5.sh`) usa el **`--dbpath` ABSOLUTO**
  `/data/data/com.termux/files/usr/var/lib/rpm` (decisión D8/R1 corregida: rpm ≥ 4.18
  rechaza el relativo) y el publish descarga el artifact con `download-artifact@v4` a
  `bootstrap-aarch64/` (zip en `bootstrap-aarch64/bootstrap-aarch64.zip`).

### ✅ Documentación de instalación añadida/actualizada

- **`docs/INSTALLATION.md`** (nuevo) — guía principal de instalación: modo **alterno**
  (`scripts/install-dnf-termux.sh`/`uninstall-dnf-termux.sh`) y modo **principal
  (bootstrap)** con el flujo failsafe de la wiki.
- **`README.md`** (nuevo en la raíz) — resumen del proyecto con sección **## Instalación**
  (los 2 modos) y enlaces a docs, repo RPM, Releases y workflows.
- **`config/yum.repos.d/termux.repo`** — sincronizado con el conffile real que instala el
  paquete dnf5 (`https://Leonisaurov.github.io/dnf-for-termux/rpm/` con
  `gpgcheck=1 repo_gpgcheck=1`; sustituye al placeholder `packages.termux.dev/rpm/` 404).
- **`BOOTSTRAP-DESIGN.md` / `style.md`** — corregidas las menciones al `--dbpath` relativo
  (→ absoluto) y al layout de publish antiguo (`bootstrap-out/` → `bootstrap-aarch64/`).
- **`docs/ARCHITECTURE.md` / `docs/CI-PIPELINE.md`** — nota de estado desactualizado al
  inicio (la fuente de verdad es `PROGRESS.md`/`REPORT.md`).

### Pendientes

- **Ecosistema completo**: más paquetes RPM en el repo (conversión del ecosistema Termux a
  RPM en CI) — el repo hoy solo tiene los 8 del stack (el base del bootstrap no es
  actualizable vía dnf5 todavía).
- **Validación on-device del bootstrap** publicado (flujo failsafe, CA-8 de
  `BOOTSTRAP-DESIGN.md`).

---

## Repo RPM COMPLETO — `repo-full.yml` + `--mode repo` (2026-08-09)

**Estado: IMPLEMENTADO (script `--mode repo` + workflow nuevo + `deploy.yml` deshabilitado);
pendiente: primer run de CI (dry-run → producción) + verificación on-device + borrado de
`deploy.yml`.** Correcciones C1/M1–M6/m1–m12 del crítico aplicadas (tabla en
`REPO-FULL-DESIGN.md` "## Estado de implementación").

- **`scripts/generate-bootstrap-dnf5.sh`**: flag `--mode <bootstrap|repo>` (default
  bootstrap) + `--no-project`. En modo repo ejecuta los pasos 1-4 (resolver cierre desde
  `main.json`, descargar `.pkg`, `fix_any_arch`, convertir+firmar) y **sale temprano**:
  copia `$WORK/rpms/*.rpm` + `manifest.txt` + `pkg-table.txt` a `--out`; sin rpmdb,
  conffiles, DT_NEEDED, SYMLINKS.txt, zip ni PASO 13. `--no-project` omite la descarga del
  stack de gh-pages (el workflow lo añade aparte). Flujo bootstrap (14 pasos) intacto.
- **`.github/workflows/repo-full.yml`** (nuevo): **único writer** de `gh-pages/rpm/`.
  Stack (9 .rpm, incl. `dnf-hello`) desde gh-pages (canónico) o artifacts de `build.yml`
  (`update-stack=true`, con check de expiración m7); cierre termux-pacman vía
  `--mode repo --no-project`; assert `total -ge stack + pkg-table` (M5/m9); firma única
  `rpm --addsign` + `rpm -K` == total; `createrepo_c`; firma `repomd.xml` + `gpg --verify`
  en CI (m12); export `termux-rpm.gpg`; staging `{index.html, .nojekyll, rpm/}`; clean
  publish peaceiris `enable_jekyll: false` (M4). Input `dry-run` (build + verify sin
  publicar; evidencia en `GITHUB_STEP_SUMMARY` — no artifact: `actions: read` no permite
  upload-artifact). Permissions `{contents: write, actions: read}` (m11). Concurrency
  `rpm-repo-publish`; triggers dispatch + schedule `30 0 * * 0`.
- **`.github/workflows/deploy.yml`**: **DESHABILITADO** (`on: []` + comentario C1) —
  sustituido por repo-full como único writer; borrar tras validar el primer run.
- **Verificaciones locales**: `bash -n` del generador OK; YAML parseable (pyyaml) y
  actionlint sin errores.

### Pendientes

- [ ] Primer run de `repo-full` (dry-run → producción) y verificación CA-1..CA-5 (§9 del
  diseño).
- [ ] Verificación on-device: CA-6 (instalados ⊆ repo, excluyendo `gpg-pubkey-*`; warning
  con delta — M2) y CA-7 (`dnf5 install <convertido instalado>` → already installed o
  actualizable — M3).
- [ ] Borrar `deploy.yml` tras validar.


