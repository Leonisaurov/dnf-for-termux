# Style Guide: dnf-for-termux

## Estado actual (julio 2026)

Proyecto de port de DNF5 a Termux. **En reinicio de Fase 0**: el sistema de build
paralelo actual (`build/termux/*/build.sh`) se compilaba nativamente x86_64 en el
container y no producía artefactos aarch64 reales. Se migra al sistema oficial
`termux-packages` (fork/overlay + `build-package.sh -a aarch64`).

## Estructura del proyecto

```
DNF/
├── .github/workflows/        # CI: build.yml, update-submodules.yml, dependabot.yml
├── build/termux/             # ⚠️ Sistema custom a ELIMINAR: build.sh por componente,
│                             #    aarch64-toolchain.cmake, TEMPLATE-build.sh
├── config/                   # dnf.conf + yum.repos.d/ (INI con @PREFIX@ placeholder)
├── docs/                     # ARCHITECTURE.md, CI-PIPELINE.md
├── patches/                  # Parches git-format por componente + ROUTES.txt
│   ├── dnf5/                 # 7 patches de rutas FHS → $PREFIX (los + completos)
│   ├── libsolv/              # 2 patches: rutas + bionic CMake
│   ├── librepo/              # 3 patches: rutas, gpgme opcional
│   ├── libcomps/             # 1 patch: sin python bindings
│   ├── rpm/                  # 2 patches: bionic errno, c23 goto
│   └── zchunk/               # ROUTES.txt
├── scripts/                  # setup-ndk.sh, gha-build-all.sh (a ELIMINAR),
│                             # setup-build.sh, apply-patches.sh, install-dnf-termux.sh
├── source/                   # ⚠️ Submódulos git de los 6 componentes (a ELIMINAR:
│                             #    termux-packages descarga source vía TERMUX_PKG_SRCURL)
├── PLAN.md                   # Plan maestro + registro de decisiones (sección 11)
├── style.md                  # Este archivo
└── esquema.md                # Esquema Fase 0 reiniciada (entregable del arquitecto)
```

## Convenciones de código

- **Bash**: `#!/usr/bin/env bash` (CI/container) o `#!/data/data/com.termux/files/usr/bin/bash`
  (scripts on-device). `set -euo pipefail` casi siempre. Comentarios en español mezclado
  con inglés. Patrón idiomático de rutas: `SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"`.
- **Patches**: formato git (`From:`, `Subject:`, diff -p1), numerados `NNNN-descripcion.patch`,
  con `ROUTES.txt` documentando las rutas FHS encontradas y su reemplazo.
- **Placeholder de rutas**: `@TERMUX_PREFIX@` en patches (se sustituye en build) y
  `@PREFIX@` en archivos de config.
- **Workflows YAML**: nombres de jobs descriptivos con emoji (`🔍 validate`, `📦 build-zchunk`),
  `container: ghcr.io/termux/package-builder:latest`, cache con `actions/cache@v4` y
  keys con hash de `build.sh + patches`.
- **Docs**: español, markdown, tablas para comparativas/decisiones.

## APIs y contratos (sistema actual — en desuso)

| Contrato | Formato | Nota |
|----------|---------|------|
| Env de build | `TERMUX_PREFIX`, `TARGET_ARCH`, `CC/CXX` (NDK) | Los build.sh actuales los usan |
| Staging | `build/termux/<comp>/staging/$PREFIX/{include,lib}` | Cache de CI entre componentes |
| Config dnf | INI, `config/dnf/dnf.conf` | Con `@PREFIX@` sin sustituir todavía |

> ⚠️ El nuevo sistema (termux-packages) reemplaza estos contratos por las variables
> `TERMUX_PKG_*` y las funciones `termux_setup_*` del framework oficial.

## Patrones comunes

- **Patches de rutas FHS → $PREFIX**: patrón central del port. Ver `patches/dnf5/ROUTES.txt`
  (inventario exhaustivo) y `patches/libsolv/0001-termux-paths.patch` (ejemplo bien hecho).
