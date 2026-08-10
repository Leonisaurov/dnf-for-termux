# Instalación — dnf-for-termux

Guía principal de instalación y uso de **dnf-for-termux**, el port del gestor de paquetes
**DNF5** (con su ecosistema RPM: `rpm`, `libsolv`, `librepo`, `libcomps`, `zchunk`,
`createrepo-c`) a Termux/Android.

Hay **dos modos de uso**, según el rol que quieras darle a dnf5:

| Modo | Rol de dnf5 | Impacto en el sistema | Para quién |
|---|---|---|---|
| **1. Alterno** | Convive con pacman/apt (gestor adicional) | **Ninguno** sobre paquetes existentes (instala 8 paquetes del stack junto a los actuales) | Probar dnf5 sin tocar la instalación actual |
| **2. Principal (bootstrap)** | **Único** gestor del sistema | **Reemplaza** `usr/` completo (toda la base de Termux pasa a ser RPM) | Sustituir el gestor de paquetes de Termux por dnf5 |

> Ambos modos requieren un dispositivo **aarch64** (todos los paquetes del proyecto se
> cross-compilan solo para esa arquitectura).

---

## Modo 1: dnf5 como gestor ALTERNO

Recomendado para **probar dnf5 sin arriesgar** el sistema: instala el stack de 8 paquetes
(`dnf5`, `rpm`, `libpopt`, `libsolv`, `librepo`, `libcomps`, `zchunk`, `createrepo-c`) vía
`pacman -U` a partir de los artifacts del último build exitoso del CI. El resto de paquetes de
Termux (pacman/apt) quedan intactos.

### Prerrequisitos

