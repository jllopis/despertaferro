# Proposito funcional de despertaferro

`despertaferro` es un sistema personal para gestionar configuracion de
maquinas, bootstrap de nuevos equipos, migracion entre hosts y automatizacion
futura mediante agentes. La base de persistencia sigue siendo Git, pero la
interaccion diaria debe ocurrir a traves de un CLI propio llamado `desperta`.

El objetivo no es competir con herramientas genericas como `chezmoi`, `yadm` o
Ansible. La herramienta existe para cubrir necesidades propias, permitir
experimentos de bajo nivel con Git y abrir una ruta clara hacia automatizacion
asistida por LLMs.

## Principios

- Herramienta personal y opinada, no generica.
- Git como backend de estado, no como interfaz de usuario.
- CLI propio como unica superficie operativa normal.
- Bootstrap reproducible de maquinas nuevas.
- Migracion guiada desde una maquina vieja a otra nueva.
- Seguridad por defecto: snapshots, dry-run, denylist y revisiones antes de
  aplicar cambios destructivos.
- Separacion entre motor determinista y capa agentica.

## Modelo del sistema

El sistema gestiona un worktree situado en `$HOME`, con un repositorio bare
almacenado fuera de la propia configuracion del usuario:

```text
$XDG_STATE_HOME/despertaferro/repo.git      # repositorio bare
$XDG_CONFIG_HOME/despertaferro/config.toml  # configuracion local del runtime
$XDG_CACHE_HOME/despertaferro               # caches, locks, scans
$HOME                                       # worktree gestionado
```

La herramienta puede usar ramas por host, pero debe evolucionar hacia una base
comun:

```text
main                    # documentacion, manifiestos y metadata
base                    # configuracion compartida
hosts/gl2arch           # configuracion especifica de gl2arch
hosts/NewCO-Butterfly   # configuracion especifica de NewCO-Butterfly
```

Con solo dos dispositivos, las ramas por host siguen siendo una solucion
razonable. El valor adicional aparece cuando el CLI permite promocionar cambios
a una base comun, comparar divergencias y migrar configuracion entre maquinas
sin copiar ruido local.

## CLI

El comando `desperta` debe cubrir inicialmente:

```text
desperta init --host gl2arch
desperta status
desperta track ~/.config/nvim
desperta ignore ~/.config/zsh/.zsh_history
desperta snapshot
desperta sync
desperta migrate --from gl2arch --to newbox
desperta doctor
desperta service install
desperta agent audit
```

La primera version implementa un subconjunto: `status`, `track`, `ignore`,
`sync` y `doctor`. `sync` empieza como operacion segura de tipo dry-run hasta
que exista un backend Git conectado mediante `libgit2` u otra implementacion
nativa. El CLI no debe depender del binario `git` para las operaciones normales.

## Bootstrap

El bootstrap debe poder arrancar una maquina nueva con un unico punto de entrada:

```sh
curl -fsSL https://.../desperta-bootstrap | sh
```

Ese flujo debe:

- detectar sistema operativo, hostname, shell, permisos y dependencias base;
- descargar o compilar el binario `desperta`;
- inicializar el repositorio bare en `$XDG_STATE_HOME`;
- elegir un host existente o crear uno nuevo;
- aplicar configuracion en dry-run antes de tocar el sistema;
- crear snapshot antes de sobrescribir ficheros;
- instalar dependencias minimas por perfil;
- ejecutar `desperta doctor`.

## Migracion

La migracion no debe ser un simple checkout de otra rama. Debe comparar:

- sistema operativo y version;
- hardware relevante;
- monitores y configuracion grafica;
- shell, terminales y rutas locales;
- paquetes instalados;
- servicios de usuario;
- ficheros que no deben copiarse;
- secretos esperados pero no versionados.

Ejemplo objetivo:

```sh
desperta migrate --from gl2arch --to thinkpad
```

## Servicio residente

El servicio asociado es opcional y debe empezar como observador. Sus tareas
razonables son:

- detectar cambios en paths trackeados;
- avisar de ficheros sensibles;
- sugerir commits;
- crear snapshots;
- detectar drift;
- ejecutar health checks;
- programar updates bajo reglas explicitas.

Por defecto no debe trackear nuevos ficheros, commitear ni hacer push sin una
politica clara.

## Capa agentica

La IA debe vivir por encima del motor determinista. El motor debe saber
comparar, aplicar, revertir y validar. El agente debe proponer planes y explicar
riesgos.

Casos iniciales:

```text
desperta agent audit
desperta agent explain ~/.config/hypr/hyprland.conf
desperta agent plan-migration --to new-host
desperta agent clean-repo
desperta agent update-nvim
desperta agent detect-secrets
```

El agente debe emitir planes verificables, y el runtime debe ejecutarlos solo
con snapshots, dry-run y confirmaciones.

## Seguridad inmediata

El estado remoto actual contiene ruido y material sensible en ramas historicas.
La nueva fase exige:

- eliminar historiales de shell del tracking y de la historia;
- bloquear caches, logs, secretos y ficheros generados;
- corregir gitlinks/submodules rotos;
- mover el repositorio bare fuera de `.config/despertaferro`;
- crear un manifiesto minimo del sistema;
- empezar el CLI con operaciones seguras.

