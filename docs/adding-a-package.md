# Guía: cómo añadir un paquete a dnf-for-termux

Guía paso a paso para añadir un paquete nuevo al overlay de dnf-for-termux. El flujo completo
es: crear `packages/<pkg>/` → validar localmente → añadir a la matrix de CI → commit+push →
deploy del repo RPM → probar en el dispositivo.

## Requisitos

- **El paquete debe compilar con termux-packages** (el CI clona `termux/termux-packages`, copia
  el overlay `packages/` encima y compila con el sistema oficial).
- **Si el paquete ya existe upstream** en termux-packages: copia el `build.sh` de
  `termux-packages master` y adáptalo (añade REVISION o patches si es necesario).
- **Si es un port nuevo** (no existe en termux-packages): sigue las convenciones del framework
  (`TERMUX_PKG_HOMEPAGE`, `TERMUX_PKG_DESCRIPTION`, `TERMUX_PKG_LICENSE`, `TERMUX_PKG_VERSION`,
  `TERMUX_PKG_SRCURL`, `TERMUX_PKG_SHA256`, `TERMUX_PKG_DEPENDS`, etc.).
- El resultado debe **cross-compilar a aarch64 real**: cada ELF del `.pkg` debe ser aarch64
  (el CI lo verifica con `file`).

## Paso 1 — Crear `packages/<pkg>/`

Crea el directorio con el `build.sh` (y, si aplica, los `*.patch`/`*.diff` y archivos
adicionales en el mismo directorio).

### Notas clave

- **`TERMUX_PKG_VERSION` / `TERMUX_PKG_REVISION`**:
  - Para un paquete del overlay que ya existe en termux-main y se **parchea** manteniendo la
    MISMA versión, **sube la `REVISION`**.
  - ⚠️ **La trampa del `--needed`**: `pacman -U --needed` **salta** un paquete cuya versión no
    es mayor que la instalada. Si parcheas un paquete que ya existe en termux-main con la
    misma versión, el `.pkg` del CI no reemplazaría al instalado. Por eso los paquetes
    parcheados del overlay llevan REVISION más alta que la oficial:
    - `rpm`: **4.18.1-4** (oficial de termux-main: `4.18.1-2`).
    - `libpopt`: **1.19-4** (oficial: `1.19-3`).
  - Ejemplo en `packages/rpm/build.sh`:
    ```sh
    TERMUX_PKG_VERSION=4.18.1
    TERMUX_PKG_REVISION=4   # > 4.18.1-3 anterior y > el oficial 4.18.1-2; si no, pacman -U --needed salta el parcheado
    ```

- **Script packages** (sin fuente que compilar): usa `TERMUX_PKG_SKIP_SRC_EXTRACT=true` y
  guarda el script en `$TERMUX_PKG_BUILDER_DIR` (el directorio del paquete). Plantilla:
  `packages/dnf-hello/`:
  ```sh
  TERMUX_PKG_VERSION=1.0
  TERMUX_PKG_REVISION=1
  TERMUX_PKG_SKIP_SRC_EXTRACT=true
  TERMUX_PKG_BUILD_IN_SRC=true

  termux_step_make_install() {
      install -Dm755 "$TERMUX_PKG_BUILDER_DIR/dnf-hello" "$TERMUX_PREFIX/bin/dnf-hello"
  }
  ```

- **Patches**: el framework los aplica **por orden alfabético** (`0001-...`, `0002-...`, …).
  Valida cada patch antes de commitear:
  ```sh
  patch --dry-run -F0 -p1 < packages/<pkg>/NNNN-nombre.patch   # 0 fuzz, sin saltos
  git apply --check packages/<pkg>/NNNN-nombre.patch            # debe aplicar limpio
  ```
  Nota: un `.diff` (en vez de `.patch`) no lo aplica el pipeline automático del framework;
  hay que aplicarlo manualmente en `termux_step_post_get_source` (ver el caso
  `0002-termux-paths-config-main.diff` en `packages/dnf5/build.sh`).

## Paso 2 — Validación local (opcional)

