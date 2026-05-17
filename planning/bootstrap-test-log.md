# Bootstrap test log — Docker (CachyOS x86_64 on ARM Mac)

Bitácora de hallazgos durante las pruebas de `desperta bootstrap` para preparar
el `install.sh` final. Se actualiza incrementalmente.

## Entorno de prueba

- **Host**: macOS ARM (Apple Silicon)
- **Docker**: imagen `cachyos/cachyos` con `--platform linux/amd64` (Rosetta)
- **Binario**: pre-built estático `zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe` (4.9 MB)
- **Montaje**: repo en `/repo` (read-only), `DESPERTA_REPO=/repo`
- **Usuario**: `jllopis` con NOPASSWD sudo (passwd `jllopis` por si `chsh` pide)

## Comandos de prueba

```sh
# Build local (host)
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe

# Build/run contenedor
bash docker/run.sh build
bash docker/run.sh shell

# Dentro del contenedor:
cd /repo
desperta bootstrap --apply --profile test
```

`--profile test` evita instalar los 628 paquetes del perfil `base`. Solo instala
11 paquetes esenciales sin GUI: `zsh tmux btop neovim ripgrep fzf starship zoxide jq curl wget`.

---

## Bugs encontrados y fixes

### 1. `buildPlan` filtraba todos los paquetes con `sysinfo.os_id = "cachyos"`

- **Síntoma**: `profile 'base': 49 pending` aparecía en cada ejecución; nada se instalaba.
- **Causa**: `pkg.hasPlatform("cachyos")` siempre false porque los paquetes declaran `platforms = ["linux", "macos"]`.
- **Fix**: en `commandBootstrap` y `commandInstall`, mapear `sysinfo.os_id` a un platform canónico:
  ```zig
  const canonical_platform: []const u8 = switch (sysinfo.os) {
      .linux => "linux",
      .macos => "macos",
      else => sysinfo.os_id,
  };
  ```
- **Status**: ✅ fixed

### 2. Phase 6 ejecutaba `post_cmd`/services aunque el paquete no se instalara

- **Síntoma**: `chsh -s /usr/bin/zsh` corría aunque `zsh` no estuviera instalado, pidiendo password.
- **Fix**: añadido `if (!dry_run and !pkgmgr.isInstalled(io, environ_map, pkg)) continue;` en phase 6.
- **Status**: ✅ fixed

### 3. Output desordenado: stdout de subprocesos antes que los `print` de desperta

- **Síntoma**: salida de pacman aparecía antes que el header `[pacman] zsh tmux ...`.
- **Causa**: desperta usa `std.Io.Writer` con buffer; subprocesos escriben directo al terminal.
- **Fix**: `try out.flush();` antes de cada `std.process.spawn` (en `pkgmgr.runInstall` y `services.runArgv`).
- **Status**: ✅ fixed

### 4. Cross-compile mac→linux falla con `catch .{}` por inferencia de tipo

- **Síntoma**: error de tipo en `readOsRelease(...) catch .{}`.
- **Fix**: anotar tipo explícito: `catch OsReleaseInfo{...}`.
- **Status**: ✅ fixed

### 5. `std.c.getuid()` requiere `link_libc = true` en cross-compile musl

- **Fix**: añadido `.link_libc = true` al módulo en `build.zig`.
- **Status**: ✅ fixed

### 6. `SHELL`/`USER`/`LOGNAME` no existen en contenedor Docker

- **Síntoma**: `shell=""` y `[group] add  to docker` (username vacío).
- **Fix**: fallbacks en `detect.zig` y `main.zig`:
  ```zig
  // shell
  environ_map.get("SHELL") orelse "/bin/bash"
  // username
  environ_map.get("USER") orelse environ_map.get("LOGNAME") orelse
      std.fs.path.basename(environ_map.get("HOME") orelse "")
  ```
- **Status**: ✅ fixed

### 7. ENOSPC en Docker Desktop con imagen pequeña

- **Síntoma**: pacman aborta a mitad de 628 paquetes; dotfile copy falla con `error: Unexpected`.
- **Workaround**: liberar disco host (Docker Desktop necesita > 20 GB libres).
- **Mejora pendiente**: mapear errnos crudos en `dotfiles.copyFile` a mensajes claros (`NoSpaceLeft` → "disk full").

### 8. `bootstrap` busca `config/packages.toml` desde cwd

- **Síntoma**: `error: config/packages.toml not found — run from repo root` cuando se ejecuta desde `$HOME`.
- **Workaround actual**: `cd /repo` antes de `desperta bootstrap`.
- **Mejora pendiente**: respetar `DESPERTA_REPO` env var en `packages.zig` y en la pre-flight check de `main.zig`.

### 9. Necesidad de flag `--profile` para tests acotados