- **Estrategia por capas**: componentes portables primero, RPM como dependencia reutilizada
  del repo oficial (Decisión #4 en PLAN.md: rpm 4.18.1 ya existe en termux-packages).
- **Registro de decisiones**: ADR-lite en PLAN.md sección 11 (Contexto/Decisión/Consecuencia/
  Alternativas/Fecha/Responsable).

## Bootstrap generator (dnf5)

- **Spec**: `BOOTSTRAP-DESIGN.md` (raíz) — generador de bootstrap dnf5 para Termux. Spec de
  referencia; su bloque "## Estado de implementación" (línea 3) marca el estado
  **IMPLEMENTADO (2026-08-09)** con las correcciones C1–C6/M1–M9/m1–m5 ya aplicadas.
- **Script**: `scripts/generate-bootstrap-dnf5.sh` (703 líneas, implementado) — genera
  `bootstrap-aarch64.zip` (árbol relativo a `$PREFIX` + rpmdb sqlite pre-poblada). Flags:
  `--arch/--out/--work/--sign-key/--help`. Flujo en 14 pasos: set resuelto desde `main.json`
  de termux-pacman (base 30 + deps curadas + cierre transitivo BFS sobre DEPENDS → **93 pkgs,
  0 sin resolver**), `fix_any_arch_pkg()` re-empaqueta los `arch=any` a `aarch64`, conversión
  `.pkg` → `.rpm` con `scripts/pkg2rpm.sh` + firma (siempre, M9), rpmdb poblada con
  `rpm --root` (`--dbpath` absoluto `/data/data/com.termux/files/usr/var/lib/rpm`, `$SUDO`;
  rpm ≥ 4.18 rechaza el relativo), verificación de conffiles (`termux.repo` →
  gh-pages con `gpgcheck=1 repo_gpgcheck=1`), auditoría DT_NEEDED con `readelf` (whitelist
  `BIONIC_LIBS`), `SYMLINKS.txt` (formato `target←path`), zip con entries relativos a `usr/`
  y verificaciones finales (`unzip -l`, `rpm -qa` en [90,200] + `gpg-pubkey` ≥1, tamaño
  <300MB, sha256).
- **Workflow**: `.github/workflows/bootstrap.yml` (75 líneas, implementado) — disparo por
  `workflow_dispatch` + `schedule` semanal (cron `0 0 * * 0`); job `build` en
  **`ubuntu-24.04-arm`** (macros rpm aarch64; lección deploy.yml) con permissions
  `{contents: read, actions: write}`, `apt install rpm jq zip unzip sqlite3 binutils curl gpg
  libarchive-tools file gzip`, patrón de firma replicado de `deploy.yml` (secret
  `RPM_SIGNING_KEY`, `~/.rpmmacros` con `%__gpg_sign_cmd`, clave pública importada en
  `$HOME/rpmdb`) y artifact `bootstrap-aarch64` (`upload-artifact@v4`); job `publish` con
  `download-artifact@v4` y `gh release create` con tag `bootstrap-YYYY.MM.DD-rN+dnf5.android-7`
  (incrementa `rN` hasta tag libre) y sha256 en las notas.
- **Publicación del repo RPM — único writer**: `.github/workflows/repo-full.yml` (nuevo)
  publica el repo **COMPLETO** en `gh-pages/rpm/` y sustituye a `deploy.yml` (que quedó
  **DESHABILITADO** con `on: []`; borrar tras validar el primer run). Stack del proyecto
  (9 .rpm, **incluye `dnf-hello`**) desde gh-pages (canónico) u opcionalmente desde
  artifacts de build.yml (`update-stack=true`, con check de expiración m7); cierre
  termux-pacman (~93 .rpm) re-convertido con `generate-bootstrap-dnf5.sh --mode repo
  --no-project` (mismo cierre que el bootstrap). Firma única `rpm --addsign` (idempotente)
  + assert `rpm -K` == total; `createrepo_c`; firma `repomd.xml` **verificada en CI** con
  `gpg --verify` (m12); export de `termux-rpm.gpg`; staging `{index.html, .nojekyll, rpm/}`
  + clean publish peaceiris `enable_jekyll: false` (sin `destination_dir`/`keep_files`).
  Triggers: `workflow_dispatch` (inputs `dry-run` — sin publicar, evidencia en step summary —
  y `update-stack`) + `schedule` semanal (`30 0 * * 0`); concurrency `rpm-repo-publish`;
  permissions `{contents: write, actions: read}` (m11).
- **Convenciones**: `#!/usr/bin/env bash`, `set -euo pipefail`, `$TMPDIR` nunca `/tmp` en
  Termux (fallback `/tmp` solo en runners), staging bajo `$TMPDIR`, `SUDO` por env para
  `rpm --root`, zip creado desde `$USR` (nunca con prefijo `data/`), verificación estática en
  CI (ELF aarch64 + `rpm -qa` + `unzip -l`); validación funcional on-device (los binarios
  Android no corren en el runner).

## Observaciones

- **Lección clave**: los 6 build.sh de `build/termux/` dicen literalmente
  "Builds natively (x86_64) in the package-builder container" → se compilaba para el
  host, no para el target. El toolchain `aarch64-toolchain.cmake` es incompleto
  (`CMAKE_SYSTEM_NAME Linux`, sin sysroot bionic, sin flags target) y las dependencias
  se instalaban con `apt-get` (librerías x86_64 de Ubuntu).
- `err.log` es basura de log de gita (no es un error real del proyecto).
- Instalador actual descarga de `https://packages.termux.dev/rpm/` un `.deb` que no existe:
  el pipeline nunca generó artefactos instalables (.deb/.rpm).
- Los patches de `patches/` SÍ son reutilizables para los `packages/*` de termux-packages.
