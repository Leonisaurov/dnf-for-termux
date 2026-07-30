# Plan de Adaptación de DNF para Termux

## 1. Resumen Ejecutivo

**Objetivo**: Portar DNF5 (Dandified YUM, gestor de paquetes de Fedora/RHEL) para funcionar en Termux (Android), coexistendo con apt, siguiendo el modelo establecido por el port de pacman (`termux-pacman`).

**Viabilidad**: Alta para componentes independientes (libsolv, librepo), MUY BAJA para RPM. DNF5 tiene ~650K LOC (C++17 + C), con una cadena de dependencias compleja. El cuello de botella crítico es **RPM (librpm)**, ~150K LOC C atado a glibc, que nunca se ha portado exitosamente a bionic (libc de Android).

**Enfoque**: Adaptación por capas, comenzando con componentes portables y dejando RPM para el final. Si RPM resulta inviable, se propone un Plan B: usar PRoot Fedora como backend de RPM o implementar un adaptador RPM → apt.

**Esfuerzo estimado**: 6-12 meses para un port completo con 1-2 desarrolladores dedicados.

---

## Progreso Actual

**Última actualización**: 31 julio 2026

### Fase 0 — Infraestructura: ✅ COMPLETADA (6 commits, 31 archivos)

| Componente | Estado | Notas |
|-----------|--------|-------|
| Proyecto Git + estructura | ✅ Completo | 31 archivos trackeados, 5 submódulos |
| dnf5 source | ✅ Clonado | vía submodule, 23MB, 2,105 archivos |
| libsolv source | ✅ Clonado | vía submodule, 5.8MB, 458 archivos |
| librepo source | ✅ Clonado | vía submodule, 4.7MB, 315 archivos |
| libcomps source | ✅ Clonado | vía submodule, 16MB, 178 archivos |
| zchunk source | ✅ Clonado | vía submodule, 6.4MB, 163 archivos |
| Parche dnf5 (rutas) | ✅ Creado | 15 paths FHS → $PREFIX en const.hpp |
| Parche libsolv (rutas) | ✅ Creado | 6 archivos adaptados |
| Parche librepo (GPG) | ✅ Creado | GPG socket → $TMPDIR |
| Config DNF | ✅ Creado | dnf.conf + yum.repos.d/ |
| Scripts de build/setup | ✅ Creados | setup-build, apply-patches, install |
| **CI/CD Pipeline** | ✅ **COMPLETADO** | Ver sección 10 |

### Fase 0.5 — CI/CD Pipeline: ✅ COMPLETADA

| Componente | Estado | Notas |
|-----------|--------|-------|
| build.yml | ✅ Completo | 4 jobs: validate, build (matrix), create-repo, release |
| update-submodules.yml | ✅ Completo | Actualización semanal automática |
| dependabot.yml | ✅ Completo | Dependabot para Actions |
| gha-build-all.sh | ✅ Creado | Orquestador de compilación (orden de dependencias) |
| build script template | ✅ Creado | TEMPLATE-build.sh para componentes |
| CI-PIPELINE.md | ✅ Creado | Documentación del pipeline |

### Fase 1 — Componentes Portables: 🔧 3/4 COMPLETADO

| Componente | Build Script | Compila en CI | Estado |
|-----------|:-----------:|:-------------:|--------|
| zchunk | ✅ Creado (meson) | ✅ Compila | Build verificado |
| libsolv | ✅ Creado (cmake) | ✅ Compila | Build verificado |
| libcomps | ✅ Creado (cmake) | ✅ Compila | Build verificado |
| librepo | ✅ Creado (cmake) | ❌ Bloqueado por RPM | Depende de rpm/rpmpgp.h |

