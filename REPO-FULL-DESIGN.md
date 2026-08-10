# Diseño: Repositorio RPM COMPLETO en gh-pages (`repo-full`)

> Diseño conceptual (solo diseño, sin implementación). Autor: Arquitecto.
> Objetivo: que `https://Leonisaurov.github.io/dnf-for-termux/rpm/` contenga el stack
> del proyecto (8-9 RPM) **y** los ~93-95 RPM convertidos de termux-pacman (el cierre que
> el bootstrap ya instala), todos firmados con la misma clave, para que dnf5 opere como
> gestor oficial y coherente (instalar / actualizar / ver como "del repo oficial" todo lo
> que el bootstrap tiene instalado).

---

## Estado de implementación (2026-08-09)

**IMPLEMENTADO** (builder): correcciones C1/M1–M6/m1–m12 aplicadas. Pendiente: primer run de
CI (dry-run → producción) + verificación on-device + borrado de `deploy.yml` (M6).

| Id | Corrección | Estado |
|----|-----------|--------|
| C1 | `deploy.yml` **deshabilitado** (`on: []` + comentario), NO borrado; input `dry-run` en `repo-full.yml` (build + verify sin publicar; evidencia en step summary — ver decisión de permisos abajo) | Aplicada |
| M1 | CA-6: verificación instalados ⊆ repo excluye `gpg-pubkey-*` | Aplicada (§9) |
| M2 | CA-6 reportable (warning con delta) cuando el cierre se resuelve sobre el `main.json` del run (no del bootstrap); no criterio duro | Aplicada (§9) |
| M3 | CA-7: `dnf5 install <convertido instalado>` → "already installed" **O** "actualizable", sin errores de firma/repodata | Aplicada (§9) |
| M4 | `enable_jekyll: false` en peaceiris + `.nojekyll` explícito en el staging (el clean publish borraría el `.nojekyll` actual de gh-pages si no) | Aplicada |
| M5 | assert `total -ge expected` (no `==`) contra `pkg-table.txt` (lo descargable del generador) | Aplicada |
| M6 | Checklist de merge documentado (bootstrap.yml regresión + repo-full dry-run antes del run de producción) | Aplicada (abajo) |
| m1/m2 | `dnf-hello` **MANTENIDO** en el repo completo (9 del stack): gh-pages lo tiene; `update-stack` NO lo filtra | Aplicada |
| m3 | `stack_count` calculado dinámicamente (`ls stack/*.rpm | wc -l`), sin hardcodear 8 | Aplicada |
| m4 | index.html del staging se copia del checkout (main, ya con el fix del overflow); gh-pages == main al primer run (verificar identidad post-publicación) | Aplicada |
| m5 | `rpm --addsign` idempotente sobre .rpm ya firmados; el assert `rpm -K` final valida (comentario en workflow) | Aplicada |
| m6 | Fingerprint GPG fijo `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9` en workflow + generador; rotar en **ambos** si cambia | Aplicada |
| m7 | `update-stack`: check de artifacts del run (expiración 90 días) ANTES de `gh run download`, fallo claro | Aplicada |
| m8 | Riesgo residual (gh-pages roto + artifacts expirados = sin recuperación) documentado en el workflow | Aplicada |
| m9 | CA-1: `N = stack + manifest` dinámico como fuente de verdad (assert `>=`, warning si < 100) | Aplicada |
| m10 | CA-5 especifica "nombres de archivo .rpm" | Aplicada (§9) |
| m11 | `permissions: contents: write, actions: read` explícito | Aplicada |
| m12 | Paso in-workflow `gpg --verify repomd.xml.asc repomd.xml` antes del publish (CA-3 verificado en CI) | Aplicada |

### Decisiones de implementación

- **`dnf-hello` mantenido en el repo completo** (9 del stack): el generador nunca lo excluye
  del cierre (no está en `main.json` ni en `PROJECT_STACK`, así que el BFS no lo resuelve); el
  workflow lo añade explícitamente en su resolución de stack (gh-pages o artifacts).
- **`deploy.yml` deshabilitado, no borrado** (`on: []`): único writer pasa a ser `repo-full.yml`;
  borrar tras validar el primer run de producción (recuperable de git).
- **`enable_jekyll: false` + `.nojekyll` explícito** en el staging: el clean publish (sin
  `keep_files`) reemplaza TODO el árbol y borraría el `.nojekyll` actual de gh-pages si no se
  regenera en cada run.
- **dry-run SIN artifact upload**: `actions: read` (m11) NO permite `actions/upload-artifact`
  (exige `actions: write` — ver el CI del propio repo actions/upload-artifact). La evidencia del
  dry-run queda en `GITHUB_STEP_SUMMARY` + logs del job. Si se quiere el árbol completo como
  artifact, subir a `actions: write` (desviación de m11 a decisión del orquestador).
- **Sin input `run` manual en update-stack**: se resuelve siempre el último run exitoso de
  `build.yml` (skeleton del builder con inputs `dry-run` + `update-stack`).

### Checklist de merge (M6)

