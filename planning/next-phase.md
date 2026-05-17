# Próxima fase — planificación

Tres mejoras priorizadas tras cerrar el MVP de bootstrap. Ninguna bloquea el uso
diario; son optimizaciones y cierre del ciclo "config viva".

## 1. GitHub Releases con binarios pre-built

### Motivación
Hoy el `install.sh` instala Zig (~120 MB de toolchain) y compila desperta en el
host destino. Con releases publicados, el script puede bajar un binario
estático y saltarse el compile. Ventajas:
- ~30 s ahorrados en cada instalación.
- ~120 MB menos de paquetes (zig + clang + lld + compiler-rt + llvm-libs).
- No requiere `base-devel` para usuarios que solo quieren correr desperta.

### Targets
- `desperta-linux-x86_64` (musl, estático)
- `desperta-linux-aarch64` (musl, estático)
- Opcional: `desperta-macos-arm64`, `desperta-macos-x86_64` (no críticos — el
  flujo de bootstrap es Linux/CachyOS).

### Implementación

1. **Workflow GitHub Actions** `.github/workflows/release.yml`:
   - Trigger: `push` de tag `v*` (ej. `v0.1.0`).
   - Pasos:
     - `actions/checkout@v4`
     - Setup Zig 0.16 (descarga del binario oficial; no acción third-party para
       evitar supply-chain risk).
     - Matrix: `[x86_64-linux-musl, aarch64-linux-musl]`.
     - `zig build -Dtarget=$TARGET -Doptimize=ReleaseSafe`.
     - `gh release create $TAG zig-out/bin/desperta-$TARGET` (uno por target).
2. **`install.sh` actualizado**:
   ```sh
   ARCH=$(uname -m)   # x86_64 | aarch64
   URL="https://github.com/jllopis/despertaferro/releases/latest/download/desperta-linux-${ARCH}"
   if curl -fsSL "$URL" -o "$BIN"; then
     chmod +x "$BIN"
     log "downloaded pre-built binary"
   else
     log "release binary not available — falling back to source build"
     # ... existing zig build path
   fi
   ```
3. **Verificación opcional**: shasum del binario publicado en el workflow,
   verificado por install.sh. Bajo prioridad inicialmente.

### Riesgos / decisiones
- **Versionado**: convención SemVer. Primer tag `v0.1.0` cuando estabilicemos
  flags del CLI; tags `v0.0.x` mientras tanto.
- **Compatibilidad libc**: musl estático → corre en cualquier Linux. No
  necesitamos releases glibc.
- **Sin firma GPG** inicialmente; HTTPS al CDN de GitHub es suficiente para el
  threat model personal.

### Estado
- [ ] Decidir primer tag y crearlo manualmente.
- [ ] Escribir `.github/workflows/release.yml`.
- [ ] Probar generación con un tag de prueba (`v0.0.1-test`).
- [ ] Actualizar `install.sh` con preferencia por release binary.
- [ ] Actualizar README con instrucción de release manual.

---

## 2. `loginctl enable-linger` en bootstrap

### Motivación
Servicios `systemctl --user enable X` solo arrancan al hacer login interactivo,
salvo que el usuario tenga *linger* habilitado. Sin linger, los servicios
`--user` (ej. `syncthing`) quedan habilitados pero no se inician hasta el
próximo login real. En primera instalación esto sorprende.

### Comportamiento propuesto
Phase 5.5 (entre `deploy dotfiles` y `post-install`):
1. Detectar si algún paquete del perfil activo tiene `service_user` definido.
2. Si sí, ejecutar `sudo loginctl enable-linger $USERNAME` si el linger no está
   ya habilitado (`loginctl show-user $USERNAME` muestra `Linger=yes`).
3. Imprimir `[linger] enabled for $USERNAME` o `[linger] already enabled — skip`.

### Implementación
- Helper en `services.zig`:
  ```zig
  pub fn enableLinger(io, allocator, out, username, dry_run) !bool
  pub fn isLingerEnabled(io, allocator, username) !bool
  ```
- Llamado desde `commandBootstrap` antes del loop de Phase 6 si
  `any_user_service == true`.

### Estado
- [ ] Añadir `enableLinger` / `isLingerEnabled` en `services.zig`.
- [ ] Detectar `any_user_service` en bootstrap antes de Phase 6.
- [ ] Imprimir status en Phase 8 summary.

---

## 3. `desperta sync` (cerrar el ciclo)

