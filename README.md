# dnf-for-termux

Port del gestor de paquetes **DNF5** —y su ecosistema RPM: `rpm`, `libsolv`, `librepo`,
`libcomps`, `zchunk`, `createrepo-c`— a **Termux/Android** (aarch64), construido como un
**overlay sobre [`termux/termux-packages`](https://github.com/termux/termux-packages)**.

El proyecto **funciona de verdad en un dispositivo Android real**: `dnf5` instala RPMs
**firmados** desde un repositorio remoto con verificación GPG completa de paquetes y metadata
(`gpgcheck=1 repo_gpgcheck=1`), con historial de transacciones funcional y un
instalador/desinstalador simétricos.

## Estado

- **dnf5 5.4.2.1 operativo y validado en el dispositivo** (Fases 0–1.5 cerradas): instala y
  ejecuta RPMs reales, `dnf5 history list` sin SIGSEGV, firma GPG de paquetes y metadata
  operativa, deploy automatizado en CI.
- **Bootstrap del sistema (dnf5 como único gestor)**: generado y publicado como GitHub
  Release (`bootstrap-aarch64.zip`, ~73 MB, 95+ paquetes RPM).
- Fuente de verdad del detalle: [`PROGRESS.md`](PROGRESS.md) y [`REPORT.md`](REPORT.md).

## Instalación

Hay **dos modos** de usar dnf5 en Termux (guía detallada:
[`docs/INSTALLATION.md`](docs/INSTALLATION.md)):

| Modo | Rol de dnf5 | Comando rápido |
|---|---|---|
| **1. Alterno** | Convive con pacman/apt (no toca el sistema) | `bash scripts/install-dnf-termux.sh --assume-yes` |
| **2. Principal (bootstrap)** | Único gestor (reemplaza `usr/`) | Descargar `bootstrap-aarch64.zip` de las **Releases** y seguir la guía |

### Modo alterno (probarlo sin riesgos)

Requiere Termux con **termux-pacman** y `gh` (GitHub CLI) autenticado. Instala los 8 paquetes
del stack (`dnf5`, `rpm`, `libpopt`, `libsolv`, `librepo`, `libcomps`, `zchunk`,
`createrepo-c`) desde los artifacts del último build exitoso del CI:

```sh
bash scripts/install-dnf-termux.sh --assume-yes   # → dnf5 --version OK
dnf5 -y install dnf-hello && dnf-hello            # → "dnf5 funciona en Termux!"
```

Desinstalación: `bash scripts/uninstall-dnf-termux.sh` (`--purge` para borrar también clave de
firma y stagings — **cuidado**: `--purge` elimina `$HOME/dnf-gpg`, la clave de firma del repo).

### Modo principal (bootstrap, dnf5 como único gestor)

Descarga el asset **`bootstrap-aarch64.zip`** del release más reciente con tag
`bootstrap-...-rN+dnf5.android-7` en las **[Releases](https://github.com/Leonisaurov/dnf-for-termux/releases)**
(primer release: `bootstrap-2026.08.10-r1+dnf5.android-7`), verifica su sha256 y sigue los
pasos de instalación en sesión failsafe de [`docs/INSTALLATION.md`](docs/INSTALLATION.md)
(flujo "Switching package manager" de la wiki de Termux).

## Recursos

| Recurso | URL |
|---|---|
| Repo RPM (GitHub Pages) | https://leonisaurov.github.io/dnf-for-termux/rpm/ |
| Clave pública del repo | https://leonisaurov.github.io/dnf-for-termux/rpm/termux-rpm.gpg |
| Releases (bootstrap) | https://github.com/Leonisaurov/dnf-for-termux/releases |
| Workflow build (manual) | https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/build.yml |
| Workflow deploy (manual) | https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/deploy.yml |
| Workflow bootstrap | https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/bootstrap.yml |
| Reporte formal | [`REPORT.md`](REPORT.md) |

## Documentación

- [`docs/INSTALLATION.md`](docs/INSTALLATION.md) — guía de instalación (modo alterno y bootstrap)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — arquitectura
- [`docs/CI-PIPELINE.md`](docs/CI-PIPELINE.md) — pipeline de CI/CD
- [`docs/adding-a-package.md`](docs/adding-a-package.md) — cómo añadir un paquete al overlay
- [`BOOTSTRAP-DESIGN.md`](BOOTSTRAP-DESIGN.md) — spec del generador del bootstrap
- [`PROGRESS.md`](PROGRESS.md) — registro de progreso por sesiones