Antes de mergear este cambio en `main`:
1. [ ] Correr `bootstrap.yml` (regresión: el modo bootstrap del generador sigue pasando).
2. [ ] Correr `repo-full` con `dry-run=true` (staging + verificación sin publicar).
3. [ ] Solo entonces: run de producción de `repo-full` + verificación CA-1..CA-5 (§9).
4. [ ] Tras validar: borrar `deploy.yml`.

---

## 0. Resumen ejecutivo

- **Un único workflow nuevo** `.github/workflows/repo-full.yml` pasa a ser el **único escritor**
  de `gh-pages/rpm/`. `deploy.yml` queda **superseded y deshabilitado** (`on: []`; ver
  "Estado de implementación" — C1) y se borra tras validar el primer run.
- El cierre termux-pacman (~93 .rpm) **no se expone como artifact de bootstrap.yml**: se
  **re-convierte en el propio workflow** reutilizando el generador existente con un modo nuevo
  (`--mode repo`). Cero duplicación de la lógica BFS/conversión/firma.
- El stack del proyecto por defecto se toma de **gh-pages** (canónico, ya firmado, lo mismo
  que instala el bootstrap); opcionalmente se refresca desde artifacts de `build.yml`
  (input `update-stack=true`) tras un build nuevo.
- Publicación **atómica y limpia**: se construye un árbol staging `{index.html, rpm/}` y se
  publica completo (sin `keep_files`), de modo que **no se borra index.html**, **no quedan
  .rpm obsoletos** y gh-pages queda regenerable desde cero.
- Firma y gpgcheck: se reutiliza el patrón probado de `deploy.yml` (macros `%__gpg_sign_cmd`,
  `rpm --addsign`, `rpm -K` con rpmdb local, `createrepo_c`, firma de `repomd.xml`,
  export de `termux-rpm.gpg`). La clave es la misma (`dnf-for-termux`,
  fingerprint `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9`) → `gpgcheck=1` y `repo_gpgcheck=1`
  del `termux.repo` funcionan sin ningún cambio de configuración.

---

## 1. Estrategia global

### Opciones evaluadas

| Opción | Descripción | Ventajas | Inconvenientes |
|--------|-------------|----------|----------------|
| **a. Ampliar deploy.yml** | El workflow actual además convierte y publica el cierre | Un solo archivo, un solo flujo | `deploy.yml` es frágil (conversión inline con `wc -l` sin assert); mezclar stack + cierre en el mismo paso complica su mantenimiento; sigue necesitando el refactor del cierre |
| **b. Ampliar bootstrap.yml** | Un job nuevo publica los convertidos (artifact `$WORK/rpms`) + stack | Reutiliza el cierre ya generado | Acopla la publicación del repo a la cadencia del bootstrap (semanal); requiere exponer `$WORK/rpms` (cambio de contrato del generador); sube decenas de MB extra por artifact; el stack seguiría viviendo en deploy.yml → colisión |
| **c. Workflow nuevo `repo-full.yml`** | Workflow independiente, único escritor de `rpm/`, que hace TODO: stack + cierre + firma + repodata + publicación | Un solo dueño de `rpm/` (sin colisiones); reutiliza el generador vía `--mode repo` (cero duplicación de lógica); cadencia propia (manual + semanal); reversible (deploy.yml se puede recuperar de git si algo falla) | Requiere eliminar/superseder `deploy.yml` y añadir un flag al generador |

### Recomendación: **opción c — `repo-full.yml` como único escritor**

Justificación:

1. **Colisión cero**: `createrepo_c` regenera `repodata/` a partir del contenido total del
   directorio. Si `deploy.yml` (stack) y `repo-full.yml` (completo) escribieran ambos en
   `gh-pages/rpm/`, el repodata de uno pisaría/ignoraría al otro y el `repomd.xml` quedaría
   **incoherente con el contenido real** (p. ej. repodata que solo lista el stack mientras el
   dir tiene ~100 .rpm). La única solución robusta es **un solo workflow publica `rpm/`
   completo**.
2. **Coherencia de versiones**: el cierre se re-resuelve con el MISMO código del generador
   que usa el bootstrap (`main.json` en tiempo de ejecución) y el stack por defecto se toma
   de gh-pages (lo mismo que el bootstrap instala en su PASO 5). Repo ⊇ bootstrap por
   construcción.
3. **Complejidad controlada**: el workflow reutiliza código probado (el generador) en vez de
   replicar el BFS. El diff del generador es mínimo (un flag `--mode` + salida temprana).
4. **Frecuencia**: `workflow_dispatch` (manual, tras un build) + `schedule` semanal alineado
   con bootstrap. **No** se dispara automáticamente al éxito de `build.yml`: build.yml es una
   CI de prueba (matrix `fail-fast: false`) y auto-publicar cada build acoplaría experimentos
   al repo de producción; el refresh del stack debe ser deliberado (`update-stack=true`).

---

## 2. Fuente de los convertidos (~93 .rpm)

### Opciones evaluadas