### Motivación
Después de `bootstrap` o de modificar dotfiles a mano y registrarlos con
`desperta track`, los cambios están en el git index del bare repo (`status`
los reporta como `clean`), pero **nunca se commitean ni se pushean** a ningún
remote. Hoy el bare repo es local-only.

El usuario debería poder cerrar el ciclo con un comando:

```
desperta sync                  # re-stage → commit → push
desperta sync --commit-only    # sin push (commit local)
desperta sync --message "..."  # mensaje custom
```

### Modelo de repos — clarificación importante

Conviven dos repos completamente independientes:

| Repo | Path | Qué guarda | Quién lo configura |
|---|---|---|---|
| **Project repo** (este código) | `~/.local/share/despertaferro/` ↔ `github.com/jllopis/despertaferro` | Código de desperta, plantillas en `dotfiles/default/`, catálogo en `config/packages.toml` | El proyecto. La URL **no se configura** en el manifest: el binario sabe de dónde lo clonaron. |
| **Dotfiles repo del usuario** | `~/.local/state/despertaferro/repo.git` (bare) | Los dotfiles **reales** del usuario en cada host, una rama por hostname | El usuario, vía `[git] remote` en `desperta.toml`. **Privado por defecto** porque los dotfiles pueden tener datos personales. |

Por eso `desperta.toml` solo expone **un** remote (`[git] remote`), no dos.
La URL del proyecto es implícita.

### Modelo de ramas

Una rama por máquina, derivada del hostname:

```
hosts/<hostname>          # bare repo: tracking dotfiles de un host concreto
```

**Importante**: no hay `host_branch_prefix` configurable y los `[[hosts]]` del
manifest **no declaran `branch`**. El código siempre usa `hosts/<name>`.
Antes existían esos campos (`host_branch_prefix`, `base_branch`,
`default_branch`, `[[hosts]] branch`) — eliminados porque eran código muerto y
podían generar paths como `hosts/hosts/<name>` si alguien los combinaba.

### Semántica
1. Resolver `remote` del manifest. Si no hay → solo commit local + warn.
2. Abrir el bare repo y leer el index actual (re-staging ya lo hace `bootstrap`
   phase 7; aquí solo si hay cambios respecto al index actual).
3. Si no hay cambios respecto al último commit → "nothing to sync".
4. `git commit` con autor/email del `~/.gitconfig` (o env `GIT_AUTHOR_*`).
   - Mensaje default: `"sync: <hostname> @ <ISO timestamp>"`.
   - Custom: `--message "..."`.
5. Si `remote` configurado y no es `--commit-only`:
   - Configurar `origin` en el bare repo si no existe.
   - `git push origin hosts/<hostname>`.
6. Imprimir: commit SHA + push status.

### Implementación
- Extender el `commandSync` actual (es un stub mínimo hoy).
- Reusar `git_backend.createCommit` (ya implementado y probado en tests).
- Push: invocar `git` binario como subprocess inicialmente (más simple que
  reimplementar el wire protocol nativamente). Documentar que requiere SSH key.
- Reusar `[git] use_git_binary` para forzar fallback al `git` del sistema en
  todas las operaciones si el usuario lo prefiere.

### Riesgos
- **Auth SSH con passphrase**: si la key requiere passphrase, el push se
  bloquea pidiéndola. Aceptable inicialmente; documentar.
- **Repo público accidental**: el bare repo aún no enlaza con ningún remote en
  `init`. Asegurarse de que `sync` muestre la URL antes del primer push y
  pida confirmación si parece pública (heurística: contiene `github.com` y no
  está marcado como privado en el manifest).
- **Conflictos entre máquinas**: dos máquinas con el mismo hostname pushearían
  a la misma rama. `--adopt <host>` ya cubre el caso intencional; el accidental
  (dos máquinas con el mismo `$HOSTNAME`) es responsabilidad del usuario.

### Estado
- [ ] Decidir si `desperta init` ya configura `origin` o si lo hace `sync` al
      primer push.
- [ ] Aviso explícito antes del primer push (URL del remote, modo público vs
      privado heurístico).
- [ ] Implementar commit step usando `git_backend.createCommit`.
- [ ] Implementar push step (subprocess `git push`).
- [ ] Flags `--commit-only`, `--message`.
- [ ] Test con remote local (`file://`) en suite.
- [x] Limpiar campos obsoletos del manifest (`host_branch_prefix`,
      `base_branch`, `default_branch`, `[[hosts]] branch`).

---

## 4. Comandos location-independent

### Motivación
Hoy varios comandos leen archivos del proyecto resolviéndolos relativos a
`cwd`:

