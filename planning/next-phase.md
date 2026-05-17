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

## Orden recomendado

1. **Releases primero** — quita la dependencia de Zig en máquinas cliente,
   beneficio inmediato para cualquier nueva instalación.
2. **Comandos location-independent (#4)** — base limpia para todo lo demás;
   evita que `sync` y otros futuros comandos hereden el problema.
3. **`desperta sync` (#3)** — cierra el ciclo principal (bootstrap → track →
   sync → re-instalar en otra máquina). Sin esto, el bare repo es "write-only"
   en máquinas reales.
4. **Linger (#2)** — quality-of-life, no bloqueante. Se puede hacer en
   cualquier momento.

## No-goals para esta fase

- Hot-reload de configs (sería el "service daemon" — fase 06 del plan original).
- Auto-detección de cambios en archivos trackeados con watcher (mismo).
- UI gráfica / TUI. La CLI es suficiente.
- Encriptación de archivos sensibles en el bare repo. Estrategia actual es la
  denylist; secretos van por otros canales (1Password, etc.).