| Opción | Descripción | Ventajas | Inconvenientes |
|--------|-------------|----------|----------------|
| **Artifact de bootstrap.yml** | `upload-artifact` extra `rpms-convertidos` con `path $WORK/rpms/` | No re-convierte | Acopla el repo a la cadencia del bootstrap (el repo solo se actualiza cuando corre bootstrap); obliga a cambiar el contrato del generador para exponer `$WORK/rpms` (side-effect fuera de su contrato "zip + manifest"); transferencia extra de decenas de MB; si bootstrap falla, el repo no se actualiza; duplicidad con el stack (que seguiría en deploy.yml → colisión) |
| **Re-convertir en el workflow** (compartiendo el script del generador) | El workflow descarga `main.json` + `.pkg` y convierte con el MISMO generador en modo repo | Determinista e idempotente; el generador ya lo hace hoy (93/93 firmados y verificados); sin dependency del artifact; un solo flujo | Re-descarga ~30-70 MB y re-convierte (pocos minutos; el job build de bootstrap ya convierte los 93 sin problema) |

### Recomendación: **re-convertir en el workflow usando el generador con `--mode repo`**

- El cierre transitivo (BFS sobre `DEPENDS` con fallback `PROVIDES`, exclusión del stack del
  proyecto en 2 puntos, `fix_any_arch_pkg`, `AutoReqProv:no`, Epoch de Termux) es la lógica
  más frágil del proyecto (corregida con C1-C6/M1-M9). **No debe duplicarse** en un workflow.
- El tamaño real de los ~93 `.pkg.tar.xz` es del orden del contenido del zip del bootstrap
  (~73 MB comprimido); la descarga+conversión del job `build` de bootstrap.yml ya lo hace
  dentro del límite de tiempo del runner. La porción "repo" (pasos 1-4 del generador) es un
  subconjunto → tiempo estimado < 30-60 min en `ubuntu-24.04-arm`.
- Evita el límite/expiración de artifacts (90 días): no hay artifact grande de por medio.

---

## 3. Refactor compartido: interfaz de `generate-bootstrap-dnf5.sh --mode repo`

**Decisión**: NO se extrae un script nuevo (`resolve-and-convert.sh`). Se **añade un modo al
generador existente** (`--mode repo`), porque:

- El generador (729 líneas, maduro y verificado) ya contiene `resolve_package_set`,
  `download_pkgs`, `fix_any_arch_pkg`, `convert_pkgs` y `sign_rpms`. Extraerlos a un script
  aparte sería **mover ~200 líneas** con riesgo de regresión sobre un flujo probado, y
  crearía dos implementaciones del cierre con riesgo de drift.
- El diff es mínimo: un flag + salida temprana en `main()`. El flujo bootstrap (14 pasos,
  zip, rpmdb) queda **intacto**.

### Interfaz

```
scripts/generate-bootstrap-dnf5.sh --mode repo --out DIR [--arch aarch64] [--work DIR] \
                                   [--sign-key PATH] [--no-project] [--help]
```

| Flag | Efecto |
|------|--------|
| `--mode repo` | Ejecuta pasos 1-4 (preparar, resolver cierre, descargar .pkg, convertir+firmar) y **sale** antes del PASO 5+. Copia los .rpm firmados y `manifest.txt` a `OUT_DIR`. No toca rpmdb, ni zip, ni release. |
| `--mode bootstrap` (default) | Flujo actual completo de 14 pasos (sin cambios). |
| `--no-project` | En modo repo, **salta** `download_project_rpms` (no baja el stack de gh-pages). Se usa cuando el stack lo aporta el workflow desde artifacts de build.yml (`update-stack=true`). |
| `--out DIR` | En modo repo, `DIR` recibe los .rpm firmados + `manifest.txt`. (En bootstrap, el zip, como hoy.) |

### Cambio mínimo especificado (para el builder)

En `parse_args()`:

```bash
MODE="bootstrap"          # nuevo default
NO_PROJECT=""
# en el case:
--mode)        MODE="${2:?--mode necesita un valor}"; shift 2 ;;
--no-project)  NO_PROJECT=1; shift ;;
# tras el loop:
[ "$MODE" = bootstrap ] || [ "$MODE" = repo ] || die "modo inválido: $MODE (bootstrap|repo)"
```

En `main()`, tras `convert_pkgs` (que ya firma, M9):

```bash
prepare_dirs
resolve_package_set
download_pkgs
convert_pkgs
if [ "$MODE" = repo ]; then
  [ -n "$NO_PROJECT" ] || download_project_rpms      # stack canónico desde gh-pages (ya firmado)
  cp "$WORK"/rpms/*.rpm "$OUT_DIR"/
  [ -n "$NO_PROJECT" ] || cp "$WORK"/rpms-project/*.rpm "$OUT_DIR"/
  cp "$WORK/manifest.txt" "$OUT_DIR/manifest.txt"
  log "modo repo: $(ls "$OUT_DIR"/*.rpm | wc -l) .rpm + manifest en $OUT_DIR"
  exit 0
fi
download_project_rpms
# ... resto del flujo bootstrap intacto ...
```