- **Termux** instalado con **pacman** (`termux-pacman`): el script instala los paquetes con
  `pacman -U`, así que termux-pacman debe estar operativo (para más detalle, ver la wiki de
  [termux-pacman](https://github.com/termux-pacman/termux-pacman)). El modo *online* además
  requiere `gh` (GitHub CLI) instalado y autenticado:
  ```sh
  pkg install gh
  gh auth login
  ```
- Arquitectura **aarch64** (`uname -m` → `aarch64`).
- El repositorio clonado en el dispositivo (los scripts están en `scripts/`).

### Instalación

```sh
# Desde la raíz del repo (clonado en el dispositivo):
bash scripts/install-dnf-termux.sh --assume-yes
```

El script (verificado en `scripts/install-dnf-termux.sh`):

1. Localiza el **último run exitoso** del workflow `build.yml` en la rama `main` (vía `gh`).
2. Descarga los **8 artifacts** `<paquete>-aarch64` (zips con los `.pkg.tar.xz` dentro) a un
   staging (`$HOME/.cache/dnf-termux-install`).
3. Los instala con `pacman -U --needed` en el **orden correcto de dependencias**:
   **libpopt → rpm → libsolv → librepo → libcomps → zchunk → createrepo-c → dnf5**
   (libpopt va **antes** que rpm porque debe usarse el artifact parcheado del SIGSYS; si no,
   pacman bajaría el oficial `1.19-3` sin parche).
4. Verifica el resultado con `dnf5 --version`.

#### Flags y modos

| Opción | Efecto |
|---|---|
| `--assume-yes` / `-y` | Pasa `--noconfirm` a pacman (no pregunta confirmaciones) |
| `--help` / `-h` | Muestra la ayuda completa |
| `(directorio)` | **Modo offline**: instala los `.pkg.tar.*` de ese directorio sin descargar nada (p. ej. `bash scripts/install-dnf-termux.sh ~/dnf-pkgs/`) |

Ejemplos:

```sh
bash scripts/install-dnf-termux.sh                # online: descarga e instala el último build
bash scripts/install-dnf-termux.sh --assume-yes   # idem sin preguntar
bash scripts/install-dnf-termux.sh ~/dnf-pkgs/    # offline: instala los .pkg de un directorio
```

> El staging (`$HOME/.cache/dnf-termux-install`) persiste entre reinicios, así que puedes
> reinstalar en modo offline sin volver a descargar.

### Verificación

```sh
dnf5 --version     # imprime la versión instalada
dnf5 repolist      # lista el repo RPM (termux)
```

### Uso básico

```sh
# Hello world del proyecto (paquete de prueba del repo RPM)
dnf5 install dnf-hello && dnf-hello    # → "dnf5 funciona en Termux!"

# Instalar un RPM por archivo local (sin tocar repos)
dnf5 --disablerepo='*' install ./foo.rpm
```

### Desinstalación

```sh
bash scripts/uninstall-dnf-termux.sh              # desinstala los 8 paquetes del stack
bash scripts/uninstall-dnf-termux.sh --purge      # además borra clave de firma y stagings
```

Sin flags, el desinstalador: desinstala los 8 paquetes con `pacman -Rdd --noconfirm`, elimina
la config/runtime de dnf5/libdnf5 (incluido el staging del instalador), hace **backup de la
rpmdb en `$TMPDIR`** y borra la clave GPG de prueba de `~/.gnupg`.

> ⚠️ **`--purge` es peligroso**: además de los stagings de build, elimina **`$HOME/dnf-gpg`**,
> que contiene la **clave de firma del repo RPM** (`E4AC7735...`). Solo úsalo si tienes el
> backup en `$HOME/dnf-for-termux-signing-key.asc` (si no, perderías la capacidad de firmar
> nuevos paquetes del repo).

---

## Modo 2: dnf5 como gestor PRINCIPAL (bootstrap)

El modo "definitivo": un **bootstrap de Termux** (zip) con **95+ paquetes RPM** — el stack
dnf5 (8 paquetes del proyecto) + la base de termux-pacman convertida a RPM — y **dnf5 como
único gestor** de paquetes. El zip reemplaza por completo `/data/data/com.termux/files/usr`.

### Qué es el bootstrap

- **Contenido**: `bootstrap-aarch64.zip` (~73 MB) con el árbol relativo a `usr/`
  (`bin/`, `etc/`, `lib/`, `libexec/`, `share/`, `var/`) y el obligatorio `SYMLINKS.txt`
  (formato `target←path`; la app recrea los symlinks al instalar).
- **rpmdb pre-poblada**: viaja en `usr/var/lib/rpm` con todos los paquetes registrados como
  instalados, para que dnf5 sepa qué hay en el sistema sin una transacción inicial.
- Se publica como **GitHub Release** con el tag `bootstrap-YYYY.MM.DD-rN+dnf5.android-7`
  (el workflow `bootstrap.yml` la genera en CI).

### Descargar

1. Ve a las **Releases** del repositorio:
   https://github.com/Leonisaurov/dnf-for-termux/releases
2. Descarga el asset **`bootstrap-aarch64.zip`** del release con tag
   `bootstrap-...-rN+dnf5.android-7` más reciente.
3. **Verifica el sha256** (aparece en las notas del release):

   ```sh
   sha256sum bootstrap-aarch64.zip
   ```

   Primer release publicado: `bootstrap-2026.08.10-r1+dnf5.android-7` — sha256
   `55ed99682afa91b3d1c9bfd68e6fd11e269fa4b84cbf2b97dfb3f29809776081`.

### Instalación en sesión failsafe

Pasos exactos del flujo "Switching package manager" de la wiki de Termux (el zip **reemplaza**
`/data/data/com.termux/files/usr`):

1. **Cierra todas las sesiones** de Termux.
2. Crea el directorio `usr-n/` **junto a** `usr/` (ruta
   `/data/data/com.termux/files/`), mueve ahí el zip y **descomprímelo** (el zip extrae
   entries relativos a `usr/`: `bin/`, `etc/`, `lib/`, `libexec/`, `share/`, `var/`,
   `SYMLINKS.txt`).
   ```sh
   cd /data/data/com.termux/files
   mkdir usr-n && cd usr-n
   unzip ../bootstrap-aarch64.zip
   ```
3. **Recrea los symlinks** (obligatorio: el zip los trae registrados, no como enlaces) —
   ejecútalo **dentro de `usr-n/`**:
   ```sh
   cat SYMLINKS.txt | awk -F "←" '{system("ln -s \""$1"\" \""$2"\"")}'
   ```
4. **Inicia Termux en sesión FAILSAFE**: desde la UI de Termux → *New session* → *failsafe*
   (si el bootstrap estuviera roto, la app ofrece la sesión failsafe automáticamente).
5. En la sesión failsafe, **reemplaza** `usr/` por el contenido nuevo:
   ```sh
   cd /data/data/com.termux/files
   rm -fr usr/
   mv usr-n/ usr/
   ```
6. **Sal de failsafe y abre una sesión normal.** En el siguiente arranque la app ve `$PREFIX`
   no vacío y lo acepta.

> En una sesión failsafe `$PREFIX` apunta a la base estática de la app
> (`/data/data/com.termux/files/usr`), que no ha sido reemplazada todavía — por eso el
> reemplazo se hace ahí con seguridad.

### Verificación post-instalación

```sh
dnf5 --version                          # versión instalada
dnf5 repolist                           # lista el repo termux
dnf5 -y install dnf-hello && dnf-hello  # → "dnf5 funciona en Termux!"
```

### Notas y advertencias del modo bootstrap

- **El repo RPM solo tiene 8 paquetes hoy** (los del stack del proyecto). El resto del sistema
  (la base de termux-pacman convertida) **no es actualizable vía dnf5** hasta que el ecosistema
  crezca: `dnf5 install <paquete>` solo puede instalar lo que exista en el repo. El sistema
  base queda estático hasta entonces (es el siguiente hito del proyecto).
- **Clave GPG del repo**: se importa **automáticamente en el primer uso** (patch `0015` de
  dnf5: el auto-import de la `gpgkey` se dispara ante "Bad GPG signature"). Con
  `gpgcheck=1 repo_gpgcheck=1`, dnf5 valida paquetes y metadata sin prompt tras el import.
- **Paquetes base convertidos**: se convierten con `AutoReqProv: no` (sin dependencias
  automáticas declaradas), de modo que el solucionador no se pierde con deps inventadas.
- El **tag de release** usa el formato `bootstrap-YYYY.MM.DD-rN+dnf5.android-7`; al copiar la
  URL del release, GitHub codifica el `+` como `%2B`.

---

## Solución de problemas

| Síntoma | Causa / solución |
|---|---|
| `dnf5 history list` crashea con **SIGSEGV (139)** | **Ya corregido** (Fase 1.4): era un callback global de sqlite3 en rpm 4.18.1; el fix (backport 4.18.2, `termux-remove-sqlite3-global-log.patch`) viene horneado en el `rpm` del stack. Si el síntoma persiste, actualiza `rpm` al `4.18.1-4` |
| **Errores GPG** al instalar desde el repo (`Bad GPG signature`, clave no encontrada) | Importar la clave pública manualmente: `gpg --import <(curl -fsSL https://Leonisaurov.github.io/dnf-for-termux/rpm/termux-rpm.gpg)` — o borrar la caché de metadata (`$PREFIX/var/cache/dnf`) para que el auto-import (patch 0015) se dispare de nuevo |
| Problemas con la **rpmdb** (sqlite) | Al desinstalar, el script hace **backup de la rpmdb en `$TMPDIR`** (`rpmdb-backup-uninstall-*`); puedes restaurarla desde ahí. Con `--purge` también se puede reconstruir reinstalando el stack |
| `install-dnf-termux.sh` falla por `gh` | El modo online requiere `gh` instalado y autenticado (`pkg install gh` + `gh auth login`). Alternativa: modo offline con un directorio de `.pkg` |
| Los scripts dicen "esto solo funciona dentro de Termux" | `install/uninstall` verifican `$PREFIX` y la presencia de `pacman`: hay que ejecutarlos **dentro de una sesión de Termux** con termux-pacman |

---

## Referencias

- **Repo RPM (GitHub Pages)**: https://leonisaurov.github.io/dnf-for-termux/rpm/ — 8 RPMs
  firmados del stack + `repodata/` firmada + `termux-rpm.gpg` (clave
  `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9`).
- **Releases (bootstrap)**: https://github.com/Leonisaurov/dnf-for-termux/releases
- **Spec del generador del bootstrap**: [`BOOTSTRAP-DESIGN.md`](../BOOTSTRAP-DESIGN.md)
- **Scripts**: `scripts/install-dnf-termux.sh`, `scripts/uninstall-dnf-termux.sh`,
  `scripts/generate-bootstrap-dnf5.sh`
- **Registro de progreso**: [`PROGRESS.md`](../PROGRESS.md) · **Reporte formal**:
  [`REPORT.md`](../REPORT.md)