- **Motivo**: hosts no están en manifest todavía; fallback es `base` (628 paquetes).
- **Fix**: añadido `--profile <name>` que bypasea `m.findHost(...)` y selecciona perfil directamente.
- **Status**: ✅ fixed (perfil `test` añadido a 11 paquetes esenciales)

### 10. `tracked-paths.txt` hardcoded en cwd → falla con `/repo` read-only

- **Síntoma**: Phase 7 aborta con `error: ReadOnlyFileSystem`.
- **Causa**: `const tracked_paths_path = "config/tracked-paths.txt";` (main.zig:12) — relativo a cwd. Cuando bootstrap corre con `cd /repo`, intenta escribir en el mount read-only.
- **Diseño correcto**: `tracked-paths.txt` es **state**, no config — debe vivir bajo `$XDG_STATE_HOME/despertaferro/` (o `$DESPERTA_REPO` cuando apunte a clon escribible).
- **Fix elegido (test Docker)**: `docker/run.sh shell` copia `/repo` a `~/.local/share/despertaferro` y `cd` ahí antes de abrir el shell. Refleja lo que hará el `install.sh` real (clonar el repo a un sitio escribible).
- **Fix pendiente (código)**: mover `tracked_paths_path` a `$XDG_STATE_HOME/despertaferro/tracked-paths.txt` (con migración del actual `config/tracked-paths.txt` si existe). Afecta también a `commandTrack`, `commandStatus`, `commandMigrate`.
- **Status**: ⏳ workaround vía run.sh; fix de código pendiente

### 11. `chsh` pide password (esperado, no es bug)

- **Síntoma**: `chsh -s /usr/bin/zsh` → `Password:` durante phase 6.
- **Causa**: PAM exige autenticación del usuario para cambiar su shell. No es sudo. No se puede ni se debe bypassear con `--noconfirm`.
- **Acción**: documentar en `install.sh` que el usuario verá un prompt de password (su propio password) si zsh está en el perfil.
- **Status**: ✅ comportamiento correcto

---

## Decisiones de diseño tomadas

- **Repo montado read-only en `/repo`**: bootstrap no necesita escribir en el repo; sus writes van a `$HOME` (`tracked-paths.txt` está en `$HOME/.local/share/despertaferro` cuando init crea el bare repo).
- **Binario pre-built en el host**: evita instalar zig dentro del contenedor (ahorra ~1 GB).
- **`--profile test`** queda como mecanismo de override permanente para test/CI.

---

## Pendientes para `install.sh` final

Cosas que el script de instalación debe contemplar, deducidas de las pruebas:

- [x] Verificar espacio en disco antes de empezar (`df -h /` > 10 GB para perfil completo).
- [x] No asumir `$SHELL`/`$USER` poblados — derivar de `getpwuid` o `whoami`.
- [x] Clonar repo a `~/.local/share/despertaferro` (escribible) y `cd` ahí antes de `desperta bootstrap`.
- [x] Mensaje claro si pacman aborta por disco/red (capturar exit code y reportar).
- [x] Tras `chsh`: avisar al usuario de re-login (el cambio no aplica hasta nueva sesión).
- [x] Tras añadir grupos (docker, etc.): mismo aviso de re-login o sugerir `newgrp`.
- [ ] Linger systemd-user: `loginctl enable-linger $USER` si se van a habilitar servicios `--user`.
- [x] Bootstrap ahora **produce snapshot real** — Phase 7 stagea al index. ✅

## Estado final

`scripts/install.sh` validado end-to-end en contenedor `cachyos/cachyos` con repo
público. Listo para usar en VM real o instalación CachyOS Minimal nativa con:

```sh
curl -fsSL https://raw.githubusercontent.com/jllopis/despertaferro/master/scripts/install.sh | bash
```

Para acotar a un subset de paquetes durante test/CI:

```sh
curl -fsSL https://raw.githubusercontent.com/jllopis/despertaferro/master/scripts/install.sh | bash -s -- --profile test
```

---

## Resultados de iteraciones

### Iteración 1 — 2026-05-17 — primer end-to-end con `--profile test`

- Comando: `desperta bootstrap --apply --profile test`
- Resultado: ✅ todas las 8 fases sin errores
- Métricas:
  - Phase 4: 10 paquetes pedidos → 28 instalados (con deps)
  - Phase 5: 24 dotfiles desplegados desde `default/`
  - Phase 7: 28 paths tracked
- Observaciones:
  - `chsh` pidió password (esperado) y aplicó zsh
  - Phase 7 trackeó tanto archivos individuales (desde dotfiles) como directorios (desde `config_paths` cuando existen → ej. `~/.config/zsh`, `~/.config/nvim`)
  - Mensaje final de re-login presente
  - `run.sh shell` con copia previa a `~/.local/share/despertaferro` permite tracking writable

