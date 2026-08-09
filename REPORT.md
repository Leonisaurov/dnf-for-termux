# REPORT — dnf-for-termux (T12: reporte final)

> Fecha del reporte: 2026-08-09 · Proyecto: `Leonisaurov/dnf-for-termux` · Rama principal: `main`
> Fuente de verdad: `PROGRESS.md`, verificado contra el repo real (`git log`, `.github/workflows/*`, `packages/*`, `scripts/*`, rama `gh-pages`, `curl` sobre las URLs y `gh run`).

## 1. Resumen

**dnf-for-termux** es un port del gestor de paquetes **DNF5** —y de su ecosistema RPM:
`rpm`, `libsolv`, `librepo`, `libcomps`, `zchunk`— a **Termux/Android**, construido como un
**overlay sobre `termux/termux-packages`** (no un fork).

El proyecto **funciona de verdad**: `dnf5` **instala RPMs firmados desde un repositorio
remoto en un dispositivo Android real**, con verificación GPG completa de paquetes y metadata
(`gpgcheck=1 repo_gpgcheck=1`), historial de transacciones funcional y un
instalador/desinstalador simétricos para el dispositivo.

## 2. Arquitectura

### Modelo: overlay sobre termux-packages (no fork)

El CI clona `termux/termux-packages` (depth 1), copia el overlay encima y compila con el
sistema oficial. El repo contiene solo tres áreas:

| Área | Contenido |
|---|---|
| `packages/` | 9 paquetes del overlay (build.sh + patches propios) |
| `.github/workflows/` | `build.yml` (compila) y `deploy.yml` (publica repo RPM) |
| `scripts/` | `install-dnf-termux.sh`, `uninstall-dnf-termux.sh`, `mkrepo.sh`, `pkg2rpm.sh` |

### CI `build.yml` — compilación (disparo manual `workflow_dispatch`)

- **Matrix de 9 paquetes**: `[zchunk, libcomps, libsolv, librepo, rpm, libpopt, createrepo-c, dnf-hello, dnf5]` con `fail-fast: false`.
- **Salida en formato pacman** (`.pkg.tar.xz`), el formato real del dispositivo, vía
  `TERMUX_PACKAGE_FORMAT=pacman` inyectado al container (`TERMUX_DOCKER_EXEC_EXTRA_ARGS`).
- **Verify AArch64**: extrae cada `.pkg` y verifica con `file` que **todos** los ELF
  (`.so*` o ejecutables) son aarch64.
- **Caché anti-rebuilds por hash de inputs**: hash de `build.sh` + patches del paquete y de
  sus DEPENDS del overlay (`actions/cache@v4`); en cache-hit **se SKIP el build** y el `.pkg`
  se restaura de la caché (regla del usuario: no recompilar sin cambios).

### CI `deploy.yml` — publicación del repo RPM (disparo manual `workflow_dispatch`)

Convierte los `.pkg` del último build exitoso de `build.yml` (o de un run dado) a `.rpm` y
publica el repo RPM firmado:

1. `scripts/pkg2rpm.sh` — convierte `.pkg.tar.xz` → `.rpm` aarch64 (spec con `AutoReqProv: no`).
2. **Firma GPG** de cada `.rpm` con la clave del **secret `RPM_SIGNING_KEY`** (macro
   `%__gpg_sign_cmd` en `~/.rpmmacros`, gpg headless con ruta absoluta).
3. `createrepo_c` — genera `repodata/`.
4. Firma `repomd.xml` y publica la clave pública `termux-rpm.gpg`.
5. `peaceiris/actions-gh-pages` → publica bajo `rpm/` en la rama `gh-pages`.

### Repo RPM remoto

- **URL**: `https://leonisaurov.github.io/dnf-for-termux/rpm/` (rama `gh-pages`, HTTP 200
  verificado sobre `repodata/repomd.xml` y `dnf-hello-1.0-1.aarch64.rpm`).
- **Firmado**: metadata (`repomd.xml.asc`) **y** los 9 paquetes (GPG).
- `termux.repo` del paquete dnf5 apunta a esa URL con `gpgcheck=1 repo_gpgcheck=1` y
  `gpgkey=.../termux-rpm.gpg` (auto-import disparado por el patch `0015`).

### Bootstrap del dispositivo

- `scripts/install-dnf-termux.sh` — descarga los **8 artifacts** `.pkg` del último run exitoso
  de `build.yml` y los instala con `pacman -U --needed` en orden
  **libpopt → rpm → (libsolv, librepo, libcomps, zchunk, createrepo-c) → dnf5** (libpopt antes
  que rpm: debe usarse el artifact parcheado del SIGSYS).
- `scripts/uninstall-dnf-termux.sh` — **simétrico**: desinstala los 8 paquetes
  (`pacman -Rdd --noconfirm`), limpia config/runtime de dnf5/libdnf5, hace **backup de la
  rpmdb en `$TMPDIR`**, borra la clave GPG de prueba, y con `--purge` elimina también
  `$HOME/dnf-gpg` y los stagings de build.