Notas:

- `require()` **no se toca**: el workflow instala el superset de herramientas que bootstrap.yml
  ya usa (rpm jq zip unzip sqlite3 binutils curl gpg libarchive-tools file gzip) + `createrepo-c`.
- `sign_rpms()` en modo repo firma los convertidos (M9: "siempre"). El workflow hará un
  `rpm --addsign` adicional sobre el dir completo (idempotente) para cubrir el stack. La
  re-firma de los convertidos es barata (cabecera de ~1 KB) y deja una única puerta de
  verificación (`rpm -K` == total).
- En modo repo **no se necesita** `SUDO` ni rpmdb de rootfs; el workflow pasa `--sign-key "$HOME/rpmdb"`.

---

## 4. Fuente del stack y coherencia de versiones

**Decisión (task 5)**: el stack por defecto se descarga de **gh-pages** (canónico), NO de los
artifacts de build.yml, y solo se refresca explícitamente con `update-stack=true`.

| Fuente | Cuándo | Efecto |
|--------|--------|--------|
| **gh-pages** (default) | `schedule` semanal o dispatch sin flags | `download_project_rpms` (PASO 5 del generador, patrón probado M8 con grep anclado sobre `primary.xml`) baja los 8 .rpm del stack YA FIRMADOS. Repo-publicado == lo que el bootstrap instala, **sin riesgo de regresión** (nunca publica un stack más nuevo que el verificado). |
| **build.yml artifacts** (`update-stack=true`) | Dispatch deliberado tras un build nuevo | `gh run download` del run (input `run` o último exitoso) + conversión con `pkg2rpm.sh` → el stack se refresca. El maintainer inspecciona el run ANTES de pedirlo (evita publicar un build roto por accidente). |

**Versiones resultantes en el repodata:**

- **Stack**: la de gh-pages (o la del run aprobado con `update-stack`). El bootstrap descarga
  el stack de gh-pages (PASO 5) → coinciden por construcción.
- **Convertidos**: `main.json` en el momento del run (misma fuente y resolución que el
  bootstrap) → misma NEVRA que el bootstrap instaló. Si termux-pacman subió versión entre
  runs, el repo tiene una **más nueva** → dnf5 muestra la actualización (deseable). No se
  requiere identidad byte a byte con lo instalado (rpmbuild embebe `BUILDTIME`, el sha difiere);
  **basta la igualdad de NEVRA** para que dnf5 vea "ya instalado" o "actualizable".
- **repodata**: `createrepo_c` corre sobre el dir **total** en el mismo job → `primary.xml`
  siempre refleja TODOS los .rpm publicados. Publicación monotónica (clean publish): cada run
  reemplaza el estado completo, sin repodata parcial ni .rpm huérfanos.

**dnf-hello** (artifact de build.yml, excluido del bootstrap por diseño): en modo default el
repo publica los **8** de `PROJECT_STACK` (lo que el bootstrap instala); con `update-stack`
se publican los **9** artifacts (incluido dnf-hello). Delta menor y documentado; si se quiere
uniformidad estricta, filtrar `dnf-hello-*.rpm` en `update-stack` (una línea) o añadirlo a
`PROJECT_STACK` (impactaría el bootstrap, no recomendado).

---

## 5. Workflow YAML completo (`repo-full.yml`)

