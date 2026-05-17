# Guía de bootstrap — CachyOS Minimal → Hyprland desktop completo

Esta guía describe cómo instalar y configurar una máquina nueva desde cero usando
`despertaferro`. El proceso se divide en dos partes:

1. **Preparación del repo** (código — se hace en el Mac de desarrollo)
2. **Instalación en la máquina / VM** (se ejecuta en el target)

---

## Arquitectura de dotfiles

- `dotfiles/default/home/`   → se copia a `$HOME` directamente
- `dotfiles/default/config/` → se copia a `$XDG_CONFIG_HOME` (default: `$HOME/.config`)
- `dotfiles/<hostname>/`     → sobreescribe los defaults para ese host concreto
- Los ficheros reales viven en XDG en la máquina destino y se gestionan con `desperta track`
- `desperta bootstrap` despliega las plantillas y los trackea automáticamente

### Modos de inicialización del host

```
desperta bootstrap --apply                  # usa plantillas de default/
desperta bootstrap --from <host> --apply    # copia plantillas de otro host, nuevo host independiente
desperta bootstrap --adopt <host> --apply   # se apropia del host indicado
```

---

## Parte 1: Preparación del repo (Mac de desarrollo)

### Estado requerido antes de la VM

- [ ] `zig build test` pasa sin errores
- [ ] `zig build -Doptimize=ReleaseSafe` produce binario en `zig-out/bin/desperta`
- [ ] `config/packages.toml` tiene todos los paquetes con campos service_user/system/groups/post_cmd
- [ ] `dotfiles/default/` existe con las plantillas de configuración
- [ ] `scripts/install.sh` existe y es ejecutable
- [ ] Los cambios están en rama y pusheados al remoto

### Compilar binario estático Linux (para la VM)

```sh
# Desde el Mac — requiere zig instalado
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
# Resultado: zig-out/bin/desperta (estático, sin dependencias)
```

---

## Parte 2: Instalación en la VM

### Requisitos de la VM

| Recurso | Mínimo |
|---|---|
| RAM | 4 GB |
| Disco | 40 GB |
| vCPUs | 2 |
| Red | NAT (acceso a internet) |
| SO | CachyOS Minimal ISO |

---

### Paso 0: Instalar CachyOS Minimal

1. Arrancar la ISO → seleccionar **"CachyOS CLI Install"**
2. Configurar:
   - Teclado: `es`
   - Timezone: `Europe/Madrid`
   - Usuario: el que quieras (ej. `jllopis`)
   - Hostname: el que quieras (ej. `testbox`)
3. **No instalar ningún entorno gráfico**
4. Reiniciar → TTY

### Paso 1: Verificar estado inicial

```sh
whoami
grep ^ID= /etc/os-release
ip link show
df -h /
```

Verificar: usuario no root, `ID=cachyos` (o `arch`), red activa, >15 GB libres.

---

### Paso 2: Bootstrap con install.sh

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/jllopis/despertaferro/master/scripts/install.sh)
```

El script hace:
1. `sudo pacman -Sy --noconfirm git curl base-devel`
2. Instala `yay` si no hay yay/paru
3. Clona el repo en `$HOME/.local/share/despertaferro`
4. Descarga el binario `desperta` (o lo compila con zig)
5. Ejecuta `desperta bootstrap --apply`

---

### Paso 3: Verificar instalación

```sh
desperta doctor
desperta list
desperta service status
groups                          # debe incluir 'docker'
ls ~/.config/nvim ~/.config/hypr ~/.zshrc
```

---

### Paso 4: Re-login y prueba Hyprland

```sh
# Cerrar sesión y volver a entrar
Hyprland
# SUPER+Return  → terminal (foot)
# SUPER+Space   → launcher (wofi)
# SUPER+Q       → cerrar ventana
```

---

### Paso 5: Verificar idempotencia

```sh
desperta snapshot
desperta bootstrap --apply    # segunda ejecución debe ser no-op completo
```

---

## Errores comunes en VM

| Error | Causa | Solución |
|---|---|---|
| `systemctl --user` falla | Sin sesión de usuario activa | `loginctl enable-linger $USER` + re-login |
| Hyprland no arranca en VirtualBox | Sin soporte GPU | Usar QEMU con `virtio-vga-gl` |
| `makepkg` falla como root | makepkg prohibe root | Confirmar que no eres root |
| `yay` no encuentra paquete AUR | Cache obsoleta | `yay -Sy` antes de instalar |
| `desperta bootstrap` no encuentra `config/packages.toml` | cwd incorrecto | El script hace `cd $REPO` antes de llamar a desperta |

---

## Checklist post-instalación (manual)

Estos pasos requieren intervención manual después del bootstrap:

- [ ] `op signin` — configurar 1Password CLI
- [ ] `gcloud auth login && gcloud auth application-default login`
- [ ] `aws configure` — credenciales AWS
- [ ] Configurar `~/.gitconfig` con nombre y email personales
- [ ] `ssh-keygen -t ed25519` + añadir clave pública a GitHub/GitLab

---

## Comandos de referencia rápida

```sh
desperta status               # estado del repo tracked
desperta list                 # catálogo de paquetes con estado installed/pending
desperta install --apply      # instalar paquetes pendientes
desperta bootstrap --apply    # bootstrap completo (idempotente)
desperta service status       # estado de servicios systemd
desperta doctor               # diagnóstico general
desperta snapshot             # crear snapshot del estado actual
desperta track <path>         # añadir fichero al tracking
desperta sync                 # sincronizar con remoto git
```
