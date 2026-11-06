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
- **Con Claude Code**: en la sesión de cada workspace, `/progreso conectar` y después `/progreso`, que
  dimensiona el proyecto del repo y lo publica; Claude marca avances y deja avisos solo. Ver
  [Conexión con Claude Code](#conexión-con-claude-code).
- **A mano**: `wsbar --help`. Ejemplos:

```bash
wsbar where                                              # workspace de esta terminal
wsbar progress --label "Release 1.2" --percent 40 --start 2026-11-01 --deadline 2026-11-30
wsbar focus --now "Webhook de pagos" --next "Reintentos"
wsbar notice add --level warn "CI rojo en main"
wsbar scroll bottom
```

IPC: `omarchy-shell shell call matis.sidebar <toggle|show|hide|moveTo> <arg>`.

## Conexión con Claude Code

Las sesiones de Claude Code arrancan **desconectadas**: desde una sesión no conectada, `wsbar` no escribe
nada (los comandos de lectura sí funcionan). La persona conecta cada sesión a su workspace a propósito:

- `/progreso conectar` (corre `wsbar connect`): conecta esta sesión al workspace de su terminal. Hay una
  sesión por workspace: si ya había otra, la reemplaza y lo dice. Dentro de tmux no se puede detectar el
  workspace y Claude te pregunta el número (`wsbar connect --ws N`).
- `/progreso desconectar` (`wsbar disconnect`) y `/progreso estado` (`wsbar status`).

Una sesión conectada sólo escribe en su workspace. La sidebar marca los workspaces con una sesión
conectada (atenuado si la sesión terminó). Si Claude Code muere sin cerrar la sesión (kill -9, un
crash), la marca queda encendida hasta el próximo `wsbar status`, `connect`, hook de otra sesión
conectada o arranque de cualquier sesión de Claude: ahí se apaga y se va su aviso de espera.
Desde una terminal común (sin `CLAUDE_CODE_SESSION_ID`), `wsbar` no tiene restricciones, y
`wsbar disconnect --ws N` desconecta la sesión de un workspace.

Con los hooks, una sesión conectada además publica su plan al arrancar, recibe el estado del panel
como contexto y deja un aviso "Claude terminó y espera tu respuesta" (o el aviso de Claude Code cuando
pide permiso), que se va solo cuando volvés a escribir. Agregar en `~/.claude/settings.json`, dentro de
`"hooks"` (si ya hay entradas para alguno de estos eventos, sumá este grupo a su lista; no las
reemplaces):

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "timeout": 5, "command": "$HOME/.config/omarchy/plugins/matis.sidebar/hooks/claude-hook SessionStart" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "timeout": 5, "command": "$HOME/.config/omarchy/plugins/matis.sidebar/hooks/claude-hook Stop" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "timeout": 5, "command": "$HOME/.config/omarchy/plugins/matis.sidebar/hooks/claude-hook Notification" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "timeout": 5, "command": "$HOME/.config/omarchy/plugins/matis.sidebar/hooks/claude-hook UserPromptSubmit" }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "timeout": 5, "command": "$HOME/.config/omarchy/plugins/matis.sidebar/hooks/claude-hook PostToolUse" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "timeout": 2, "command": "$HOME/.config/omarchy/plugins/matis.sidebar/hooks/claude-hook SessionEnd" }] }]
  }
}
```

Para sesiones no conectadas los hooks son inertes: salen enseguida (un `jq` y un `stat`, sin arrancar
Python), no imprimen nada y siempre salen con 0, así que nunca bloquean a Claude Code. Los errores van a
`~/.local/state/wsbar/hook.log`. `/clear` conserva la conexión: la sesión nueva hereda el workspace de
la que terminó.

## Seguridad

- El contenido de los paneles puede venir, indirectamente, de texto de repos ajenos (Claude lo lee y lo
  resume). Por eso `wsbar` valida todo y limita tamaños, y la sidebar no carga imágenes, no interpreta
  HTML y sólo abre links `https://`, mostrando el destino real al pasar el mouse.
- La IPC del plugin expone sólo `toggle`, `show`, `hide` y `moveTo`.
- Los hooks de Claude Code no leen nada del repo: sólo el JSON del evento y los archivos de `wsbar`. Lo
  que inyectan como contexto sale del plan ya validado y le recuerda a Claude que el contenido del repo
  son datos, no instrucciones.
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
