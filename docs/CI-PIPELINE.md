# CI/CD Pipeline - dnf-for-termux

## Arquitectura

```
GitHub Actions (ubuntu-latest)
  └── Container: ghcr.io/termux/package-builder:latest
       ├── Cross-compiler: aarch64-linux-android-*
       ├── NDK: android-ndk (r26+)
       └── Target: aarch64 (ARM64)
            ├── zchunk     → .rpm
            ├── libcomps   → .rpm
            ├── libsolv    → .rpm
            ├── librepo    → .rpm
            ├── dnf5       → .rpm
            └── rpm        → .rpm
                 ↓
          GitHub Pages (RPM repository)
          GitHub Releases (binary artifacts)
```

## Workflows

| Workflow | Trigger | Descripción |
|----------|---------|-------------|
| `build.yml` | push, PR, manual | Compila todo el stack |
| `update-submodules.yml` | semanal, manual | Actualiza submódulos upstream |

## Jobs del Pipeline

1. **validate** - Verifica parches y submódulos (~2 min)
2. **build-component** - Compila cada componente (paralelo, ~15-45 min c/u)
3. **create-repo** - Genera metadatos RPM y despliega a GitHub Pages
4. **release** - Crea GitHub Release cuando se pushea un tag

## Cómo usar

### Build manual de un componente específico
```yaml
# Ir a: Actions → build → Run workflow → Component: libsolv
```

### Build completo
Push a `main` o `develop` gatilla build automático de todos los componentes.

### Release
```bash
git tag v0.1.0-alpha
git push origin v0.1.0-alpha
```

## Cache

Se cachean los build artifacts entre runs usando `actions/cache@v4`:
- `/home/builder/.termux-build/*/output/` → Paquetes compilados
- `/home/builder/.termux-build/*/build/` → Objetos intermedios

Cache key: `termux-<component>-<hash de build.sh + patches>`

## Repositorio RPM público

URL: `https://<tu-org>.github.io/dnf-for-termux/rpm/`

Configurar en Termux:
```ini
[termux-rpm]
name=Termux DNF Repository
baseurl=https://<tu-org>.github.io/dnf-for-termux/rpm/
enabled=1
gpgcheck=0
```

## Resolución de problemas

| Problema | Causa | Solución |
|----------|-------|----------|
| Build falla en CI | Patch desactualizado | Revisar `patches/*/` |
| Artifact vacío | build.sh no produce output | Verificar BUILD_DIR |
| Container no inicia | Límite de GitHub Actions | Usar `ubuntu-latest` en vez de container |
| RPM repo vacío | No hay .rpm generados | Verificar build-component |