| Path | Quién lo lee |
|---|---|
| `config/packages.toml` | `list`, `install`, `bootstrap`, `service install` |
| `config/denylist.txt` | `track`, `ignore`, staging en phase 7 |
| `config/tracked-paths.txt` | `track`, `status`, `snapshot`, `sync` |
| `desperta.toml` | `doctor`, `bootstrap`, `status` |
| `dotfiles/default/` | `bootstrap` phase 5 |

Si el usuario ejecuta `desperta list` desde `~` o `/tmp`, falla. Hoy se exige
`cd ~/.local/share/despertaferro` o `DESPERTA_REPO` (que solo unos pocos
caminos respetan). Inconsistente y propenso a errores.

### Modelo propuesto
Resolver el "project dir" una sola vez al arranque, con orden de precedencia
explícito:

1. Flag CLI `--repo <path>` (nuevo, global).
2. Env `DESPERTA_REPO`.
3. Campo `project_dir` en el runtime config (`~/.config/despertaferro/config.toml`).
4. Fallback dev: subir directorios desde `cwd` buscando un `desperta.toml`.
5. Si ninguno: error claro con instrucciones (`export DESPERTA_REPO=... o cd al repo o pasar --repo`).

Una vez resuelto, **todas** las lecturas de catálogo / manifest / templates /
denylist / tracked-paths se hacen relativas a `project_dir`. `cwd` deja de
importar.

### Implementación

- Extender `config.Config` con `project_dir: ?[]const u8`.
- `install.sh` (y `desperta init`) escriben `project_dir = "..."` en el
  runtime config tras clonar el repo, así que tras la primera instalación el
  binario sabe dónde está sin más configuración.
- Añadir helper `resolveProjectDir(allocator, environ_map, cfg, flag) ![]const u8`
  paralelo al ya existente `resolveRepoPath` (este último es para el **bare
  repo de dotfiles**, conceptos distintos — documentar bien).
- Añadir `flags.repo: ?[]const u8` en `Flags.parse`.
- Reemplazar todas las cadenas literales `"config/packages.toml"`,
  `"config/denylist.txt"`, etc., por `std.fmt.allocPrint("{s}/config/packages.toml", .{project_dir})`.
- Centralizar las constantes en un helper (`paths.zig`?) para no esparcir el
  cambio.
- Mostrar `project_dir` resuelto en `desperta status` y `desperta doctor`,
  útil para diagnosticar dónde está mirando.

### Compatibilidad
- Quien lance `desperta list` desde el repo seguirá funcionando: el fallback
  #4 (subir buscando `desperta.toml`) lo cubre sin tocar config.
- Quien haga `cd` al repo y exporte `DESPERTA_REPO` también seguirá: #2 gana
  sobre #3.
- Cambio rompedor para usuarios que dependan del comportamiento `cwd`-relativo
  sin tener `DESPERTA_REPO` ni runtime config — aceptable, esto es un fix.

### Estado
- [ ] Añadir `project_dir` a `config.Config` (`config.zig`).
- [ ] `install.sh` escribe `project_dir` al runtime config tras clonar.
- [ ] `desperta init` también lo escribe si no existe.
- [ ] Añadir `--repo <path>` global en `Flags.parse`.
- [ ] Helper `resolveProjectDir` con la cascada de 5 niveles.
- [ ] Centralizar las 5 rutas hardcodeadas en `paths.zig` (o constantes).
- [ ] Mostrar `project_dir` en `status` y `doctor`.
- [ ] Tests: ejecución desde `cwd` distinto, con env, con flag, con runtime
      config.

### Bonus
Una vez todos los comandos toman `project_dir` consistentemente, **el usuario
puede mover el repo a donde quiera** (`~/dev/despertaferro`, `/opt/despertaferro`,
lo que sea) y desperta lo encuentra. Es flexibilidad real.

---

## 5. Package management v2 — SQLite como inventario local

### Motivación
Hoy `config/packages.toml` describe **todo lo que podría instalar**, y el
binario lo lee en cada `list`/`install`/`bootstrap`. Eso confunde dos cosas:

- **Catálogo** (recetario): "esto es lo que sé instalar, con sus configs".
  Versioned, compartido, vive en el repo del proyecto.
- **Inventario** (qué tiene tu máquina): "esto es lo que **tú** has decidido
  gestionar". Local, mutable, vive en tu home.