```yaml
# ============================================================================
# repo-full — publica el REPOSITORIO RPM COMPLETO en gh-pages/rpm/
# ============================================================================
# Único escritor de gh-pages/rpm/ (sustituye a deploy.yml).
#   - Stack del proyecto: desde gh-pages (canónico, ya firmado) por defecto;
#     opcionalmente desde artifacts de build.yml (input update-stack=true).
#   - Cierre termux-pacman (~93 .rpm convertidos): re-resuelto desde main.json
#     por generate-bootstrap-dnf5.sh --mode repo (mismo cierre que el bootstrap).
#   - Todos firmados con la MISMA clave (RPM_SIGNING_KEY / dnf-for-termux)
#     -> gpgcheck=1 + repo_gpgcheck=1 del termux.repo funcionan sin cambios.
#   - Publicación atómica: staging con index.html + rpm/ -> gh-pages limpio
#     (nada de keep_files; sin .rpm obsoletos; sin borrar index.html).
# ============================================================================

name: repo-full

on:
  workflow_dispatch:
    inputs:
      update-stack:
        description: 'true = refrescar el stack desde artifacts de build.yml; false = stack desde gh-pages'
        required: false
        default: 'false'
        type: boolean
      run:
        description: 'Run number de build.yml para update-stack (vacío = último exitoso)'
        required: false
        type: string
  schedule:
    - cron: "30 0 * * 0"   # domingo 00:30 UTC (30 min después del bootstrap semanal)

concurrency:
  group: rpm-repo-publish
  cancel-in-progress: false

jobs:
  publish:
    runs-on: ubuntu-24.04-arm          # macros rpm aarch64 (lección deploy.yml)
    permissions:
      contents: write                  # publicar gh-pages
      actions: read                    # gh run download/list (solo update-stack)
    steps:
      - uses: actions/checkout@v5

      # --- herramientas: igual que bootstrap.yml (job build) + createrepo-c ---
      - name: Instalar herramientas
        run: |
          sudo apt-get update
          sudo apt-get install -y rpm jq zip unzip sqlite3 binutils curl gpg \
            libarchive-tools file gzip createrepo-c

      # --- clave de firma + rpmdb local para rpm -K (patrón deploy.yml) ---
      - name: Importar clave de firma (RPM_SIGNING_KEY)
        env:
          RPM_SIGNING_KEY: ${{ secrets.RPM_SIGNING_KEY }}
        run: |
          set -euo pipefail
          if [ -z "$RPM_SIGNING_KEY" ]; then
            echo "::error::RPM_SIGNING_KEY no está configurado — set the RPM_SIGNING_KEY secret"
            exit 1
          fi
          echo "$RPM_SIGNING_KEY" | gpg --batch --import
          GPG_BIN="$(command -v gpg)"
          printf '%%_gpg_name dnf-for-termux\n%%__gpg_sign_cmd %s --batch --no-tty --no-verbose --no-armor --output %%{__signature_filename} --detach-sign --local-user %%{_gpg_name} %%{__plaintext_filename}\n' "$GPG_BIN" > "$HOME/.rpmmacros"
          "$GPG_BIN" --export --armor E4AC7735BD60196E19123DB6247EEE5F6AA25EC9 > "$HOME/rpm-pubkey.asc"
          mkdir -p "$HOME/rpmdb"
          rpm --define "_dbpath $HOME/rpmdb" --import "$HOME/rpm-pubkey.asc"

      # --- [solo update-stack] stack nuevo desde build.yml ---
      - name: Resolver run de build.yml
        if: inputs.update-stack == 'true'
        id: run
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          if [ -n "${{ github.event.inputs.run }}" ]; then
            echo "id=${{ github.event.inputs.run }}" >> "$GITHUB_OUTPUT"
          else
            echo "id=$(gh run list --workflow=build.yml --status success --limit 1 --json databaseId -q '.[0].databaseId')" >> "$GITHUB_OUTPUT"
          fi

      - name: Convertir el stack desde build.yml
        if: inputs.update-stack == 'true'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          gh run download "${{ steps.run.outputs.id }}" -D /tmp/pkgs
          mkdir -p /tmp/stack-new
          for d in /tmp/pkgs/*/; do
            pkg=$(find "$d" -name '*.pkg.tar.*' | head -1)
            [ -z "$pkg" ] && continue
            bash scripts/pkg2rpm.sh "$pkg" /tmp/stack-new
          done
          echo "stack nuevo convertido: $(ls /tmp/stack-new/*.rpm | wc -l)"

      # --- núcleo: repo mode del generador (cierre + stack canónico) ---
      - name: Resolver, convertir y firmar el cierre termux-pacman
        run: |
          set -euo pipefail
          EXTRA=""
          [ "${{ inputs.update-stack }}" = "true" ] && EXTRA="--no-project"
          ./scripts/generate-bootstrap-dnf5.sh --mode repo --out /tmp/rpm-repo \
            --sign-key "$HOME/rpmdb" $EXTRA
          echo "convertidos+stack: $(ls /tmp/rpm-repo/*.rpm | wc -l)"

      # --- [solo update-stack] merge del stack refrescado ---
      - name: Merge stack refrescado
        if: inputs.update-stack == 'true'
        run: cp /tmp/stack-new/*.rpm /tmp/rpm-repo/

      # --- firma única sobre TODO (idempotente para los ya firmados) ---
      - name: Firmar todos los RPM
        run: rpm --addsign /tmp/rpm-repo/*.rpm

      # --- verificación (assert, no print) ---
      - name: Verificar firmas de todos los RPM
        run: |
          set -euo pipefail
          total="$(ls /tmp/rpm-repo/*.rpm | wc -l)"
          ok="$(rpm -K --define "_dbpath $HOME/rpmdb" /tmp/rpm-repo/*.rpm | grep -c 'signatures OK' || true)"
          echo "firmas OK: $ok / $total"
          [ "$ok" -eq "$total" ] || { echo "::error::firmas incompletas: $ok/$total"; exit 1; }
          manifest="$(wc -l < /tmp/rpm-repo/manifest.txt)"
          stack=8
          [ "${{ inputs.update-stack }}" = "true" ] && stack="$(ls /tmp/stack-new/*.rpm | wc -l)"
          expected=$(( stack + manifest ))
          [ "$total" -eq "$expected" ] || { echo "::error::conteo inesperado $total (esperado ~$expected)"; exit 1; }
          echo "repo completo OK: $total = stack($stack) + cierre($manifest)"

      # --- repodata TOTAL + firma repomd + exportar clave pública ---
      - name: Generar repodata y firmar el repo
        run: |
          set -euo pipefail
          createrepo_c /tmp/rpm-repo
          gpg --batch --detach-sign --armor /tmp/rpm-repo/repodata/repomd.xml
          gpg --export --armor E4AC7735BD60196E19123DB6247EEE5F6AA25EC9 > /tmp/rpm-repo/termux-rpm.gpg

      # --- publicación atómica: staging (index.html + rpm/) -> gh-pages limpio ---
      - name: Preparar árbol de gh-pages
        run: |
          set -euo pipefail
          rm -rf /tmp/gh-pages-out
          mkdir -p /tmp/gh-pages-out/rpm
          cp index.html /tmp/gh-pages-out/index.html
          cp -a /tmp/rpm-repo/. /tmp/gh-pages-out/rpm/

      - name: Publicar en gh-pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: /tmp/gh-pages-out
          publish_branch: gh-pages
          # sin destination_dir ni keep_files: gh-pages == árbol staging exacto
          # (index.html conservado; rpm/ limpio sin .rpm obsoletos; peaceiris
          # añade .nojekyll automáticamente porque enable_jekyll=false)
```

