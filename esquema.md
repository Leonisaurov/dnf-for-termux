# Esquema: Reinicio Fase 0 — Port de DNF5 a Termux con termux-packages

## Propósito

Reiniciar el proyecto dnf-for-termux desde cero (Fase 0) usando el **sistema oficial
de construcción de paquetes de Termux** (`termux-packages`), para que los binarios
sean **cross-compilados reales para aarch64** (la arquitectura del dispositivo del
usuario) y se empaqueten como `.deb` instalables con `dpkg` en Termux.

El problema que resuelve: el intento anterior compilaba nativamente para x86_64
(host del container CI), las dependencias eran librerías Ubuntu x86_64 instaladas
con `apt-get`, y el traspaso a aarch64 real se rompió por mezcla de arquitecturas,
toolchain incompleto y artefactos nunca generados.

## Diagnóstico (por qué se rompió — evidencia en el repo)

| # | Problema | Evidencia |
|---|----------|-----------|
| 1 | Build nativo x86_64, no cross | Todos los `build/termux/*/build.sh` dicen "Builds natively (x86_64)" |
| 2 | Dependencias x86_64 de Ubuntu | `apt-get install libpopt-dev libglib2.0-dev ...` dentro de los build.sh |
| 3 | Toolchain CMake incompleto | `aarch64-toolchain.cmake`: `CMAKE_SYSTEM_NAME Linux` (no Android), sin sysroot bionic, sin `--target`, `CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY` enmascara fallos de link |
| 4 | Meson sin cross-file | `zchunk/build.sh` exporta CC/CXX pero no pasa `--cross-file` |
| 5 | No usa termux-packages | Cero `TERMUX_PKG_*`, cero `termux_setup_*`; NDK descargado a mano (`setup-ndk.sh`) cuando el container `package-builder` ya lo trae |
| 6 | Artefactos no instalables | `staging/` no es .deb; `create-repo` busca `*.rpm` que nunca se generan; el instalador descarga de `packages.termux.dev/rpm/` un `.deb` inexistente |
| 7 | Confusión conceptual | Se intentaba emitir `.rpm` para Termux; Termux distribuye `.deb`. DNF es un paquete `.deb` de Termux que *gestiona* repos RPM |

## Componentes (modelo nuevo)

### A. Estructura del repo (reestructurada)

- **`packages/`** — overlay con los paquetes nuevos en formato termux-packages (nuevo).
- **`patches/`** — conservar: ya están en formato git y son reutilizables. Mover el
  contenido a `packages/<pkg>/` según convenga.
- **`config/`** — conservar y convertir (dnf.conf, yum.repos.d) para instalarse dentro
  del paquete `dnf5` como confiles.
- **`source/`** (submódulos) — **ELIMINAR**: termux-packages descarga el source vía
  `TERMUX_PKG_SRCURL` + `TERMUX_PKG_SHA256` (tarballs de release estables).
- **`build/termux/*` custom, `scripts/setup-ndk.sh`, `scripts/gha-build-all.sh`,
  `aarch64-toolchain.cmake`, `TEMPLATE-build.sh`** — **ELIMINAR** (sistema paralelo roto).
- **`.github/workflows/build.yml`** — reescribir sobre `build-package.sh`.
- **`.github/workflows/update-submodules.yml`** — ELIMINAR (ya no hay submódulos).

### B. Paquetes a crear en `packages/`

| Paquete | Build system | Deps (Termux) | Estado |
|---------|-------------|----------------|--------|
| `libsolv` | cmake | zlib; rpm (para `ENABLE_RPMDB=ON`) | Nuevo — parches existentes reutilizables |
| `zchunk` | meson (con cross-file) | zstd, openssl, curl | Nuevo |
| `libcomps` | cmake | libxml2 (sin python) | Nuevo — patch 0001 reutilizable |
| `librepo` | cmake | glib, libcurl, openssl, gpgme, zchunk; rpm (headers `rpm/rpmpgp.h`) | Nuevo — parches reutilizables |
| `dnf5` | cmake | rpm, libsolv, librepo, libcomps, zchunk, libsqlite, json-c, fmt, glib, libxml2 (+ toml11 header-only, embeber) | Nuevo — 7 patches de rutas ya listos |
| `rpm` | — (ya existe) | — | **REUTILIZAR** el oficial de termux-packages (4.18.1, port completo: libgcrypt, rpmdb SQLite) |

### C. CI (GitHub Actions)

1. **validate** — revisa `build.sh` de los packages (lint básico).
2. **build** — `container: ghcr.io/termux/package-builder:latest`,
   `./build-package.sh -a aarch64 <pkg>` (resuelve deps del fork vía `buildorder.py` +
   recursión). Matrix por componente con `needs:` en orden de dependencias.
3. **verify-arch** — `file` + `readelf -h` sobre los binarios `.so`/`dnf5` del `.deb`
   para **confirmar aarch64** (esto faltó la vez pasada).
4. **artifact** — upload de los `.deb` (`actions/upload-artifact@v4`) + release con tags.

### D. Instalación en Termux