Mezclarlos provoca varios problemas:
- Tras bootstrap, el catálogo deja de reflejar tu realidad (pueden faltar cosas
  que instalaste a mano, sobrar cosas de perfiles que no usaste).
- "Gestionar configs" significa cosas distintas para cada paquete: si
  desperta no gestiona su config, no debería aparecer en `list`.
- No hay forma de añadir un paquete ad-hoc (algo que no esté en el TOML) y
  trackear su config sin editar el catálogo.

### Modelo
- **`config/packages.toml`** queda como **recetario**: lookup table consultada
  solo durante bootstrap inicial o cuando haces `package add <name>`.
- **`$XDG_STATE_HOME/despertaferro/managed.db`** (SQLite) = inventario real
  con los paquetes cuya configuración estás gestionando con desperta.
- **`desperta package`** es la API normal post-bootstrap:
  ```
  desperta package add <name>                            # del catálogo
  desperta package add <name> --config <path>...         # ad-hoc, sin catálogo
  desperta package remove <name>                         # desinstala + olvida
  desperta package list                                  # contenido de la DB
  ```

### Schema (borrador)

```sql
CREATE TABLE managed_packages (
    id            INTEGER PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    source        TEXT NOT NULL,           -- 'bootstrap' | 'manual' | 'catalog'
    installed_at  INTEGER NOT NULL,        -- unix epoch
    pacman_name   TEXT,                    -- nombre real instalado (puede diferir del id)
    catalog_id    TEXT                     -- id en packages.toml si proviene de allí
);

CREATE TABLE managed_paths (
    id         INTEGER PRIMARY KEY,
    package_id INTEGER NOT NULL REFERENCES managed_packages(id) ON DELETE CASCADE,
    path       TEXT NOT NULL,              -- absoluto o ~/...
    UNIQUE (package_id, path)
);

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
-- meta: schema_version, last_bootstrap_at, etc.
```

### SQLite backend
**Decisión**: vendor `sqlite3.c` directamente en el repo. Razones:
- Cero dependencias externas en runtime (binario sigue siendo standalone).
- Solo crece ~700 KB el binario estático.
- Es 1 archivo en `vendor/sqlite/sqlite3.{c,h}` — autocontenido.

Pasos:
- Crear `vendor/sqlite/` con la versión `amalgamation` oficial (la fuente
  fusionada en un solo `.c`).
- `build.zig`: compilar `sqlite3.c` como objeto, linkarlo al ejecutable.
- Definir flags estándar de compilación segura: `-DSQLITE_THREADSAFE=0`
  (single-thread), `-DSQLITE_OMIT_LOAD_EXTENSION`, `-DSQLITE_DQS=0`.
- Crear `src/db.zig` que envuelve la API C de SQLite con un layer Zig minimo:
  open, exec, prepare, bind, step, finalize.

### Bootstrap → DB

La opción elegida es **bootstrap = N llamadas a `package add` (mismo path de
código)**, con la matiz de que en bootstrap source='bootstrap' y en uso normal
source='manual'. Al final, `package list` muestra todo desde el día uno.

Pseudocódigo:
```zig
for (catalog.packagesInProfile(profile)) |pkg| {
    package.add(allocator, db, pkg.name, .source_bootstrap);
}
```

`package.add` internamente:
1. Si el paquete ya está en la DB → no-op (idempotencia).
2. Si no está instalado → invocar pacman/yay/brew (lógica actual de `pkgmgr`).
3. Resolver config_paths (catálogo o `--config`).
4. Por cada path: añadir a `tracked-paths.txt`, stagear al index, insertar
   en `managed_paths`.
5. INSERT en `managed_packages` con source apropiado.

### Paquetes ad-hoc (fuera del catálogo)

```sh
desperta package add htop --config ~/.config/htop/htoprc
desperta package add htop --config ~/.config/htop/  # directorio entero
```

Sin lookup en el catálogo. El DB guarda `name="htop"`, `source="manual"`,
`catalog_id=NULL`. Los config paths son los que el usuario indique. Para que
funcione el install necesitamos saber **el nombre del paquete en el package
manager** — si difiere de `<name>` se permitirá:
```sh
desperta package add htop --pacman htop --config ~/.config/htop/
```

### Migración del estado actual

Usuarios que ya hayan corrido bootstrap antes de esta fase necesitan poblar la
DB inicial. Solución: `desperta package backfill` (o como subcomando de
`migrate`) que:
1. Lee el perfil activo del manifest local.
2. Comprueba con `pkgmgr.isInstalled` cuáles están realmente instalados.
3. Por cada uno → `INSERT` con source='backfill'.