```sh
bash -n packages/<pkg>/build.sh          # sintaxis OK
```

Si el dispositivo tiene las herramientas de build, puedes compilar localmente con `tcr`
(termux create package) para iterar rápido antes de subir al CI.

## Paso 3 — Añadir a la matrix de `.github/workflows/build.yml`

Añade el nombre del paquete a la lista `matrix.pkg`. Ejemplo del diff real (commit
`b418537`, que añadió `dnf-hello`):

```diff
       matrix:
-        pkg: [zchunk, libcomps, libsolv, librepo, rpm, libpopt, createrepo-c, dnf5]
+        pkg: [zchunk, libcomps, libsolv, librepo, rpm, libpopt, createrepo-c, dnf-hello, dnf5]
```

Cada paquete de la matrix genera un artifact `${{ matrix.pkg }}-aarch64` con su `.pkg.tar.xz`.

## Paso 4 — Commit + push

Haz commit del `packages/<pkg>/` (y del cambio en `build.yml` si lo hiciste en el paso 3) y
haz push a `main`. El CI (disparo manual `workflow_dispatch` desde la pestaña Actions) compila
el paquete.

**Comportamiento de la caché anti-rebuilds**: el CI solo recompila **lo que cambió**. El hash
de inputs de cada paquete incluye su `build.sh` + patches **y los de sus DEPENDS del overlay**.
Consecuencias:

- Un paquete nuevo compila desde cero.
- Si tu paquete **depende** de otros del overlay, el hash de la dependencia incluye los
  `build.sh`/patches de tu paquete → **recompilan juntos** (así, por ejemplo, un cambio en
  `packages/rpm/` recompila dnf5, librepo, libsolv y createrepo-c).

## Paso 5 — Deploy

1. Abre el workflow de deploy:
   `https://github.com/Leonisaurov/dnf-for-termux/actions/workflows/deploy.yml`
2. **Run workflow** (opcional: indica el run de `build.yml` a publicar; vacío = último
   exitoso).
3. El workflow convierte cada `.pkg` a `.rpm` firmado (`scripts/pkg2rpm.sh` + GPG con el
   secret `RPM_SIGNING_KEY`), genera `repodata/` con `createrepo_c`, firma `repomd.xml` y
   publica en gh-pages/rpm/.
4. **Verifica** que el `.rpm` esté publicado (HTTP 200):
   ```sh
   curl -sI https://leonisaurov.github.io/dnf-for-termux/rpm/<pkg>-<version>-<release>.aarch64.rpm
   ```

## Paso 6 — Probar en el dispositivo

```sh
# Desde el repo RPM firmado remoto (gpgcheck=1 repo_gpgcheck=1)
dnf5 -y install <pkg>

# Si es una librería: reinstalar el .pkg con pacman es más directo
pacman -U <pkg>-<version>-aarch64.pkg.tar.xz
```

## Troubleshooting

| Síntoma | Causa probable | Solución |
|---|---|---|
| (a) `pacman -U --needed` **salta** el paquete | El paquete ya está instalado con la misma (o mayor) versión | **Bump `TERMUX_PKG_REVISION`** (rpm: 4.18.1-4, libpopt: 1.19-4) para que el `.pkg` del overlay sea mayor que el de termux-main |
| (b) El deploy falla en la **firma** | El secret `RPM_SIGNING_KEY` no está configurado (o cambió la clave) | Verificar en Settings → Secrets and variables → Actions que `RPM_SIGNING_KEY` existe y es la clave privada de firma |
| (c) **Verify AArch64** falla en CI | Algún ELF del `.pkg` no es aarch64 (o se coló un binario de otra arquitectura) | Revisar el log: extraer el `.pkg`, `file` sobre los ELF; arreglar enlazado/empaquetado |
| (d) dnf5 no **resuelve** el paquete desde el repo | `repodata/` desactualizada o deps versionadas mal emitidas | Regenerar la `repodata` (`scripts/mkrepo.sh <dir>` o `createrepo_c <dir>`) y revisar que las deps versionadas de `primary.xml` lleven `flags/epoch/ver/rel` (ver fix `058d61e`) |
