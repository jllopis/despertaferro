# Plan de implementacion

## Estado de esta fase

- [x] Crear rama limpia `phase/desperta-runtime` sin contenido legado.
- [x] Documentar proposito y alcance en `planning/purpose.md`.
- [x] Crear manifiesto inicial en `desperta.toml`.
- [x] Crear denylist de seguridad en `config/denylist.txt`.
- [x] Crear backlog por funcionalidad en `planning/*/tasks.md`.
- [x] Implementar primer CLI con `status`, `track`, `ignore`, `sync` y `doctor`.
- [x] Conectar backend Git nativo.
- [x] Implementar gestion de paquetes (list, install, bootstrap).
- [x] Ejecutar limpieza destructiva de historia remota tras confirmacion.

## Orden propuesto

1. Higiene del repositorio y politica de seguridad.
2. Manifiesto minimo del sistema.
3. Bootstrap y migracion.
4. CLI core.
5. Backend Git nativo.
6. Servicio residente.
7. Automatizacion agentica.

## Decision clave

La limpieza de historia sensible de ramas remotas requiere reescritura y
`force-push`. La nueva rama incluye las reglas, tareas y script de apoyo, pero
la operacion remota debe ejecutarse de forma explicita y coordinada porque
afecta a ramas en uso.