**Trigger elegido y por qué NO `on: build.yml success`**: `workflow_dispatch` cubre el caso
"acabo de buildear el stack y quiero publicar" (con `update-stack=true`) y el caso "refrescar
el cierre" (sin flags). El `schedule` semanal mantiene el cierre al día (termux-pacman cambia
a diario). Un `workflow_run`/`on: success` de build.yml auto-publicaría cada experimento de
una CI de prueba (matrix con `fail-fast: false`) sobre el repo de producción: sin inspección
humana y sin control de regresiones → descartado. El `concurrency` (`rpm-repo-publish`,
`cancel-in-progress: false`) serializa runs manuales contra el schedule y evita que dos
publicaciones se pisen entre sí.

**Alternativa más simple (opción A, si el orquestador prefiere menos flags)**: quitar el
branching de `update-stack` y SIEMPRE tomar el stack de los artifacts de build.yml (como
hoy deploy.yml: `gh run download` + conversión). Es el camino más corto, con los mismos
resultados de coherencia, pero reintroduce la dependencia de que exista un run reciente de
build.yml (expiración de artifacts a los 90 días) y pierde la garantía "nunca publico un
stack no verificado". Este diseño recomienda el modo default gh-pages + `update-stack`.

---

## 6. Firma y gpgcheck (bloque completo)

Se reutiliza el patrón probado de `deploy.yml` (y el de `sign_rpms()` del generador):

1. **Importar la clave privada**: `echo "$RPM_SIGNING_KEY" | gpg --batch --import` (aborta si el
   secret falta). El fingerprint fijo `E4AC7735BD60196E19123DB6247EEE5F6AA25EC9` (m5) es la
   clave `dnf-for-termux` → **la misma** con la que el bootstrap firma/verifica.
2. **Macros de firma** en `~/.rpmmacros` (nunca `--define` en CLI — expansión diferida;
   `gpg` con ruta ABSOLUTA porque `rpm --addsign` no hereda el PATH; `--batch --no-tty
   --no-verbose --no-armor` para CI sin TTY y clave sin passphrase):

   ```
   %_gpg_name dnf-for-termux
   %__gpg_sign_cmd /usr/bin/gpg --batch --no-tty --no-verbose --no-armor \
       --output %{__signature_filename} --detach-sign --local-user %{_gpg_name} \
       %{__plaintext_filename}
   ```

3. **Clave pública en la rpmdb LOCAL** (`$HOME/rpmdb`) ANTES de `rpm -K` (rpm valida contra su
   keyring, no contra `~/.gnupg`): `gpg --export --armor <fingerprint> | rpm --import`.
4. **Firmar TODO**: `rpm --addsign /tmp/rpm-repo/*.rpm` (una sola pasada sobre stack +
   convertidos; idempotente para los convertidos que ya firmó el generador en modo repo).
5. **Verificar (assert)**: `rpm -K --define "_dbpath $HOME/rpmdb" *.rpm | grep -c 'signatures OK'`
   == total.
6. **Repodata y firma del repo**: `createrepo_c /tmp/rpm-repo`; `gpg --batch --detach-sign
   --armor repodata/repomd.xml` → `repomd.xml.asc`; `gpg --export --armor <fingerprint> >
   termux-rpm.gpg`.
7. **Cliente**: `termux.repo` ya exige `gpgcheck=1`, `repo_gpgcheck=1` y la gpgkey
   `termux-rpm.gpg` de gh-pages. Con la misma clave y el `repomd.xml.asc` publicado, **no hay
   ningún cambio de configuración** en el dispositivo ni en el bootstrap.

---

## 7. Decisiones clave (tabla)

