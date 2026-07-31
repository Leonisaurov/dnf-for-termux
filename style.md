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
