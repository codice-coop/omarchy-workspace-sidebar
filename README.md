# Workspace sidebar para Omarchy

Barra lateral izquierda para el shell de Omarchy 4 (`omarchy-shell`). Muestra:

- **Workspaces**: número y título editable (doble click). El workspace con foco queda resaltado y destella
  al recibir el foco; los vacíos se ven atenuados. Cada fila cuenta los avisos sin cerrar.
- **Progreso del workspace con foco**: una franja vertical con el % del objetivo actual y una marca de
  dónde debería estar hoy según la fecha límite (el atraso se ve rayado). Al lado, bloques: avisos, foco
  (ahora / después), hitos, notas en Markdown y barras secundarias.

El contenido del panel de progreso sale de `~/.config/workspaces/sidebar/workspaceN.json`, uno por
workspace, y se actualiza solo cuando el archivo cambia. Lo escribe el CLI `wsbar`, pensado para que lo
use una sesión de Claude Code con la skill `progreso` incluida.

## Instalación

Requisitos: Omarchy 4 (shell basado en Quickshell) y Python 3.

```bash
omarchy plugin add <url-de-este-repo> --enable
omarchy restart shell
```

El plugin queda en `~/.config/omarchy/plugins/matis.sidebar/`. Para el CLI y la skill:

```bash
ln -sfn ~/.config/omarchy/plugins/matis.sidebar/bin/wsbar ~/.local/bin/wsbar
ln -sfn ~/.config/omarchy/plugins/matis.sidebar/skills/progreso ~/.claude/skills/progreso
```

Atajo para mostrar/ocultar, en `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + B", "Workspace sidebar", "omarchy-shell shell call matis.sidebar toggle ''")
```

## Uso

- **Mostrar/ocultar**: el atajo de arriba. **Cambiar de monitor**: los botones de arriba de la barra.
  **Ancho**: arrastrar el borde derecho. Todo se recuerda en `~/.config/workspaces/sidebar/_sidebar.json`.
- **Con Claude Code**: en la sesión de cada workspace, `/progreso` dimensiona el proyecto del repo y lo
  publica; después Claude marca avances y deja avisos solo.
- **A mano**: `wsbar --help`. Ejemplos:

```bash
wsbar where                                              # workspace de esta terminal
wsbar progress --label "Release 1.2" --percent 40 --start 2026-11-01 --deadline 2026-11-30
wsbar focus --now "Webhook de pagos" --next "Reintentos"
wsbar notice add --level warn "CI rojo en main"
wsbar scroll bottom
```

IPC: `omarchy-shell shell call matis.sidebar <toggle|show|hide|moveTo> <arg>`.

## Seguridad

- El contenido de los paneles puede venir, indirectamente, de texto de repos ajenos (Claude lo lee y lo
  resume). Por eso `wsbar` valida todo y limita tamaños, y la sidebar no carga imágenes, no interpreta
  HTML y sólo abre links `https://`, mostrando el destino real al pasar el mouse.
- La IPC del plugin expone sólo `toggle`, `show`, `hide` y `moveTo`.
- `wsbar` y la skill son symlinks a este checkout: actualizar el plugin también los actualiza.
  Instalalo sólo desde un repo en el que confíes.

## Formato

El formato de `workspaceN.json` y el diseño completo están en
[`docs/superpowers/specs/2026-11-06-workspace-sidebar-design.md`](docs/superpowers/specs/2026-11-06-workspace-sidebar-design.md).

## Desarrollo

```bash
node --test tests/model/                          # lógica del panel (SidebarModel.js)
python3 -m unittest discover -s tests/wsbar       # wsbar
omarchy plugin validate .
omarchy restart shell                             # el plugin es keepLoaded: los cambios aplican al reiniciar
```