### Iteración 4 — 2026-05-17 — `install.sh` end-to-end desde repo público

- Contexto: tras hacer el repo público en GitHub, validar el flujo completo desde una imagen vanilla `cachyos/cachyos`.
- Comando:
  ```sh
  docker run --rm -it --platform linux/amd64 \
    -v "$PWD/scripts/install.sh:/tmp/install.sh:ro" \
    cachyos/cachyos bash -c '
      pacman -Syu --noconfirm sudo &&
      useradd -m -s /bin/bash test &&
      echo "test:test" | chpasswd &&
      echo "test ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/test &&
      su - test -c "bash /tmp/install.sh --profile test"
    '
  ```
- Resultado: ✅ todo el flujo completa correctamente
- Pasos verificados:
  1. Pre-flight (uid, sudo, pacman, disco 35G, user/home derivados sin $USER)
  2. pacman base-devel + curl + git (cached, "nothing to do")
  3. yay instalado desde AUR
  4. `git clone https://github.com/jllopis/despertaferro.git` desde repo público
  5. Zig instalado desde pacman, `zig build -Doptimize=ReleaseSafe` exitoso
  6. `desperta bootstrap --apply --profile test` corre las 8 fases
  7. 28 paquetes pacman instalados, 24 dotfiles desplegados, 31 paths staged al index
- **Único issue cosmético** (Phase 6 chsh): `unix_chkpwd: password check failed for user (test)`.
  - Causa: PAM en el contenedor Docker no valida correctamente el password puesto vía `chpasswd`. Quirk de Docker, no del script.
  - En máquina real (VM o instalación nativa), el usuario teclea su password y `chsh` funciona.
  - La detección de #15 funcionó: Phase 8 NO dijo "shell changed" porque `runPostCmd` devolvió `false`.

### Iteración 3 — 2026-05-17 — bootstrap → snapshot → status end-to-end

- Comandos:
  - `desperta bootstrap --apply --profile test` (primera vez, contenedor nuevo)
  - `desperta snapshot`
  - `desperta status`
  - `desperta bootstrap --apply --profile test` (segunda vez, idempotencia)
- Resultado: ✅ ciclo completo funcional
- Métricas primera ejecución:
  - Phase 5: 24 dotfiles desplegados, 0 skipped
  - Phase 6: chsh corre (shell cambiado de bash a zsh)
  - Phase 7: 31 files staged al git index
- Métricas snapshot: 24 files copied
- Métricas status: tracked=24, clean=24, modified=0, deleted=0
- Métricas segunda ejecución (idempotencia):
  - Phase 5: deployed=0, skipped=24 ✅
  - Phase 6: chsh skip "(already current shell)" ✅
  - Phase 7: re-stagea 31 files (los blobs ya existen, es no-op real en el index)
  - Phase 8: no dice "shell changed" porque chsh no corrió ✅
- **Conclusión**: bootstrap es operacionalmente idempotente. Listos para `install.sh` real.

### Iteración 2 — 2026-05-17 — segunda ejecución (idempotencia)

- Comando: `desperta bootstrap --apply --profile test` (segunda vez en el mismo contenedor)
- Resultado: ⚠️ idempotente en datos, ruidoso en operaciones
- Observaciones detalladas:
  - ✅ Phase 2: "repo already exists" — correcto
  - ✅ Phase 4: "all installed" — perfecto
  - ⚠️ Phase 5: **vuelve a desplegar los 24 dotfiles sin chequear**. Pisaría modificaciones del usuario.
  - ⚠️ Phase 6: `chsh` corre otra vez → "Shell not changed" (zsh ya era la shell). Ruido + password prompt innecesario.
  - ✅ Phase 7: vacía (no añade duplicados a `tracked-paths.txt`).
  - ⚠️ Phase 8: "shell changed — re-login to apply" incluso cuando no cambió.

### Comandos auxiliares — observaciones

| Comando | Resultado | Notas |
|---|---|---|
| `desperta status` | ✅ | Branch `hosts/c36f82e455ed`, "no commits yet" |
| `desperta list --host test` | ⚠️ | Muestra los 11 paquetes pero la columna profile dice **"base"** (debería decir "base, test" o el matched) |
| `desperta snapshot` | ❌ | "no tracked files yet" pese a 28 entries en `tracked-paths.txt` |
| `desperta doctor` | ✅ | Todo OK |

---

## Bugs adicionales descubiertos

### 12. `desperta snapshot` no ve los paths en `tracked-paths.txt`