## 3. Fases e hitos (resumen de PROGRESS.md)

| Fase | Fecha | Hito |
|---|---|---|
| **Fase 0** | 2026-08-05 | Cross-compile **5/5 AArch64** en CI (zchunk, libcomps, libsolv, librepo, dnf5 5.4.2.1) — HITO 5/5 (run `31060791791`) |
| **0.6** | 2026-08-05/06 | CI en formato **pacman** + fix de selección de artifacts (`c381c0d`, `7c5592f`, `805410d`); **dnf5 validado en el dispositivo** (run `31071605356`) |
| **0.7** | 2026-08-05 | Repo RPM **local** funcional (`$HOME/dnf-repo/`) + `scripts/mkrepo.sh` |
| **0.8** | 2026-08-06 | **dnf5 instala y ejecuta RPMs reales** en el dispositivo (rpm rootless patcheado; run `31221704266`) |
| **0.9** | 2026-08-06/07 | Repo RPM **remoto en GitHub Pages** operativo + fix `058d61e` de `mkrepo.sh` (deps versionadas) |
| **1.0** | 2026-08-07 | **dnf5 100% sin errores** en el dispositivo; `createrepo_c` portado a Termux (run `31236591563`) |
| **1.1** | 2026-08-08 | **Firma GPG del repo** (metadata) + auto-import de clave (patch `0015`); caché anti-rebuilds (run `31242682232`) |
| **1.2** | 2026-08-08 | **Firma de paquetes** GPG + patch de libpopt (fix SIGSYS); instalación real con `gpgcheck=1` confirmada (run `31271307345`) |
| **1.3** | 2026-08-08 | **Deploy automatizado** (`deploy.yml`) + **rotación de la clave** de firma (run `31276974715`) |
| **1.4** | 2026-08-08 | **Fix del SIGSEGV de `dnf5 history`** (callback global sqlite3 de rpm; run `31296859502`) |
| **1.5** | 2026-08-08/09 | **dnf-hello** restaurado como paquete de primera clase; rpm 4.18.1-4 sincronizado (build `31303160667`, deploy `31303896890`) |

## 4. Fixes técnicos clave

| # | Área | Problema | Fix | Verificación |
|---|---|---|---|---|
| 1 | **dnf5 bootc** | `Failed to stat /usr` en sistema non-FHS | Patch `0014-termux-bootc-nonfhs.patch`: `bootc::is_writable()` hace `statvfs(TERMUX_PREFIX)` en vez de `/usr` (commit `ac354d0`) | Validado en dispositivo (instalación real) |
| 2 | **rpm rootless-unpack** | `EBADF` al instalar RPMs en Android rootless (SELinux: `open("/")` → EACCES) | `termux-rootless-unpack.patch` en `packages/rpm/`: `ensureDir()` de `lib/fsm.c` re-ancla la caminata en `TERMUX_PREFIX`; ruta fuera del prefix → rechazo (commit `3c6532b`) | Patch horneado en `librpm.so` (cadena `failed to open dir %s: %s` presente); run `31221704266` 7/7 |
| 3 | **mkrepo.sh rpmlib parsing** | `nothing provides rpmlib(...)` en instalaciones **desde repo** | Fix de `entry_from_dep()`/`parse_evr()` en `scripts/mkrepo.sh`: deps versionadas emiten `flags/epoch/ver/rel` (operador al inicio de `rest`, EVR por el último guion, `IFS='|'`) → libsolv resuelve vía SYSTEMSOLVABLE (commit `058d61e`) | `dnf5 install/reinstall` desde la URL remota OK |
| 4 | **createrepo-c portado** | `createrepo_c` no existe en Termux | Nuevo `packages/createrepo-c/` (1.2.4) con `WITH_LIBMODULEMD=OFF`, `ENABLE_BASHCOMP=OFF`, `ENABLE_DRPM=OFF`, `ENABLE_PYTHON=OFF`, `BUILD_DOC_C=OFF`, `WITH_ZCHUNK=ON` (commits `424533d` + `c8f88e5`) | Build local aarch64 + run `31236591563` 8/8 |
| 5 | **libpopt no-elevated-exec-drop** | `rpm --addsign` moría con **SIGSYS** (`__NR_setgid` bloqueado por seccomp) | `packages/libpopt/` (1.19-4, REVISION=4): patch `termux-no-elevated-exec-drop.patch` — el drop de privilegios de `execCommand()` queda envuelto en `if (getuid() != geteuid() \|\| getgid() != getegid())` (no-op en Android rootless; idéntico a upstream con setuid real). Commits `84a667f` + `a37f14b` | run `31271307345` 9/9; `rpm --addsign` funciona en el dispositivo |
| 6 | **rpm sqlite3 global log callback** | **SIGSEGV (139)** en `dnf5 history list` con WAL pendiente (use-after-free) | Backport del fix upstream 4.18.2 (`d018e756`): patch `termux-remove-sqlite3-global-log.patch` elimina `errCb` + `sqlite3_config(SQLITE_CONFIG_LOG, ...)` de `lib/backend/sqlite.c`; **REVISION rpm → 4** (commits `04e5089` + `c1bb30e`) | run `31296859502` SUCCESS; `dnf5 history list` lista las 17 transacciones EXIT=0 sin SIGSEGV (WAL real de 16 KB) |
| 7 | **Firma GPG (metadata + paquetes)** | dnf5 no auto-importaba la gpgkey con el mensaje "Bad GPG signature" del librepo de Termux | Patch `0015-termux-gpg-import-trigger.patch` amplía el chequeo de `RepoPgp::import_key()` (commit `8509ddb`); `termux.repo` con `gpgcheck=1 repo_gpgcheck=1 gpgkey=...` (commit `9b01c22`) | Validado en el dispositivo: prompt de importación → aceptada → instalaciones vía GPG OK; `rpm -K` → "digests signatures OK" |
| 8 | **Caché anti-rebuilds por hash** | No recompilar sin cambios (regla del usuario) | Hash de `build.sh` + patches del paquete y de sus DEPENDS del overlay → `actions/cache@v4`; cache-hit → SKIP del build (commits `92eaf7b` + fix `733b9d8`) | run `31242682232` 8/8 pobló la caché; en la Fase 1.5 solo dnf-hello recompiló (resto cache-hit) |