### Implicaciones sobre `list` actual

El subcomando `desperta list` actual (que itera el catálogo) cambia de
semántica:
- `desperta list` → muestra la DB (lo que está gestionado).
- `desperta list --catalog` → muestra el catálogo entero (lo viejo, opt-in).
- `desperta list --profile <name>` → catálogo filtrado por perfil (lookup
  helper antes de hacer `package add`).

### Estado
- [ ] Vendor SQLite amalgamation en `vendor/sqlite/`.
- [ ] `build.zig` compila + linka sqlite3.c.
- [ ] `src/db.zig` con wrapper Zig idiomático.
- [ ] Schema + migraciones (tabla `meta` con `schema_version`).
- [ ] `commandPackage` subcomandos: `add`, `remove`, `list`, `backfill`.
- [ ] Refactor `commandBootstrap` phase 4+5+6+7 para llamar a `package.add`.
- [ ] Tests: en memoria (`:memory:` DB), con instalaciones simuladas.

---

## 6. Host config = local, no en el manifest compartido

### Motivación
Hoy `desperta.toml` tiene bloques `[[hosts]]` con la lista de máquinas
conocidas y sus perfiles. Eso es leakage: cada máquina debería ser soberana
de su identidad. Nadie más necesita saber qué máquinas tienes ni qué
perfiles corren.

Limpiamos al hacer el repo público (los `[[hosts]]` quedaron como un
"defaults para los hosts conocidos del autor") pero el modelo correcto es
que **cada máquina se autodeclara**.

### Modelo
- `desperta.toml` del repo deja de tener `[[hosts]]`. Solo queda `[runtime]`,
  `[git]` (vacío por defecto, el usuario rellena con su remote privado), y
  `[policy]`.
- El runtime config local (`~/.config/despertaferro/config.toml`) gana una
  sección `[host]` con la identidad de **esta** máquina:
  ```toml
  [host]
  name = "my-laptop"        # default: hostname
  platform = "linux"        # default: detectado
  profiles = ["base", "hyprland"]
  ```
- **`desperta init`** o **`desperta bootstrap`** la escribe la primera vez
  (preguntando perfiles si no se pasa `--profile`).

### Cross-host: `--from` y `--adopt`

Sin lista global, ¿cómo se copia o adopta otro host?

- Cada host pushea su rama `hosts/<name>` al **remote privado del usuario**
  (definido en `[git] remote`).
- `desperta bootstrap --from old-laptop` clona el remote y usa su rama
  `hosts/old-laptop` como fuente de templates / config_paths.
- `desperta bootstrap --adopt old-laptop` mismo, pero registra esta máquina
  como `old-laptop` (sobreescribe `[host].name` localmente). Responsabilidad
  del usuario que las dos máquinas no convivan.

Esto elimina la necesidad de declarar hosts en sitios compartidos. La verdad
está en las ramas del bare repo del usuario.

### Estado
- [ ] Eliminar `[[hosts]]` de `desperta.toml` (el del repo).
- [ ] Añadir `[host]` a `config.Config` (en `config.zig`).
- [ ] `commandInit` / `commandBootstrap` escriben `[host]` al primer arranque.
- [ ] `commandStatus` muestra el `[host]` activo.
- [ ] `--from` / `--adopt` resuelven contra el remote git, no contra
      `m.findHost(name)`.

---

## Orden recomendado

1. **Releases (#1)** — quita la dependencia de Zig en máquinas cliente,
   beneficio inmediato.
2. **Comandos location-independent (#4)** — base limpia para todo lo demás;
   evita que el resto herede el problema cwd-relativo.
3. **Package management v2 (#5)** — el cambio arquitectónico más grande; toca
   bootstrap, list, install. Definir la DB antes de implementar sync simplifica
   las cosas (sync puede usar el inventario para decidir qué stagear).
4. **Host config local (#6)** — pequeño cambio adyacente a #5, hacerlos juntos.
5. **`desperta sync` (#3)** — cierra el ciclo bootstrap → track → sync.
6. **Linger (#2)** — quality-of-life independiente, en cualquier momento.

## No-goals para esta fase

- Hot-reload de configs (sería el "service daemon" — fase 06 del plan original).
- Auto-detección de cambios en archivos trackeados con watcher (mismo).
- UI gráfica / TUI. La CLI es suficiente.
- Encriptación de archivos sensibles en el bare repo. Estrategia actual es la
  denylist; secretos van por otros canales (1Password, etc.).