| Decisión | Elegida | Alternativas | Razón |
|----------|---------|--------------|-------|
| Quién publica `rpm/` | **Solo `repo-full.yml`**; `deploy.yml` se deshabilita (`on: []`) y se borra tras validar | Mantener ambos | Dos writers → repodata incoherente y pugna de versiones (la única robusta es un solo writer) |
| Fuente de los convertidos | **Re-convertir en el workflow** vía `--mode repo` | Artifact de bootstrap.yml | Reuso del cierre probado (C1-C6/M1-M9), sin acoplar repo↔bootstrap, sin límites de artifact |
| Refactor compartido | **Flag `--mode repo` en el generador** | Script nuevo `resolve-and-convert.sh` | Diff mínimo, sin riesgo de drift entre dos implementaciones del cierre |
| Fuente del stack | **gh-pages (canónico)** + `update-stack` opt-in desde build.yml | Siempre artifacts | Sin regresiones (nunca publica un stack no verificado) y coherencia con el PASO 5 del bootstrap |
| Publicación | **Staging `{index.html, rpm/}` + clean publish** (sin `keep_files`) | `keep_files: true` + `destination_dir: rpm` | `keep_files` deja .rpm obsoletos cuando cambia una versión (p. ej. `zlib-1.3.1` junto a `zlib-1.3.2`) y el repo crece sin control; staging da gh-pages regenerable y limpio |
| Triggers | `workflow_dispatch` + `schedule` semanal (00:30 UTC dom) | `on: success de build.yml` | No acoplar CI de prueba a producción; refresh deliberado |
| dn5-hello en el repo | Default: fuera (solo 8 de `PROJECT_STACK`); `update-stack`: incluido (9) | Añadirlo a `PROJECT_STACK` | No lo instala el bootstrap; mantener PROJECT_STACK intacto (afectaría al bootstrap) |

---

## 8. Riesgos y mitigaciones

| Riesgo | Impacto si falla | Mitigación / plan B |
|--------|------------------|---------------------|
| Colisión con deploy.yml | Doble escritura en `rpm/` → repodata incoherente | `deploy.yml` deshabilitado (`on: []`); `concurrency: rpm-repo-publish` serializa runs de repo-full |
| Borrado de `index.html` | Landing page desaparece | Staging incluye `cp index.html`; publish limpio; peaceiris añade `.nojekyll`. Verificación CA-4 |
| .rpm obsoletos en gh-pages (cambio de versión) | Repo crece; `dnf5` podría ver NEVRA viejas | Clean publish reemplaza TODO el árbol cada run (nada de keep_files) |
| Expiración de artifacts de build.yml (90 días) | `gh run download` falla en `update-stack` | El modo default NO toca artifacts (stack desde gh-pages); `update-stack` es manual y tras un build reciente |
| Un convertido falla (rpmbuild) | Job falla | El generador hace assert (`nrpm == npkg`, firmas OK == total) y el workflow hace assert (`rpm -K` == total, conteo == stack+manifest). Nada se publica (publish es el último paso) → el gh-pages anterior queda intacto |
| Tiempo de build (re-conversión ~93) | Job largo | El job build de bootstrap ya convierte los 93; porción repo = pasos 1-4 (< 30-60 min en arm64). No hay artifact grande que subir |
| Tamaño del repo gh-pages | Crecimiento ilimitado | ~100 .rpm (~50-80 MB): muy por debajo del límite de 1 GiB del repo; clean publish elimina versiones viejas |
| Paquete eliminado de main.json (cierre menor) | Un paquete del bootstrap viejo ya no está en el repo | Cadencia semanal acota la ventana; `dnf5` solo lo notaría al buscar actualización de un paquete ya instalado (skip_if_unavailable=True). Aceptable |
| Cache CDN de GitHub Pages | Cliente ve repodata viejo | `createrepo_c` regenera `revision` (timestamp) en cada run → dnf5 detecta metadatos nuevos; propagación estándar de Pages |
| `dnf-hello` presente/ausente según modo | Delta menor | Documentado (sección 4); filtrar una línea si se quiere uniformidad |
| Runner `ubuntu-24.04-arm` | No disponible → job falla | Ya lo usan deploy.yml y bootstrap.yml (GA); es requisito para las macros rpm aarch64 |

---

## 9. Criterios de aceptación verificables

1. **Repo completo publicado**: tras un run de `repo-full` (default), el directorio
   `rpm/` de gh-pages contiene `N` .rpm con `N = stack(9, incl. dnf-hello) + líneas
   (pkg-table.txt)` — fuente de verdad **dinámica** (m9), no un número fijo — y `N ≥ 100`
   (los ~93 del cierre + 9 del stack). Verificar con la salida del step "Verificar firmas"
   y con `gh api repos/:owner/:repo/contents/rpm?ref=gh-pages`.
2. **Firmas al 100 %**: `rpm -K --define "_dbpath $HOME/rpmdb" *.rpm` da
   `N × "signatures OK"` (con `termux-rpm.gpg` importada). Assert en CI (m5) + on-device.
3. **Repodata firmado**: existen `rpm/repodata/repomd.xml` y `repomd.xml.asc`;
   `gpg --verify repomd.xml.asc repomd.xml` OK con la clave pública — verificado EN CI
   antes del publish (m12) y on-device.
