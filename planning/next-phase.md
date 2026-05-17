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
los reporta como `clean`), pero **nunca se commitean ni se pushean** al remote.
El usuario debería poder cerrar el ciclo con un comando:

```
desperta sync                  # snapshot → commit → push
desperta sync --commit-only    # sin push
desperta sync --message "..."  # mensaje custom
```

### Semántica
1. Re-stagear todo lo de `tracked-paths.txt` (recoge modificaciones desde
   último snapshot).
2. Si no hay cambios respecto al último commit → "nothing to sync".
3. `git commit` en el bare repo con autor/email del `~/.gitconfig` o env
   `GIT_AUTHOR_*`. Mensaje:
   - Default: `"sync: <hostname> @ <ISO timestamp>"` (no se inventa, es info verificable).
   - Custom: `--message "..."`.
4. `git push origin hosts/<hostname>` al remote del `desperta.toml` si está
   definido.
5. Imprimir resultado: commit SHA + push status.

### Implementación
- `commandSync` existe ya como stub — extenderlo, no recrear.
- Reusar `git_backend.createCommit` (ya implementado y probado en tests).
- Push: por ahora invocar `git push` como subprocess (más simple que SMTP-style
  git wire protocol nativo). Documentar que requiere SSH key configurada.

### Riesgos
- **Auth**: si el remote es SSH y la key requiere passphrase, el push pedirá
  passphrase. Aceptable inicialmente; documentar.
- **Conflictos**: dos máquinas pusheando a la misma rama `hosts/<X>` no
  conflictan si son hostnames distintos. Si el usuario adopt`a un host con
  `--adopt`, debería cerrarse el otro antes (no es algo a forzar en código).

### Estado
- [ ] Verificar qué hace hoy `commandSync` (probablemente solo lee
  tracked-paths.txt y stagea — duplicado con Phase 7 ya).
- [ ] Implementar commit step usando `git_backend.createCommit`.
- [ ] Implementar push step (subprocess `git push`).
- [ ] Flags `--commit-only`, `--message`.
- [ ] Test con remote local (`file://`) en suite.

---

## Orden recomendado

1. **Releases primero** — quita la dependencia de Zig en máquinas cliente,
   beneficio inmediato para cualquier nueva instalación.
2. **`desperta sync`** — cierra el ciclo principal (bootstrap → track → sync →
   re-instalar en otra máquina). Sin esto, el bare repo es "write-only" en
   máquinas reales.
3. **Linger** — quality-of-life, no bloqueante. Se puede hacer en cualquier
   momento.

## No-goals para esta fase

- Hot-reload de configs (sería el "service daemon" — fase 06 del plan original).
- Auto-detección de cambios en archivos trackeados con watcher (mismo).
- UI gráfica / TUI. La CLI es suficiente.
- Encriptación de archivos sensibles en el bare repo. Estrategia actual es la
  denylist; secretos van por otros canales (1Password, etc.).