- Script `install-dnf-termux.sh` reescrito: descarga los `.deb` de GitHub Releases
  (aarch64) y `dpkg -i` + `apt install -f`. Arquitectura detectada con `uname -m`.

## Relaciones y Flujo

```
GitHub Actions (container package-builder, host x86_64)
  └── ./build-package.sh -a aarch64 dnf5
        └── buildorder.py resuelve deps del fork (recursión automática):
             rpm (oficial, ya existe)
               ↓
             libsolv ── zchunk ── libcomps     (paralelos/orden topológico)
               └──────────┴──────────┘
                        ↓
                    librepo
                        ↓
                      dnf5  →  .deb aarch64
                                 ↓
        GitHub Releases ← .deb → dpkg -i en Termux (aarch64 real)
```

Flujo de parches: `packages/<pkg>/*.patch` se aplican por el framework antes de
configure (convención termux-packages: patches en el dir del paquete).

## Decisiones Clave

| Decisión | Elegida | Alternativas | Razón |
|----------|---------|--------------|-------|
| Sistema de build | termux-packages oficial (`build-package.sh`) | Sistema custom actual | Oficial, cross-compila aarch64 real, resuelve deps, genera .deb |
| Formato de distribución | `.deb` de Termux | `.rpm` (plan original) | Termux usa apt/.deb; DNF gestiona RPM, no es el formato de distribución |
| `rpm` | Reutilizar el oficial (4.18.1) | Portar 4.20.1 propio (cmake) | Ya está mantenido por termux (libgcrypt + SQLite); menos superficie de bug |
| Lugar de compilación | GitHub Actions (container package-builder) | Docker local; compilar en Termux | La skill termux-pkg-builder prohíbe compilar en Termux (lento/OOM); GHA gratis y automático |
| Source de componentes | Tarballs release (`TERMUX_PKG_SRCURL` + SHA256) | Submódulos git a master | Reproducible, versiones estables, estándar del framework |
| Estructura del repo | Overlay: `packages/` + CI materializa tree de termux-packages | Fork directo de termux-packages | Conserva historial, autocontenido, sin mantener fork separado |
| Verificación | Job `verify-arch` con `file`/`readelf` en CI | Confiar en el build | El desastre anterior fue por no verificar arquitectura |
| `toml11` | Embeber header-only en `packages/dnf5/` | Buscar paquete (no existe en termux) | Es header-only, simple |

## Riesgos y Suposiciones

- **Riesgo: rpm oficial no instala headers de desarrollo** (librpm/rpmio .h). Impacto:
  libsolv (`ENABLE_RPMDB`) y librepo (`rpm/rpmpgp.h`) no compilan. Plan B: parche
  `0003-optional-gpgme` ya explora GPGME puro en librepo; o añadir subpaquete `rpm-dev`.
- **Riesgo: versiones de deps de termux-packages insuficientes para dnf5** (fmt, json-c,
  C++20). Plan B: subir versiones vía patches o añadir paquetes que falten al overlay.
- **Riesgo: los .deb salen mal empaquetados** (deps no declaradas en `TERMUX_PKG_DEPENDS`
  → break en instalación). Mitigación: probar `dpkg -i` en Termux real temprano, no al final.
- **Suposición: el dispositivo es aarch64** (el usuario lo confirma: "traspaso real a aarch64").
- **Suposición: el repo de GitHub es público** (necesario para Actions gratis y Releases).
- **Suposición: runtime sin root es problema de Fase posterior** — compilar los paquetes
  (Fase 0) no depende de resolver permisos/chroot de rpm.

## Estado

- [ ] Concepto definido (este esquema)
- [ ] Pendiente de aprobación del Orquestador

## Notas para el Orquestador

1. **Limpieza con git, no a mano**: borrar `source/` (submódulos), `build/termux/` custom,
   `scripts/setup-ndk.sh`, `scripts/gha-build-all.sh`, `update-submodules.yml` y reescribir
   `build.yml`. Conservar `patches/`, `config/`, `docs/`, `PLAN.md`, `install-dnf-termux.sh`
   (adaptar). `err.log` es basura de gita — borrar.
2. **NO rehacer los patches**: los 7 de dnf5 y los de libsolv/librepo/libcomps ya están
   bien hechos; solo se reubican a `packages/<pkg>/`.
3. **Orden de ejecución sugerido** (planificador):
   - T1: Reestructurar repo (limpieza + mover patches/config a packages/)
   - T2: `packages/zchunk` (más simple, meson) → build verde
   - T3: `packages/libsolv` + `packages/libcomps` → build verde
   - T4: validar dep `rpm` oficial (headers) → `packages/librepo`
   - T5: `packages/dnf5` (más complejo) + confiles de config/
   - T6: `verify-arch` job + instalación real en Termux + release
4. **Hito de verificación innegociable**: `readelf -h` de cada `.so` y del binario `dnf5`
   debe decir `Machine: AArch64`. Ese fue el error del intento anterior.
5. **Decisión pendiente del usuario**: ¿el repo RPM para dnf (al que apuntará
   `yum.repos.d/termux.repo`) será GitHub Pages de este repo, o se deja para Fase 2?
   No bloquea Fase 0.