4. **index.html intacto**: `https://leonisaurov.github.io/dnf-for-termux/` sigue sirviendo
   la landing (y `rpm/index.html` NO existe en gh-pages). Al primer run, gh-pages == main
   (index.html viene del checkout; verificar identidad, m4).
5. **Sin .rpm obsoletos**: los **nombres de archivo .rpm** en `rpm/` coinciden exactamente
   con los del último run (ninguna NEVRA anterior; clean publish reemplaza el árbol
   completo). (m10)
6. **Coherencia con el bootstrap** (verificación ON-DEVICE tras el run; **REPORTABLE, no
   criterio duro** — M2): `rpm -qa` (nombres) **menos `gpg-pubkey-*`** (M1) ⊆
   `dnf5 repoquery --available` (nombres). Cuando el cierre se resuelve sobre el
   `main.json` del run (no del bootstrap), el delta se reporta como **warning** (p. ej.
   NEVRA más nuevas → "actualizable" o paquetes retirados de main.json) en vez de fallar;
   `dnf5 check-update` no reporta errores de firma/repodata.
7. **dnf5 opera como gestor** (M3): `dnf5 install <un paquete convertido ya instalado>` →
   "already installed" **O** "actualizable" (si termux-pacman subió NEVRA entre runs),
   sin errores de firma/repodata; `dnf5 repoquery --available | wc -l ≈ N`;
   `dnf5 makecache` sin errores de GPG.
8. **Sin doble escritura**: `deploy.yml` está **deshabilitado** (`on: []`) en `main` y
   `repo-full.yml` es el único writer de `gh-pages/rpm/`; un run manual de repo-full
   mientras corre el schedule no se pisa (concurrency group `rpm-repo-publish`).
9. **Modo repo del generador**: `./scripts/generate-bootstrap-dnf5.sh --mode repo --out DIR`
   produce `DIR/*.rpm` firmados + `DIR/manifest.txt` + `DIR/pkg-table.txt` y **no** genera
   zip ni toca rpmdb; con `--no-project` no descarga el stack de gh-pages. El flujo
   bootstrap (14 pasos) sigue pasando sus verificaciones (regresión = 0).

---

## 10. Cambios necesarios en el repo (para el orquestador/builder)

1. **`scripts/generate-bootstrap-dnf5.sh`**: añadir `--mode repo|bootstrap` (default
   bootstrap), `--no-project`, y el bloque de salida temprana en `main()` (sección 3).
   No tocar el flujo bootstrap.
2. **`.github/workflows/repo-full.yml`**: nuevo (sección 5).
3. **`.github/workflows/deploy.yml`**: **deshabilitado** (`on: []` + comentario), NO
   eliminado (C1): sustituido por repo-full como único writer; borrar tras validar el
   primer run de producción. No dejarlo con el publish activo — sería un segundo writer.
4. **Sin cambios** en `build.yml`, `bootstrap.yml`, `config/` (termux.repo ya apunta a
   gh-pages con gpgcheck=1 + repo_gpgcheck=1 + termux-rpm.gpg), ni en el bootstrap.
5. **Seguimiento (fuera del alcance de este diseño)**: el fix del overflow de `index.html`
   ya está aplicado en main (no tocado por el builder). La mención a `deploy.yml` como el
   que "Signs and publishes the RPM repository" en el landing y en `docs/CI-PIPELINE.md`
   (ya marcado desactualizado) se actualizará al cerrar esta implementación; no bloqueante.

---

## 11. Notas para el Orquestador

- **No se usa `mkrepo.sh`**: `createrepo_c` está disponible en el runner (deploy.yml ya lo
  usa); `mkrepo.sh` queda para repos locales on-device en Termux (no firma repomd).
- **El conteo del cierre es dinámico**: hoy el generador reporta ~93; la tarea menciona ~95.
  El workflow no debe hardcodear el número: usa `manifest.txt` + stack en el assert.
- **Coherencia instalado↔repo**: es por NEVRA, no por sha (rpmbuild embebe BUILDTIME). No
  exigir byte-identidad.
- **Primer run**: el clean publish reemplazará el `rpm/` actual (9 .rpm) por el completo
  (~100). Es el cambio deseado; gh-pages queda regenerable desde `main` (index.html + run).
- **Decisión abierta menor**: si se quiere `dnf-hello` SIEMPRE en el repo, filtrar el merge
  de `update-stack` o ampliar `PROJECT_STACK` (este último afecta al bootstrap — revisar).
- **Estimación de coste CI**: run semanal ~30-60 min en `ubuntu-24.04-arm` + runs manuales
  cortos; dentro del plan free de Actions (2000 min/mes) para este ritmo.

---

## Estado

- [x] Concepto definido (estrategia, fuentes, interfaz del generador, YAML, decisiones)
- [x] Criterios de aceptación verificables
- [x] Aprobado e IMPLEMENTADO (2026-08-09) con las correcciones C1/M1–M6/m1–m12
      (ver "## Estado de implementación" al inicio)
- [ ] Pendiente: primer run de CI (dry-run → producción), verificación on-device y
      borrado de `deploy.yml`