## 5. Estado actual

**Funciona** (verificado en el dispositivo y en CI):

- `dnf5 install / update / history` **desde el repo firmado remoto** con `gpgcheck=1
  repo_gpgcheck=1`: dnf5 pide la firma de los paquetes **y** la del metadata, y **ambas
  verificaciones funcionan**.
- `dnf5 history list` **sin SIGSEGV** (17 transacciones, EXIT=0; librpm 4.18.1-4 sin
  referencias a `sqlite3_config`).
- **Instalador/desinstalador simétricos** (8 paquetes; `--purge` soportado), ejercitados de
  extremo a extremo en la reinstalación 8/8 tras la rotación de clave.
- Hello world operativo: `dnf5 -y install dnf-hello && dnf-hello` → "dnf5 funciona en Termux!".

**Versiones clave** (repo RPM actual en gh-pages, 9 paquetes):

| Paquete | Versión | Paquete | Versión |
|---|---|---|---|
| dnf5 | **5.4.2.1-1** | librepo | 1.20.0-0 |
| rpm | **4.18.1-4** | libcomps | 0.1.24-0 |
| libpopt | **1.19-4** | zchunk | 1.5.3-0 |
| createrepo-c | **1.2.4-0** | dnf-hello | 1.0-1 |
| libsolv | 0.7.39-1 | | |

**Runs de referencia** (todos SUCCESS): build `31303160667` (10/10), deploy `31303896890`
(9 RPMs firmados), `31296859502` (rebuild rpm 4.18.1-4 + dnf5), `31276974715` (deploy 8
RPMs), `31271307345` (9/9), `31242682232` (8/8), `31236591563` (8/8), `31221704266` (7/7),
`31071605356` (6/6), `31060791791` (6/6, HITO 5/5).

## 6. Cómo usarlo

### Quickstart en el dispositivo (Termux)

```sh
# 1. Bootstrap del stack dnf5 (8 paquetes) desde los artifacts del CI
scripts/install-dnf-termux.sh --assume-yes

# 2. Instalar un paquete desde el repo RPM firmado remoto
dnf5 -y install dnf-hello

# 3. Ejecutarlo
dnf-hello    # → "dnf5 funciona en Termux!"

# 4. Historial de transacciones
dnf5 history list
```

### Actualizar el repo RPM (CI)

Enlace del deploy:
`https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/deploy.yml`
→ **Run workflow** (opcional: indicar el run de `build.yml` a publicar; vacío = último
exitoso). El workflow convierte `.pkg` → `.rpm`, firma, genera `repodata/` y publica a
gh-pages/rpm/.

## 7. Roadmap / pendientes

- **Ecosistema completo**: más paquetes RPM en el repo (conversión del ecosistema Termux a RPM
  en CI — los 689+ paquetes del dispositivo tendrían que pasar por rpmbuild/CI y
  `scripts/mkrepo.sh` o `createrepo_c`).
- **Firma/CI**: mejoras futuras de firma y del pipeline de CI conforme crezca el ecosistema.
- **T12 cerrado** con este reporte (el resto de tareas previas — T10 install, T11 code review —
  ya completadas).

## 8. URLs útiles

| Recurso | URL |
|---|---|
| Repo GitHub | https://github.com/Leonisaurov/dnf-for-termux |
| Repo RPM remoto (gh-pages) | https://leonisaurov.github.io/dnf-for-termux/rpm/ |
| Clave pública del repo | https://leonisaurov.github.io/dnf-for-termux/rpm/termux-rpm.gpg |
| Workflow build (manual) | https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/build.yml |
| Workflow deploy (manual) | https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/deploy.yml |
| termux-packages (upstream) | https://github.com/termux/termux-packages |