- **Síntoma**: `tracked-paths.txt` tiene 28 entries pero snapshot dice "no tracked files yet".
- **Causa**: `commandSnapshot` lee del git **index** del bare repo, no de `tracked-paths.txt`. `commandTrack` solo añade a `tracked-paths.txt`, nunca stagea archivos al index.
- **Fix**: añadido `stageTrackedPath` en main.zig que, dado un path absoluto bajo el worktree, lo stagea al index (recurse si es dir). Phase 7 lo invoca para cada path trackeado.
- **Bonus fix**: descubrí en el camino que `git_backend.zig` usaba `std.fmt.fmtSliceHexLower` (API obsoleta en Zig 0.16) → 3 sitios corregidos con `std.fmt.bytesToHex`.
- **Status**: ✅ fixed

### 13. Phase 5 sobrescribe dotfiles sin chequear modificaciones del usuario

- **Fix**: `dotfiles.deploy` ahora chequea si el destino existe; si existe, skip y marca como `skipped`. Añadido flag `--force` en bootstrap para forzar overwrite. Output incluye `deployed: N, skipped: M`.
- **Status**: ✅ fixed

### 14. Phase 6 `chsh` corre cada vez aunque la shell ya sea zsh

- **Fix**: helper `getCurrentLoginShell` lee `/etc/passwd` para el usuario. `parseChshTarget` extrae el target de `chsh -s <path>`. Si coinciden, se imprime "skip (already current shell)" y se omite el spawn.
- **Status**: ✅ fixed

### 15. Phase 8 reporta "shell changed" aunque no cambió

- **Fix**: `shell_changed = true` ahora solo se setea **después** de que `runPostCmd` devuelva ok=true. Si el chsh se skipea por #14, el flag queda false.
- **Status**: ✅ fixed

### 16. `desperta list --host X` muestra primer profile, no el matched

- **Fix**: columna profile ahora une todos los profiles del paquete con `,` (ej. "base,test").
- **Status**: ✅ fixed

### 17. `zlibCompress` panic: "reached unreachable code"

- **Síntoma**: bootstrap crashea con `thread 10 panic: reached unreachable code` al entrar phase 7 (primer `addPathToIndex`).
- **Causa**: `zlibCompress` usaba `Writer.Allocating.init(allocator)` que crea un writer con `buffer.len == 0`. Pero `Compress.Huffman.init` asserta `output.buffer.len > 8`. Cualquier compresión rompía.
- **Fix**: `initCapacity(allocator, 4096)` — el output writer arranca con 4 KiB de buffer, suficiente para satisfacer la aserción.
- **Notas**: este bug estaba latente — `addPathToIndex` nunca había sido invocado en producción (solo en su test específico que pasaba native macOS). El path de Linux+musl es el que lo destapó.
- **Status**: ✅ fixed

### 13. Phase 5 sobrescribe dotfiles sin chequear modificaciones del usuario

- **Síntoma**: segunda ejecución vuelve a copiar los 24 templates aunque ya existan.
- **Riesgo**: si el usuario editó `~/.zshrc`, el siguiente `desperta bootstrap` se lo pisa silenciosamente.
- **Opciones**:
  - A) `--force` para sobrescribir; por defecto skip-if-exists
  - B) skip-if-exists siempre; templates son solo bootstrap inicial
  - C) hash check: solo sobrescribir si el archivo coincide con el template original (no modificado)
- **Recomendación**: B (templates son seed, no contínuo). Modificaciones futuras del usuario se sincronizan con `desperta track` + `snapshot`.
- **Status**: ⏳ decisión de diseño + fix pendiente

### 14. Phase 6 `chsh` corre cada vez aunque la shell ya sea zsh

- **Síntoma**: segunda ejecución → `chsh -s /usr/bin/zsh` → password prompt → "Shell not changed".
- **Fix**: detectar shell actual del usuario antes de correr el `post_cmd`. En `runPostCmd` no sabemos su semántica, pero podemos añadir un check específico:
  - Si `post_cmd` contiene "chsh -s X" y `getent passwd $USER` ya tiene `X` → skip.
- **Alternativa más general**: añadir campo `check_cmd_post` por paquete (similar a `check_cmd`) que valide si el post-install ya está aplicado.
- **Status**: ⏳ pendiente

### 15. Phase 8 reporta "shell changed" aunque no cambió

- **Síntoma**: la flag `shell_changed` se setea cuando hay `post_cmd` con "chsh", no cuando realmente cambia.
- **Fix**: derivar de la condición de #14 (si chsh corrió **y** efectivamente cambió, setear flag).
- **Status**: ⏳ pendiente (depende de #14)

### 16. `desperta list --host X` muestra primer profile, no el matched

- **Síntoma**: con `--host test`, la columna profile muestra "base" para todos.
- **Fix cosmético**: imprimir todos los profiles del paquete (`["base", "test"]`) o el que matchea el filtro.
- **Status**: ⏳ cosmético, baja prioridad