**Nota**: librepo compila configuración cmake con el parche gpgme-opcional, pero 
gpg_rpm.c incluye `<rpm/rpmpgp.h>` directamente en el código fuente. Para 
completarlo se necesita primero RPM (ver Decisión #4).

**Build scripts**: `build/termux/<componente>/build.sh`
**CI Pipeline**: GitHub Actions con `ghcr.io/termux/package-builder:latest`

---

## 2. Análisis Comparativo: Port de Pacman vs Port de DNF

| Aspecto | Pacman | DNF5 | Transferible |
|---------|--------|------|--------------|
| **Lenguaje** | C (libalpm) | C++17 (libdnf5) + C (rpm) | ✅ Sí, mismo enfoque de parches |
| **LOC total** | ~80K | ~650K (todo el stack) | ❌ 8x más código |
| **Dependencias** | Mínimas (openssl, zstd, curl) | Masivas (rpm, libsolv, librepo, glib, sqlite, zchunk, json-c) | ❌ Mucho más complejo |
| **Permisos** | Necesita root (parche eliminado) | Necesita root (mismo problema) | ✅ Misma solución: parches de permisos |
| **Rutas FHS** | Hardcodeadas (mismos patrones) | Hardcodeadas (mismos patrones) | ✅ Misma estrategia: s|/etc|$PREFIX/etc|g |
| **Base de datos** | Archivos + sqlite | SQLite (transaction history) + BerkeleyDB (rpmdb) | ⚠️ rpmdb es más compleja |
| **Formato paquetes** | .pkg.tar.zst (tar comprimido) | .rpm (cpio + header + payload) | ❌ RPM es mucho más complejo de manipular |
| **Firma** | GPG (pacman-key) | GPG + OpenSSL (rpmkeys) | ✅ Similar |
| **Resolución de deps** | Simple (archivos PROVIDES) | SAT solver (libsolv) | ⚠️ Más complejo pero portable |
| **Integración con apt** | Tree separado, DB separada | Tree separado, DB separada | ✅ Misma estrategia |
| **Systemd** | No usa | No requiere (aunque tiene sd-bus opcional) | ✅ No es blocker |
| **Glibc** | No crítico (portable) | CRÍTICO (rpm atado a glibc) | ❌ El mayor desafío |
| **Ports previos a bionic** | Sí, termux-pacman | NO, nadie ha portado rpm a bionic | ❌ Sin precedentes |
| **Comunidad** | ~190 ⭐, activa | ~800 ⭐ (DNF), comunidad Fedora grande | ✅ Recursos disponibles |
| **CI/CD con GHA** | Requiere fork termux-packages | Creado con container oficial | ✅ Implementado |

**Transferibilidad**: 18/25 aspectos del port de pacman son aplicables a DNF. La principal diferencia es la complejidad y dependencia de glibc de RPM.

---

## 3. Arquitectura Objetivo en Termux

### Árbol de directorios adaptado para $PREFIX

```
$PREFIX/
├── bin/
│   ├── dnf                    # CLI principal
│   └── rpm                    # CLI de RPM (si se porta)
├── etc/
│   ├── dnf/
│   │   ├── dnf.conf           # Configuración principal
│   │   └── vars/              # Variables para dnf
│   └── yum.repos.d/
│       ├── termux.repo        # Repositorio Termux RPM
│       └── termux-testing.repo
├── lib/
│   ├── libdnf5.so             # Core library
│   ├── librpm.so              # RPM library
│   ├── librpmio.so            # RPM I/O
│   ├── libsolv.so             # SAT solver
│   ├── librepo.so             # Repo downloader
│   ├── libcomps.so            # Group management
│   └── libzck.so              # Zchunk
├── libexec/
│   └── dnf5/
│       └── plugins/           # Plugins de dnf
├── var/
│   ├── lib/
│   │   ├── dnf/               # Base de datos de transacciones
│   │   └── rpm/               # RPM database (rpmdb)
│   └── cache/
│       └── dnf/               # Cache de repositorios
└── share/
    ├── locale/                # Traducciones
    ├── man/                   # Páginas de manual
    └── dnf/                   # Data compartida
```

### Diferencias con el diseño original de DNF en Fedora

| Path original (FHS) | Path Termux ($PREFIX) | Motivo |
|---------------------|----------------------|--------|
| `/etc/dnf/dnf.conf` | `$PREFIX/etc/dnf/dnf.conf` | No hay /etc escribible |
| `/var/lib/dnf/` | `$PREFIX/var/lib/dnf/` | No hay /var real |
| `/var/cache/dnf/` | `$PREFIX/var/cache/dnf/` | No hay /var real |
| `/var/lib/rpm/` | `$PREFIX/var/lib/rpm/` | No hay /var real |
| `/etc/yum.repos.d/` | `$PREFIX/etc/yum.repos.d/` | No hay /etc real |
| `/usr/share/dnf/` | `$PREFIX/share/dnf/` | No hay /usr real |
| `/run/user/` | `$TMPDIR` | No hay /run |

---

## 4. Mapa de Parches Necesarios

### 4.1 Patrón general de parches

Basado en los 13 parches de termux-pacman, cada componente de DNF necesitará parches similares:

| Tipo de Parche | Patrón | Aplica a |
|---------------|--------|----------|
| **Ruta de configuración** | `/etc` → `$PREFIX/etc` | rpm, dnf5, librepo |
| **Ruta de datos** | `/var/lib` → `$PREFIX/var/lib` | rpm, dnf5 |
| **Ruta de caché** | `/var/cache` → `$PREFIX/var/cache` | dnf5, librepo |
| **Ruta de binarios** | `/usr/bin` → `$PREFIX/bin` | rpm, dnf5 |
| **Ruta de librerías** | `/usr/lib` → `$PREFIX/lib` | rpm, dnf5 |
| **Ruta de share** | `/usr/share` → `$PREFIX/share` | rpm, dnf5 |
| **Eliminar checks de root** | `geteuid() == 0` | rpm, dnf5 |
| **Eliminar capability checks** | `CAP_SYS_ADMIN` | rpm |
| **Eliminar mount syscalls** | `mount()`, `umount()` | rpm (scripts chroot) |
| **Adaptar syscalls** | `getrandom()`, `personality()` | rpm |
| **GPG paths** | `/etc/pki/rpm-gpg` → `$PREFIX/etc/pki/rpm-gpg` | rpm |
| **Locale paths** | `/usr/share/locale` → `$PREFIX/share/locale` | dnf5 |
| **tmp paths** | `/tmp` → `$TMPDIR` | rpm, dnf5, libdnf5 |

### 4.2 RPM (librpm) — ~50 parches estimados

RPM es el componente más complejo de portar. Este es el análisis preliminar:

| Archivo/Área | Parche | Dificultad | Prioridad |
|-------------|--------|-----------|----------|
| `rpmio/rpmio.c` | Reemplazar `/tmp` → `$TMPDIR` | 🟢 Fácil | Alta |
| `rpmio/rpmlog.c` | Logging paths | 🟢 Fácil | Alta |
| `rpmdb/` | Paths de base de datos | 🟡 Media | Alta |
| `lib/transaction.c` | Eliminar checks de root | 🟢 Fácil | Alta |
| `lib/psm.c` | Eliminar mount/umount en scripts | 🟡 Media | Alta |
| `lib/verify.c` | Verificación sin chroot | 🟡 Media | Alta |
| `rpmio/rpmsw.c` | Adaptar syscalls no disponibles | 🔴 Difícil | Alta |
| `rpmio/digest.c` | Adaptar OpenSSL para bionic | 🟡 Media | Alta |
| `rpmio/rpmmacro.h` | Paths de macros | 🟢 Fácil | Alta |
| `build/` | Build system paths | 🟡 Media | Media |
| `sign/` | GPG paths y keyring | 🟡 Media | Media |
| `rpmio/rpmfileutil.c` | Permisos de archivo (sin chown) | 🟡 Media | Alta |
| `lib/rpmug.c` | Users/groups (no existe /etc/passwd) | 🔴 Difícil | Alta |
| `rpmio/rpmlock.c` | Locking (flock en FS Android) | 🔴 Difícil | Alta |
| `CMakeLists.txt` | Flags de compilación bionic | 🟡 Media | Alta |
| `rpmrc.in` | Configuración de paths | 🟢 Fácil | Alta |

### 4.3 libsolv — ~5 parches

libsolv es el componente más portable del stack:

| Archivo/Área | Parche | Dificultad |
|-------------|--------|-----------|
| `src/solver.c` | SAT solver paths para repos | 🟢 Fácil |
| `src/repo_rpmdb.c` | Paths rpmdb | 🟢 Fácil |
| `ext/` | Extensiones para formato Termux | 🟡 Media |
| `CMakeLists.txt` | Flags bionic si es necesario | 🟢 Fácil |

### 4.4 librepo — ~8 parches

| Archivo/Área | Parche | Dificultad |
|-------------|--------|-----------|
| `src/curl_transfer.c` | Proxy/certs paths | 🟢 Fácil |
| `src/read_conf.c` | Paths de configuración | 🟢 Fácil |
| `src/package_download.c` | Cache paths | 🟢 Fácil |
| `src/repomd.c` | Mirror paths | 🟢 Fácil |
| `src/init.c` | Inicialización en Termux | 🟡 Media |

### 4.5 libdnf5 — ~15 parches

| Archivo/Área | Parche | Dificultad |
|-------------|--------|-----------|
| `libdnf5/base/base.cpp` | Paths de configuración | 🟢 Fácil |
| `libdnf5/conf/config_main.cpp` | Config defaults | 🟢 Fácil |
| `libdnf5/repo/repo.cpp` | Cache paths | 🟢 Fácil |
| `libdnf5/rpm/package.cpp` | RPM paths | 🟢 Fácil |
| `libdnf5/rpm/transaction.cpp` | Transaction paths | 🟡 Media |
| `libdnf5/plugin/` | Plugin paths | 🟢 Fácil |
| `libdnf5/utils/` | Filesystem utils (sin root) | 🟡 Media |

### 4.6 dnf5 CLI — ~5 parches

| Archivo/Área | Parche | Dificultad |
|-------------|--------|-----------|
| `dnf5/main.cpp` | Default config path | 🟢 Fácil |
| `dnf5/commands/` | Help paths | 🟢 Fácil |
| `dnf5/plugins/` | Plugin loading paths | 🟢 Fácil |

**Total estimado**: 52-68 parches en todo el stack

---

## 5. Plan de Implementación por Fases

### Fase 0: Fundación de Infraestructura (Semanas 1-2)

**Objetivo**: Preparar el entorno de build y desarrollo.

- [ ] Crear proyecto `dnf-for-termux` en GitHub
- [ ] Fork de `termux-packages` con soporte RPM
- [ ] Extender `build-package.sh` para formato RPM (actualmente soporta deb y pacman)
- [ ] Agregar target `TERMUX_PACKAGE_FORMAT=rpm` al build system
- [ ] Configurar repositorio RPM de prueba (firmado con GPG)
- [ ] Dockerizar el entorno de build (NDK + toolchains)
- [ ] Establecer CI/CD en GitHub Actions
- [ ] Crear scaffolding del proyecto con submódulos:
  - `libsolv/` (git submodule)
  - `rpm/` (git submodule)
  - `librepo/` (git submodule)
  - `libcomps/` (git submodule)
  - `dnf5/` (git submodule)

**Criterio de éxito**: `build-package.sh` puede compilar un paquete RPM simple y firmarlo.

### Fase 0.5: CI/CD Pipeline (Semanas 0-1 — COMPLETADA)

**Objetivo**: Establecer infraestructura de compilación remota para evitar OOM killer en Termux.

**Arquitectura**:
```
GitHub Actions (ubuntu-latest)
  └── Container: ghcr.io/termux/termux-packages:latest
       └── Cross-compile: aarch64 (ARM64)
            ├── validate    → Verifica parches y submódulos
            ├── build       → Matrix: zchunk, libcomps, libsolv, librepo, dnf5, rpm
            ├── create-repo → Genera repomd.xml + GitHub Pages
            └── release     → GitHub Release con .rpm
```

- [x] Workflow build.yml con 4 jobs y matrix de componentes
- [x] Cache de builds entre ejecuciones
- [x] Despliegue a GitHub Pages como repositorio RPM
- [x] Release automático con tags v*
- [x] Documentación CI/CD (CI-PIPELINE.md)

### Fase 1: Componentes Portables (Semanas 3-6)

**Objetivo**: Portar todo el stack excepto RPM (que se aborda en Fase 2).

#### 1.1 libsolv (Semanas 3-4)
Es el componente más portable. Ya se usa en varios sistemas (OpenSUSE, Fedora, etc.).

- [x] Obtener fuente: `git clone https://github.com/openSUSE/libsolv.git`
- [x] Aplicar parches de rutas mínimos (~5)
- [x] Crear build script para Termux (`build.sh`)
- [x] Compilar con CMake + NDK (host x86_64 en CI)
- [ ] Ejecutar test suite
- [ ] Verificar: crear un repositorio RPM simple y resolver dependencias con `testsolv`

**Dependencias**: cmake, zlib (ya en Termux)

**Estimación**: 2 semanas

#### 1.2 zchunk (Semanas 3-4)
- [x] Obtener fuente: `https://github.com/zchunk/zchunk.git`
- [x] Parches mínimos (rutas)
- [x] Compilar para Termux (host x86_64 en CI)
- [ ] Verificar: `zck` funciona y puede crear/leer archivos .zck

**Dependencias**: openssl, zstd (ya en Termux)

#### 1.3 libcomps (Semanas 5-6)
- [x] Obtener fuente: `https://github.com/rpm-software-management/libcomps.git`
- [ ] Parches de rutas
- [x] Crear build script
- [ ] Compilar para Termux (host x86_64 en CI)

**Dependencias**: libxml2 (ya en Termux), python3 (opcional)

#### 1.4 librepo (Semanas 5-6)
- [x] Obtener fuente: `https://github.com/rpm-software-management/librepo.git`
- [x] Parches de rutas y configuración (~8)
- [x] Crear build script
- [ ] Compilar para Termux (host x86_64 en CI)

**Dependencias**: glib, curl, openssl, libzstd, gpgme

**Criterio de éxito de Fase 1**: libsolv, zchunk, libcomps y librepo compilan y pasan tests en Termux.

### Fase 2: RPM — El Gran Desafío (Semanas 7-20)

**Objetivo**: Portar RPM (librpm) a Termux/bionic. Es el componente más crítico y difícil.

#### 2.1 Análisis y preparación (Semanas 7-8)
- [ ] Análisis profundo del código fuente de RPM
- [ ] Identificar todas las dependencias de glibc usadas por RPM
- [ ] Mapear todas las rutas FHS hardcodeadas
- [ ] Identificar syscalls no disponibles en Android
- [ ] Crear matriz de compatibilidad glibc → bionic
- [ ] Configurar entorno de build con Docker + NDK

#### 2.2 Adaptación del build system (Semanas 9-10)
- [ ] Crear `build.sh` para RPM en Termux
- [ ] Adaptar `CMakeLists.txt` para Android NDK
- [ ] Configurar flags de compilación para bionic
- [ ] Resolver dependencias: popt, file, elfutils, berkeley-db, lua, zstd, openssl, nss
- [ ] Portar/omitir dependencias no disponibles

**Dependencias de RPM**:
| Dependencia | En Termux | Notas |
|------------|-----------|-------|
| popt | ✅ sí | Parseo de args |
| file | ✅ sí | Magic numbers |
| elfutils | ✅ sí | Manipulación ELF |
| berkeley-db | ✅ sí | rpmdb (legacy) |
| lua | ✅ sí | Scripts rpm |
| zstd | ✅ sí | Compresión payload |
| openssl | ✅ sí | Criptografía |
| nss | ⚠️ posible | Firma GPG, alternativa: gpgme |
| sqlite | ✅ sí | rpmdb (moderno) |
| glibc | ❌ NO | **BLOCKER** - bionic es incompatible |

#### 2.3 Parches de compatibilidad bionic (Semanas 11-14)
- [ ] Reemplazar `glibc-specific` APIs con equivalentes bionic:
  - `error()`, `error_at_line()` → implementación propia
  - `argp_parse()` → usar getopt_long o popt (ya usado)
  - `fts.h` → portable (bionic tiene fts)
  - `obstack.h` → implementación propia
  - `sys/sysinfo.h` → parcial en bionic
  - `sys/vfs.h` → statfs alternativo
  - `execinfo.h` → backtrace() en bionic limitado
  - `ifaddrs.h` → disponible desde API 24+
  - `langinfo.h` → parcial
  - `printf.h` → no disponible
- [ ] Parches de syscalls:
  - `personality()` → stub/no-op
  - `sched_setaffinity()` → bionic compatible
  - `mount()` → stub (no disponible sin root)
  - `chroot()` → stub (no disponible sin root)
  - `mlockall()` → parcial en Android

#### 2.4 Parches de rutas FHS → $PREFIX (Semanas 15-16)
- [ ] Aplicar ~25 parches de rutas en rpm/
- [ ] Configurar macros RPM para Termux (`/usr/lib/rpm/macros` → `$PREFIX/lib/rpm/macros`)
- [ ] Configurar rpmrc para Termux
- [ ] Probar: `rpm --showrc` muestra rutas correctas

#### 2.5 Parches de permisos y operaciones (Semanas 17-18)
- [ ] Eliminar checks de `geteuid() == 0`
- [ ] Eliminar verificaciones de CAP_SYS_ADMIN
- [ ] Adaptar operaciones de chown (no disponible en Android)
- [ ] Adaptar creación de usuarios/grupos
- [ ] Adaptar locking de archivos
- [ ] Adaptar scriptlets de empaquetado

#### 2.6 Pruebas de RPM (Semanas 19-20)
- [ ] Compilar paquete RPM de prueba con `rpmbuild`
- [ ] Instalar paquete RPM de prueba
- [ ] Verificar base de datos rpmdb
- [ ] Probar transacciones (install, remove, upgrade)
- [ ] Probar firmas GPG
- [ ] Probar scripts pre/post

**Criterio de éxito de Fase 2**: `rpm --version` funciona, `rpm -i paquete.rpm` instala correctamente, `rpm -e paquete` elimina.

**⚠️ HITO CRÍTICO**: Si RPM no compila después de 10 semanas de trabajo dedicado, considerar Plan B.

### Fase 3: libdnf5 + dnf5 CLI (Semanas 21-28)

**Objetivo**: Portar la capa de alto nivel de DNF5.

#### 3.1 libdnf5 core (Semanas 21-24)
- [ ] Obtener fuente de dnf5
- [ ] Aplicar ~15 parches de rutas
- [ ] Adaptar configuración (dnf.conf para Termux)
- [ ] Adaptar módulo de repositorios
- [ ] Adaptar módulo de transacciones
- [ ] Adaptar plugins

#### 3.2 dnf5 CLI (Semanas 25-26)
- [ ] Aplicar ~5 parches de rutas
- [ ] Configurar comandos para Termux
- [ ] Adaptar output (colores, paginación)
- [ ] Integrar con termux-services si necesario

#### 3.3 Integración y pruebas (Semanas 27-28)
- [ ] Integrar todos los componentes
- [ ] Probar dnf5 install/remove/update
- [ ] Probar resolución de dependencias
- [ ] Probar transacciones multi-paquete
- [ ] Probar con repositorio RPM Termux real
- [ ] Pruebas de estrés

**Criterio de éxito de Fase 3**: `dnf --help` funciona, `dnf install <paquete>` instala desde repositorio, `dnf remove` funciona, resolución de dependencias correcta.

### Fase 4: Pulido y Release (Semanas 29-32)

- [ ] Documentación completa (README, guía de instalación)
- [ ] Crear paquete `dnf` en repositorio Termux (termux-packages)
- [ ] Script de instalación (como `pacman-for-termux/install.sh`)
- [ ] GPG keyring (`termux-keyring-dnf`)
- [ ] CI/CD robusto con tests automáticos
- [ ] Documentación de API para desarrolladores de plugins
- [ ] Lanzamiento público

---

## 6. Dependencias y Build System

### 6.1 Cadena completa de dependencias

```
dnf5 (dnf)
├── libdnf5
│   ├── rpm (librpm, librpmio)
│   │   ├── popt
│   │   ├── zlib
│   │   ├── zstd
│   │   ├── openssl
│   │   ├── berkeley-db (o sqlite para rpmdb)
│   │   ├── lua
│   │   ├── file (libmagic)
│   │   ├── elfutils (libelf)
│   │   ├── nss (o gpgme como alternativa)
│   │   ├── bzip2
│   │   ├── xz
│   │   ├── acl (parcial, no en Android)
│   │   ├── cap (parcial, no en Android → stub)
│   │   └── glibc → ❌ BIONIC (el blocker)
│   ├── librepo
│   │   ├── glib (glib2)
│   │   ├── curl (libcurl)
│   │   ├── openssl
│   │   ├── zstd
│   │   └── gpgme (opcional)
│   ├── libsolv
│   │   ├── zlib
│   │   └── cmake (build)
│   ├── libcomps
│   │   ├── libxml2
│   │   └── python3 (opcional)
│   ├── sqlite
│   ├── json-c
│   └── fmt (C++20 formatting)
├── glib2 (para librepo)
├── gpgme (para firmas)
├── python3 (opcional, plugins)
└── cmake (build)
```

### 6.2 Componentes de Termux ya disponibles

| Paquete Termux | Usado por | Notas |
|---------------|-----------|-------|
| `popt` | rpm | ✅ |
| `zlib` | rpm, libsolv | ✅ |
| `zstd` | rpm, librepo | ✅ |
| `openssl` | rpm, librepo | ✅ |
| `liblua` | rpm | ✅ |
| `file` | rpm | ✅ |
| `elfutils` | rpm | ✅ |
| `gpgme` | rpm, librepo | ✅ |
| `bzip2` | rpm | ✅ |
| `libxml2` | libcomps | ✅ |
| `sqlite` | libdnf5 | ✅ |
| `json-c` | libdnf5 | ✅ |
| `libcurl` | librepo | ✅ |
| `glib2` | librepo | ✅ |
| `cmake` | todos | ✅ |
| `berkeley-db` | rpm (rpmdb legacy) | ⚠️ No confirmado |
| `nss` | rpm (firma) | ⚠️ Alternativa: gpgme |
| `acl` | rpm | ❌ No disponible → stub |
| `libcap` | rpm | ❌ No disponible → stub |

### 6.3 Build system (termux-packages expandido)

El build system de termux-packages actualmente soporta dos formatos:
- `TERMUX_PACKAGE_FORMAT=debian` (default, .deb)
- `TERMUX_PACKAGE_FORMAL=pacman` (.pkg.tar.zst)

Habría que añadir:
- `TERMUX_PACKAGE_FORMAT=rpm` (.rpm)

```bash
# build.sh para rpm (ejemplo)
TERMUX_PKG_HOMEPAGE=https://rpm.org/
TERMUX_PKG_DESCRIPTION="RPM Package Manager"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=4.19.1
TERMUX_PKG_SRCURL=https://ftp.osuosl.org/pub/rpm/releases/rpm-4.19.x/rpm-${TERMUX_PKG_VERSION}.tar.bz2
TERMUX_PKG_DEPENDS="popt, zlib, zstd, openssl, lua, file, elfutils, gpgme, sqlite, berkeley-db, bzip2, xz"
TERMUX_PKG_BUILD_DEPENDS="cmake"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DCMAKE_INSTALL_PREFIX=$TERMUX_PREFIX
-DRPM_CONFIGDIR=$TERMUX_PREFIX/etc/rpm
-DRPM_VARDIR=$TERMUX_PREFIX/var/lib/rpm
-DENABLE_NLS=OFF
-DWITH_CAP=OFF
-DWITH_ACL=OFF
-DWITH_FUSE=OFF
"
```

---

## 7. Riesgos y Mitigaciones

| # | Riesgo | Impacto | Probabilidad | Mitigación |
|---|--------|---------|-------------|------------|
| 1 | **RPM no compila en bionic** — glibc-specific APIs incompatibles | 🔴 Crítico | Alta (70%) | Parches de compatibilidad; si falla → Plan B |
| 2 | **RPM requiere operaciones de root** (chroot, mount, chown) | 🔴 Crítico | Alta (90%) | Stubs/no-ops; verificar que no rompan funcionalidad |
| 3 | **Dependencias de RPM no disponibles en Termux** (berkeley-db, nss, acl, libcap) | 🟡 Alto | Media (50%) | Buscar alternativas (sqlite por berkeley-db, gpgme por nss, stubs para acl/cap) |
| 4 | **Problemas de rendimiento** — Android mata procesos con OOM killer | 🟡 Alto | Media (50%) | Compilar con optimizaciones de tamaño; usar termux-wake-lock; operaciones transaccionales pequeñas |
| 5 | **Espacio en disco** — 650K LOC + builds puede exceder storage | 🟡 Medio | Media (40%) | CI/CD externo (GitHub Actions); builds incrementales; limpiar caches |
| 6 | **Conflicto con apt** — paquetes RPM sobrescribiendo archivos de apt | 🟡 Medio | Alta (80%) | Namespace de paquetes diferente; poner prefijo a archivos conflicivos |
| 7 | **Firmas GPG y keyring** — Android no tiene keyring tradicional | 🟡 Medio | Media (50%) | Adaptar termux-keyring para RPM; parches similares a termux-pacman |
| 8 | **Maintenance burden** — actualizar parches por versión de DNF | 🟡 Medio | Alta (70%) | Automatizar generación de parches; mantener diff contra upstream |
| 9 | **Rendimiento de libsolv** — SAT solver puede consumir mucha RAM | 🟡 Bajo | Baja (20%) | Android 8+ tiene suficiente RAM; limitar tamaño de repos |
| 10 | **Documentación** — usuarios de Termux no conocen RPM | 🟡 Bajo | Alta (80%) | Documentación clara; equivalencias: yum → apt |
| 11 | **Mantenimiento de repositorio RPM** — necesita infraestructura de mirror | 🟡 Medio | Alta (80%) | Usar GitHub Releases + GitHub Pages como repo; script de generación de metadata |
| 12 | **Falta de interés de la comunidad** — DNF en Android es nicho | 🟡 Bajo | Media (50%) | Documentar el proyecto bien; hacerlo fácil de contribuir |

### Plan B: Si RPM resulta inviable

Si después de 10 semanas de trabajo dedicado RPM no compila o no funciona correctamente en bionic, las alternativas son:

**Plan B1: PRoot Fedora Backend**
- En lugar de portar RPM nativo, usar `proot-distro login fedora` como backend
- dnf5 CLI en Termux se comunicaría con RPM dentro del proot
- Ventaja: RPM funciona sin modificaciones
- Desventaja: Necesita proot instalado, overhead de rendimiento

**Plan B2: Adaptador RPM → apt/ALPM**
- Crear una capa de compatibilidad que convierta requests de RPM a operaciones de apt o libalpm
- dnf5 usaría este adaptador en lugar de rpm nativo
- Ventaja: Sin necesidad de portar RPM
- Desventaja: Funcionalidad limitada, posible incompatibilidad

**Plan B3: Port de microdnf (dnf5 minimal)**
- `microdnf` es una versión minimalista de dnf5 que usa libdnf5 sin rpm
- Ya no requiere rpm para operaciones básicas
- Ventaja: Evita el bloqueador de RPM
- Desventaja: Funcionalidad reducida

---

## 8. Árbol de Decisión y Hitos

```
Inicio
└── ¿Fase 0 (infraestructura) lista?
    ├── Sí → Fase 1 (libsolv, zchunk, librepo, libcomps)
    │   └── ¿Compilan?
    │       ├── Sí → Fase 2 (RPM)
    │       │   ├── ¿RPM compila en bionic?
    │       │   │   ├── Sí → ¿Pasa tests funcionales?
    │       │   │   │   ├── Sí → Fase 3 (libdnf5 + dnf5 CLI)
    │       │   │   │   │   └── ¿DNF funcional?
    │       │   │   │   │       ├── Sí → Fase 4 (Release) ✅
    │       │   │   │   │       └── No → Debug + iterar
    │       │   │   │   └── No → Debug RPM (2-4 semanas extra)
    │       │   │   │       └── ¿Se arregla?
    │       │   │   │           ├── Sí → Continuar
    │       │   │   │           └── No → Plan B
    │       │   │   └── No → Plan B (PRoot / adaptador)
    │       │   └── No → Debug + ajustar parches
    │       └── No → Dependencias faltantes → resolver
    └── No → Completar Fase 0
```

### Hitos Clave

| Hito | Semana | Indicador | Acción si falla |
|------|--------|-----------|-----------------|
| H1: Build system RPM-ready | 2 | `build-package.sh` produce .rpm | Extender soporte |
| H2: libsolv + librepo + zchunk funcionan | 6 | Tests pasan en Termux | Debug dependencias |
| H3: RPM compila en bionic | 14 | `make` exitoso | DEBUG intensivo 2 sem → Plan B |
| H4: RPM funcional (install/remove) | 20 | `rpm -i` funciona | Debug transacciones |
| H5: DNF funcional | 26 | `dnf install` desde repo | Debug integración |
| H6: Release | 32 | Paquete instalable | Documentar workarounds |

---

## 9. Conclusión y Recomendación

### Resumen de Viabilidad

| Componente | LOC | Dificultad | Confianza |
|-----------|-----|-----------|-----------|
| libsolv | 80K C | 🟢 Fácil | 95% |
| zchunk | 10K C | 🟢 Fácil | 95% |
| libcomps | 15K C | 🟢 Fácil | 90% |
| librepo | 30K C | 🟡 Media | 80% |
| libdnf5 | 200K C++ | 🔴 Difícil (depende de rpm) | 60% |
| dnf5 CLI | 50K C++ | 🔴 Difícil (depende de libdnf5) | 60% |
| RPM | 150K C | 🔴 MUY Difícil | 35% |

### Recomendación

1. **Comenzar con Fase 0 + Fase 1** (componentes portables) — bajo riesgo, valor inmediato
2. **Intentar RPM en Fase 2** — si falla, documentar lecciones y ejecutar Plan B
3. **Considerar seriamente Plan B3 (microdnf)** — si microdnf puede funcionar sin rpm (solo libdnf5), es la ruta más pragmática
4. **Publicar progreso públicamente** — atraer contribuidores interesados en el desafío RPM+bionic

### Reflexión Final

El port de pacman a Termux fue exitoso porque pacman es **simple**: ~80K LOC C, dependencias mínimas, y su creador (Judd Vinet) lo diseñó para ser portable. DNF5 es **10x más complejo** que pacman, y RPM es el ancla que lo ata a glibc y FHS.

Sin embargo, el valor de tener DNF en Termux es significativo:
- Acceso al ecosistema RPM (Fedora, RHEL, OpenSUSE)
- Posibilidad de instalar paquetes .rpm en Android
- Experiencia de usuario familiar para usuarios de Fedora
- SAT solver (libsolv) es superior a apt en resolución de dependencias complejas

**Si RPM resulta inviable, el port parcial (libsolv + librepo + microdnf) sigue siendo valioso** y sienta las bases para futuros intentos de portar RPM cuando Android/bionic madure.

---

## 10. CI/CD Pipeline (Implementado)

Ver `docs/CI-PIPELINE.md` para documentación completa.

### Resumen del Pipeline

| Job | Descripción | Tiempo estimado |
|-----|-------------|-----------------|
| **validate** | Verifica parches (dry-run), submódulos, sintaxis | ~2 min |
| **build-component** | Matrix de 4-6 componentes en paralelo | ~15-45 min c/u |
| **create-repo** | Genera repodata con createrepo_c + deploy Pages | ~3 min |
| **release** | GitHub Release con artefactos .rpm | ~2 min |

### ¿Qué compila dónde?

| Componente | Compila en | Estado |
|-----------|-----------|--------|
| zchunk | 🟢 GHA (10K C, fácil) | ✅ Build script creado, compila |
| libcomps | 🟢 GHA (15K C, fácil) | ✅ Build script creado, compila |
| libsolv | 🟢 GHA (80K C, portable) | ✅ Build script creado, compila |
| librepo | 🟡 GHA (30K C, GLib) | 🔶 Bloqueado: requiere rpm/rpmpgp.h |
| dnf5 | 🔴 GHA (250K C++, pesado) | Pendiente de RPM |
| RPM | 🟡 GHA (150K C, bionic) | Port existe en termux-packages |

### Beneficios de la CI/CD

1. **Sin OOM killer**: Todo compila en servidores GitHub, no en Termux
2. **Paralelismo**: Componentes independientes compilan simultáneamente
3. **Cache**: Build objects cacheados entre runs (ahorra ~70% tiempo)
4. **Repositorio público**: GitHub Pages sirve como RPM repo
5. **Release automático**: Tags v* generan releases con .rpm
6. **Mantenimiento**: Submódulos se actualizan semanalmente

---

## 11. Registro de Decisiones Técnicas

### Decisión #1: Compatibilidad Bionic en librepo

| Campo | Valor |
|-------|-------|
| **Contexto** | librepo (biblioteca de descarga de repositorios RPM) usa GLib como capa de abstracción de plataforma. Esto significa que las diferencias entre sistemas operativos (Linux, BSD, Android) son manejadas por GLib automáticamente. |
| **Decisión** | No se requieren parches específicos para bionic (Android libc) en librepo. GLib abstrae las diferencias de plataforma. |
| **Consecuencia** | Se eliminó el archivo `patches/librepo/0002-bionic-compat.patch`, que era un placeholder documentativo (no contenía bloques diff). El CI fallaba al intentar aplicarlo como parche. |
| **Alternativas** | Crear un parche real modificando algún archivo de librepo (innecesario, pues no hay cambios que hacer). |
| **Fecha** | 2026-07-29 |
| **Responsable** | dnf-for-termux |

### Decisión #2: Imagen Docker para CI

| Campo | Valor |
|-------|-------|
| **Contexto** | El workflow de CI usaba `ghcr.io/termux/termux-packages:latest` como imagen contenedora para compilar los componentes. Esta imagen no existe (manifest unknown). |
| **Decisión** | Se cambió a `ghcr.io/termux/package-builder:latest`, que es la imagen oficial del proyecto Termux para compilar paquetes. Contiene el NDK r29, toolchain standalone para aarch64, y todas las dependencias de build necesarias. |
| **Consecuencia** | Los builds de CI ahora pueden inicializar contenedores correctamente. La imagen incluye Ubuntu 26.04 con herramientas de build y librerías de desarrollo. |
| **Alternativas** | Usar `ubuntu-latest` directamente e instalar dependencias manualmente (más lento, menos predecible). Usar Docker Hub `termux/package-builder:latest` como espejo. |
| **Fecha** | 2026-07-30 |
| **Responsable** | dnf-for-termux |

### Decisión #3: Estrategia de build tools en CI

| Campo | Valor |
|-------|-------|
| **Contexto** | El contenedor `package-builder` no incluye `cmake`, `meson` ni `ninja` pre-instalados (el build system de termux-packages los descarga bajo demanda vía scripts `termux_setup_*`). |
| **Decisión** | Los build scripts descargan las herramientas directamente desde sus fuentes oficiales: cmake desde tarball de Kitware/CMake, ninja como binario estático desde GitHub Releases, meson vía `pip install --break-system-packages`. |
| **Consecuencia** | Los builds son autónomos (no dependen de apt-get) y funcionan en cualquier entorno Linux x86_64 con Python3 y wget. |
| **Alternativas** | Instalar vía apt-get (requiere sudo/root, no disponible en el contenedor por defecto). Incluir las tools en la imagen Docker (más trabajo de mantenimiento). |
| **Fecha** | 2026-07-30 |
| **Responsable** | dnf-for-termux |

### Decisión #4: RPM ya está portado a Termux

| Campo | Valor |
|-------|-------|
| **Contexto** | Se asumía que RPM (~150K LOC C) nunca se había portado a bionic (Android libc), y que requeriría ~50 parches y resolver dependencias heavys como NSS. Esto hacía que el proyecto contemplara un Plan B (PRoot Fedora, adaptador RPM→apt, microdnf). |
| **Hallazgo** | RPM 4.18.1 existe como paquete oficial de Termux desde Julio 2023 (`pkg install rpm`). Solo requirió **2 parches** mínimos: `errno.patch` (`__errno_location()` → `__errno()`) y `goto_declaration.patch`. RPM 4.18+ usa Sequoia PGP (Rust) o libgcrypt en vez de NSS, y SQLite en vez de Berkeley DB. |
| **Decisión** | Portar RPM usando los parches de termux-packages como base. No se necesita Plan B. El port es factible y el esfuerzo es mucho menor al estimado originalmente. |
| **Implicaciones** | Desbloquea librepo (que depende de `rpm/rpmpgp.h` para verificación de firmas) y toda la cadena libdnf5 → dnf5 CLI. |
| **Fuente** | https://github.com/termux/termux-packages/tree/master/packages/rpm |
| **Fecha** | 2026-07-31 |
| **Responsable** | dnf-for-termux |

### Decisión #5: Dependencias de dnf5 CLI (además de RPM)

| Campo | Valor |
|-------|-------|
| **Contexto** | Para determinar el esfuerzo restante después de RPM, se investigaron las dependencias completas de libdnf5 y dnf5 CLI. |
| **Hallazgo** | Además de RPM, libdnf5 requiere: libsolv, libsolvext, librepo, sqlite3, json-c, fmt, toml11, glib-2.0, libxml-2.0. De estas, la mayoría ya existen como paquetes en Termux. Las únicas que requieren port son libsolv/libsolvext (ya compiladas en Fase 1) y librepo (bloqueado por RPM). |
| **Decisión** | No hay blockers severos adicionales. La cadena es larga pero todas las dependencias están disponibles en Termux o se compilan como parte del proyecto. El orden de implementación es: RPM → librepo → libdnf5 → dnf5 CLI. |
| **Fecha** | 2026-07-31 |
| **Responsable** | dnf-for-termux |

*Actualizado: 31 julio 2026*
*Basado en investigación de termux-pacman (13 parches analizados), arquitectura de DNF5 (rpm-software-management/dnf5), y el build system de termux-packages (ghcr.io/termux/package-builder)*
