# Sidebar de workspaces y progreso — diseño

Fecha: 2026-11-06 · Estado: aprobado en conversación, pendiente de revisión escrita

## Objetivo

Tener a la vista, todo el tiempo, **en qué workspace está el foco** y **cuánto falta en el proyecto de cada
workspace** (progreso hacia el objetivo actual y su fecha límite), más un lugar donde las sesiones de
Claude Code dejen avisos para revisar. Cada workspace corresponde, en la práctica, a un proyecto con su
propia sesión de Claude Code.

Criterios de éxito:

- De un vistazo se sabe qué workspace tiene foco, cuáles están vacíos y si el proyecto del workspace
  actual va adelantado o atrasado respecto de su fecha límite.
- El contenido del panel de progreso lo mantiene Claude sin intervención manual, y no puede quedar roto.
- Sigue la estética de Omarchy y es exportable como plugin de Omarchy (un repo git con `manifest.json`).

## Alcance y descomposición

Tres piezas, en este orden de construcción (más la conexión con sesiones, sección 5):

1. **Plugin `io.github.codice-coop.workspace-sidebar`** (QML, Quickshell dentro de `omarchy-shell`).
2. **CLI `wsbar`**: única vía recomendada de escritura del contenido; valida y escribe atómico.
3. **Skill de Claude `progreso`**: dimensiona, avanza y avisa usando `wsbar`.

El contrato entre las tres es el formato de `workspaceN.json` (sección "Formato").

Fuera de alcance: Notion u otras fuentes externas de tareas; sincronización entre máquinas; edición del
contenido del panel 2 desde la UI (salvo cerrar avisos).

## Arquitectura

```
Claude Code ──(skill progreso)──► wsbar ──escribe atómico──► ~/.config/workspaces/sidebar/workspaceN.json
                                    │                                   │ (FileView watchChanges)
                                    └─► ~/.local/share/wsbar/projects/  ▼
                                         (detalle por proyecto)   io.github.codice-coop.workspace-sidebar (omarchy-shell)
                                                                        │
                                Hyprland (Quickshell.Hyprland) ────────►┤ foco, ocupación, monitores
                                                                        ▼
                                          ~/.config/workspaces/sidebar/_sidebar.json (estado de UI)
```

### Repo e instalación

Se sigue al pie de la letra la guía de plugins de Omarchy (`$OMARCHY_PATH/shell/README.md`, "Installing
by hand" y "Installing a third-party plugin"):

- El repo **es** el directorio del plugin: `~/.config/omarchy/plugins/io.github.codice-coop.workspace-sidebar/`, con `manifest.json`
  en la raíz. Es la misma forma que deja `omarchy plugin add` (un checkout git), así que exportarlo es
  publicar este repo y que otros lo instalen con `omarchy plugin add <url>`. Sin symlinks.
- Ciclo de desarrollo: guardar (recarga automática; `omarchy-shell shell rescanPlugins` si no aplica;
  `omarchy restart shell` para cambios en el plugin por ser `keepLoaded`), `omarchy plugin validate
  ~/.config/omarchy/plugins/io.github.codice-coop.workspace-sidebar`, y `omarchy plugin enable io.github.codice-coop.workspace-sidebar` la primera vez.
- `wsbar` (`bin/wsbar`) y la skill (`skills/progreso/`) viajan en el mismo repo, porque son parte de la
  funcionalidad exportable. No son código del plugin, así que se exponen fuera de él: `~/.local/bin/wsbar`
  y `~/.claude/skills/progreso` apuntan al repo.

## 1. Plugin `io.github.codice-coop.workspace-sidebar`

### Manifest

`kinds: ["panel"]`, `keepLoaded: true` (se monta al arrancar el shell y persiste). Expone IPC:
`toggle`, `show`, `hide`, `moveTo <monitor>`. Nota: al ser `keepLoaded`, los cambios de código del
plugin requieren `omarchy restart shell` (el hot-reload no reemplaza instancias kept).

### Ventana

- `PanelWindow` layer-shell anclada a izquierda, arriba y abajo, con **zona exclusiva** igual a su ancho:
  las ventanas se reacomodan al costado. Convive con la barra de Omarchy (hoy abajo).
- Un solo monitor a la vez. Colores, tipografía y espaciados desde `qs.Commons` (`Color`, `Style`) para
  seguir el tema activo y sus cambios.
- **Ocultar/mostrar**: `Super+Alt+B` (libre hoy) → `omarchy-shell shell call io.github.codice-coop.workspace-sidebar toggle`,
  agregado en `~/.config/hypr/bindings.lua`. Oculta = sin ventana y sin zona exclusiva.
- **Ancho**: se arrastra el borde derecho (handle de ~4 px, cursor de resize). Mínimo 180 px, máximo
  600 px.
- Monitor, ancho y visibilidad persisten en `_sidebar.json`. Si el monitor guardado no existe, usa el
  monitor con foco.

### Layout vertical (todo a 100 % del ancho)

1. **Selector de monitor**: un botón por monitor de `Quickshell.screens` (nombre corto, p. ej. `DP-1`);
   el actual resaltado. Click → la sidebar se muda a ese monitor.
2. **Panel 1 — workspaces**: alto según contenido.
3. **Panel 2 — progreso**: ocupa el resto; scroll propio.

### Panel 1 — workspaces

- Lista: misma regla que el widget `omarchy.workspaces` (siempre 1–5, más los existentes hasta 10).
- Cada fila: número + título + **contador de avisos sin cerrar** de ese workspace (oculto si es 0).
- Título por defecto `Workspace N`; **doble click** para editar inline, Enter guarda, Esc cancela. El
  layer-shell pide foco de teclado sólo mientras se edita. Persiste en `_sidebar.json`.
- **Vacío** (sin ventanas): opacidad atenuada, como la barra.
- **Foco**: el workspace `Hyprland.focusedWorkspace` resaltado (fondo con acento del tema), en cualquier
  monitor.
- **Destello**: al cambiar el foco, la fila nueva hace un pulso breve (~600 ms) del color de acento,
  de opacidad 0 → ~0,35 → 0.
- Click en una fila → enfoca ese workspace (mismo dispatch que la barra).

### Panel 2 — progreso del workspace con foco

Muestra `workspaceN.json` del workspace con foco; cambia al cambiar el foco.

- **Franja de progreso general** (fija, fuera del scroll), pegada al borde izquierdo, a todo el alto del
  panel 2, ~6 px de ancho:
  - se llena de abajo hacia arriba según `progress.percent`;
  - **marca de ritmo**: rayita horizontal en el % esperado para hoy,
    `clamp((hoy − start) / (deadline − start), 0, 1)`; sin `start` o `deadline`, no hay marca;
  - color de la barra: normal si `percent ≥ esperado`, color de advertencia del tema si va atrasada;
  - arriba, texto chico con el % (`62%`); abajo, días restantes (`12d`; `hoy`; `−3d` si pasó la fecha);
  - tooltip: `label`, fecha límite, y "adelantado/atrasado N %".
- **Bloques** a la derecha de la franja, en el orden del archivo, dentro de un `Flickable` con scroll.
- **Scroll**: al cargar o cambiar el archivo se aplica `scroll`; el scroll manual se respeta hasta el
  próximo cambio del archivo.
- Sin archivo: estado vacío con el texto "Sin progreso. Pedile a Claude: /progreso".
- JSON inválido o con `version` desconocida: se mantiene el último contenido válido y se muestra un
  indicador chico de error (tooltip con el mensaje).

### Lógica pura

Cálculos (ritmo, días restantes, avisos pendientes, normalización del archivo, resolución de scroll) en
`SidebarModel.js`, sin dependencias de QML, siguiendo el patrón `*Model.js` de Omarchy. Se prueba con
`node --test`.

## 2. Formato `~/.config/workspaces/sidebar/workspaceN.json`

```json
{
  "version": 1,
  "project": "/home/matis/Work/ejemplo",
  "progress": {
    "label": "Release 1.2 — pagos",
    "percent": 62,
    "start": "2026-10-20",
    "deadline": "2026-11-18"
  },
  "scroll": "top",
  "blocks": [
    { "id": "avisos", "type": "notices", "items": [
      { "id": "n1", "level": "warn", "text": "Tests de checkout fallan en CI", "at": "2026-11-06T10:12" }
    ]},
    { "id": "foco", "type": "focus", "now": "Webhook de pagos", "next": ["Reintentos", "Emails de recibo"] },
    { "id": "hitos", "type": "milestones", "items": [
      { "label": "Modelo de datos", "status": "done" },
      { "label": "Checkout", "status": "current", "date": "2026-11-12" },
      { "label": "Facturación", "status": "pending" }
    ]},
    { "id": "nota", "type": "text", "text": "Esperando credenciales de **producción**." },
    { "id": "sub", "type": "progress", "label": "Cobertura de tests", "percent": 40 }
  ]
}
```

Reglas:

- `version: 1` obligatorio. `project` opcional (ruta del repo; informativo).
- `progress` opcional; `percent` 0–100; fechas `YYYY-MM-DD`.
- `scroll`: `"top"` | `"bottom"` | id de bloque | número 0–1 (fracción). Default `"top"`.
- `blocks[].id` único dentro del archivo; `type` ∈ `notices`, `focus`, `milestones`, `text`, `progress`.
  Tipos desconocidos se ignoran (compatibilidad hacia adelante).
- `notices.items[].level` ∈ `info`, `warn`, `error`; `id` único y estable.
- `milestones.items[].status` ∈ `done`, `current`, `pending`.
- `text.text` admite Markdown básico (negrita, itálica, código, links).

### Estado de UI: `~/.config/workspaces/sidebar/_sidebar.json`

Lo escribe sólo el plugin:

```json
{
  "version": 1,
  "monitor": "DP-1",
  "width": 260,
  "visible": true,
  "titles": { "3": "Cliente X — API" },
  "dismissed": { "3": ["n1"] }
}
```

Cerrar un aviso agrega su id a `dismissed[N]`. Un aviso descartado no se muestra ni cuenta en el contador
aunque siga en `workspaceN.json`. Al cerrar uno, la lista de ese workspace se poda a los ids que el
workspace todavía tiene (cada aviso de "Claude espera" trae un id nuevo y si no la lista crecería sin
fin); además cada lista guarda como máximo los 100 ids más nuevos, y un `_sidebar.json` de más de 256 KB
se lee como los valores por defecto. Separar este archivo garantiza que Claude y la UI nunca escriban el mismo
archivo.

## 3. CLI `wsbar`

Python 3 sólo con stdlib. Toda escritura: validar contra el formato → archivo temporal en el mismo
directorio → `rename` atómico. Si la validación falla, no escribe y sale con código ≠ 0 y un mensaje claro.

Workspace destino: `--ws N`, o `WSBAR_WS`, o **autodetección** (recorre los procesos ancestros del
proceso actual y busca su pid en `hyprctl clients -j` para obtener el workspace de la terminal). Si no
puede determinarlo, falla pidiendo `--ws`.

Comandos (núcleo; el plan puede ajustar nombres):

```
wsbar where                                   # imprime el workspace detectado
wsbar show                                    # imprime el JSON actual
wsbar progress --label .. --percent N --start F --deadline F
wsbar focus --now ".." --next ".." --next ".."
wsbar milestones set '<json>' | wsbar milestone status <label> done|current|pending
wsbar notice add --level warn "texto"         # genera id estable; imprime el id
wsbar notice rm <id>
wsbar text <block-id> "markdown"
wsbar meter <block-id> --label .. --percent N  # bloque `progress` (barra secundaria)
wsbar block rm <id> | wsbar block move <id> --to N
wsbar scroll top|bottom|<block-id>|0.4
wsbar validate [archivo]
```

### Detalle por proyecto: `~/.local/share/wsbar/projects/<slug>.json`

Clave = ruta del toplevel git del proyecto (slug derivado). Guarda el objetivo, la fecha límite, los ítems
planificados con peso y estado, y un historial corto de avances. Comandos:

```
wsbar plan set '<json>'        # objetivo, start, deadline, items[{id,label,weight}]
wsbar plan done <item-id>      # marca hecho, recalcula percent y publica en el workspace
wsbar plan show
wsbar publish                  # vuelve a renderizar progress/focus/milestones al workspace actual
```

`percent = Σ peso(ítems hechos) / Σ peso(ítems) × 100`. Así el % no depende de la estimación de cada
sesión. Si el workspace pasa a otro proyecto, el detalle no se pierde: `publish` desde la otra sesión
reescribe el workspace.

## 4. Skill `progreso`

Una skill con tres usos, todos vía `wsbar`:

1. **Dimensionar** (al empezar la sesión o cuando se pide): lee las fuentes del repo — specs y planes
   (`docs/`, `docs/superpowers/`), tareas versionadas si existen, `git log`, PRs abiertos (`gh`, siempre
   acotado al repo) — y propone objetivo, ítems con peso, hitos, foco y fecha límite. **Si no encuentra la
   fecha límite, la pregunta; no la inventa.** Con el OK, `wsbar plan set` + `publish`.
2. **Avanzar**: al terminar un ítem planificado, sin que se lo pidan: `wsbar plan done` y actualiza foco.
3. **Avisar**: cuando hay algo para que la persona revise (decisión pendiente, CI roto, tarea larga
   terminada): `wsbar notice add`. Avisos cortos, una línea, accionables.

No usa Notion ni fuentes fuera del repo. Antes de todo esto, la sesión tiene que estar conectada a su
workspace (sección 5); la skill también cubre `/progreso conectar`, `desconectar` y `estado`.

## 5. Conexión con sesiones de Claude Code

Agregado el 2026-11-06, aprobado en conversación.

### Objetivo

Que sólo escriba el panel de un workspace la sesión de Claude Code que la persona eligió para él, y que
esa sesión mantenga el panel sin depender de que Claude se acuerde: publicar el plan al arrancar y avisar
cuando espera una respuesta.

Reglas:

- Las sesiones están **desconectadas por defecto**. La persona conecta una sesión con
  `/progreso conectar` (`wsbar connect`) y la desconecta con `/progreso desconectar` (`wsbar disconnect`);
  `/progreso estado` es `wsbar status`. Claude nunca conecta por iniciativa propia.
- **Una sesión por workspace**: conectar otra reemplaza a la anterior y lo informa
  ("reemplazó la sesión <prefijo>"). Una sesión está en un solo workspace: conectarla en otro la mueve
  ("movida desde el workspace M").
- Los hooks sólo actúan para sesiones conectadas.

### Archivos

`<WSBAR_CONFIG_DIR>/_sessions.json` (default `~/.config/workspaces/sidebar/_sessions.json`). Lo escribe
sólo `wsbar`, atómico y validado; la sidebar lo lee y nunca lo escribe:

```json
{"version": 1, "workspaces": {"5": {"session": "<session-id>", "project": "/abs/path o vacío",
                                    "since": "2026-11-06T10:12", "active": true,
                                    "host": "4026531836-12345-678901"}}}
```

- Claves `"1"`..`"10"`; ids de sesión `^[A-Za-z0-9_-]{1,128}$` (otro valor se rechaza).
- `project`: toplevel git del cwd al conectar (o `--project`), vacío si no hay.
- `active`: `false` después de `SessionEnd`; el link se conserva para que una sesión retomada con el
  mismo id siga conectada (`SessionStart` lo vuelve a `true`).
- `host` (opcional): el proceso de Claude Code de la sesión, `<inodo del pid namespace>-<pid>-<inicio en
  ticks>`. Lo graba `connect` corrido desde la sesión (no desde una terminal con `--session`) y lo
  actualizan `SessionStart`, el traspaso de `/clear` y cualquier hook de la sesión que corra en otro
  proceso. Si la sesión muere sin `SessionEnd` (kill -9, OOM, un crash), el siguiente `wsbar` que pase
  por los links (`status`, `connect`, `disconnect`, una escritura con restricción por sesión, un hook de
  una sesión conectada o el `SessionStart` de cualquier sesión mientras haya alguna conectada) ve que ese
  proceso ya no existe, marca el link `active: false` y saca su aviso de espera. Un `host` grabado en
  otro pid namespace (un sandbox) no se juzga, y la sesión que corre el comando o el hook nunca se toma
  por muerta.

Estado en `<WSBAR_STATE_DIR>` (default `~/.local/state/wsbar`):

- `sessions/<id>`: marcador de sesión conectada (contenido: el número de workspace). Lo crean `connect` y
  lo borran `disconnect` y el reemplazo. Es el camino rápido de los hooks.
- `waiting/<id>`: existe mientras se muestra un aviso de "Claude espera" de esa sesión (contenido: el id
  del aviso).
- `handoff/`: nota de traspaso para `/clear` (ver abajo), válida 60 s.
- `wsbar.lock`: serializa las escrituras de comandos y hooks.
- `hook.log`: errores de los hooks, rotado a 64 KB.

### Restricción por sesión en `wsbar`

Si `CLAUDE_CODE_SESSION_ID` está definida (`wsbar` corre dentro de Claude Code):

- todo comando que escribe un `workspaceN.json` o un plan (incluidos `plan set`, `plan done` y
  `publish`) exige que la sesión esté conectada y escribe sólo en su workspace; si no, sale con 1 y un
  mensaje en castellano que pide conectar con "/progreso conectar". `--ws` y `WSBAR_WS` no permiten
  apuntar a otro workspace;
- sin `--ws`, una sesión conectada apunta a su workspace sin autodetección (funciona dentro de tmux), y
  `wsbar where` lo imprime;
- los comandos de lectura (`where`, `show`, `validate`, `plan show`, `status`) y `connect`/`disconnect`
  funcionan siempre;
- `disconnect` desconecta la sesión (la de la variable o la de `--session`); si además se da `--ws N` o
  `WSBAR_WS` y la sesión no está conectada a N, sale con 1 sin tocar nada y dice que para desconectar
  otro workspace se use una terminal.

Sin esa variable (una terminal común) no hay restricción. `wsbar disconnect --ws N` desconecta desde la
terminal la sesión de un workspace.

`wsbar notice add --id ID` permite fijar el id del aviso (mismas reglas que los otros ids); si ya existe
uno con ese id, lo reemplaza.

### Hooks

`hooks/claude-hook <Evento>` se registra en `~/.claude/settings.json` (el bloque está en el README) para
`SessionStart`, `Stop`, `Notification`, `UserPromptSubmit`, `PostToolUse` y `SessionEnd`. Corre en cada
llamada a herramienta, así que en bash, antes de arrancar Python, lee `session_id` del JSON de stdin con
`jq`, lo valida y sale si no existe `sessions/<id>` (salvo en `SessionStart` mientras haya alguna sesión
conectada o una nota de traspaso, para que Python detecte sesiones muertas y el traspaso de `/clear`); para `UserPromptSubmit` y `PostToolUse` también sale
si no existe `waiting/<id>`. Recién entonces le pasa el evento a `wsbar hook <Evento>`.

`wsbar hook` siempre sale con 0, no imprime nada salvo el JSON de `SessionStart`, tarda como máximo
~2 s (1,1 s en `SessionEnd`, que Claude Code limita a 1,5 s), registra errores en `hook.log`, ignora
eventos desconocidos y escribe sólo en el workspace del link, nunca por autodetección.

| Evento | Qué hace |
| --- | --- |
| `SessionStart` | marca `active: true`; si el proyecto del link tiene plan, lo publica; imprime `hookSpecificOutput.additionalContext` (≤ 2 KB) con el workspace, el plan (label, %, pendientes con ids), el foco y las reglas de la skill; sin plan, pide ofrecer `/progreso`. Sin conexión, nada |
| `Stop` | saca el aviso de espera anterior de la sesión y agrega uno nuevo, `info`, "Claude terminó y espera tu respuesta · <proyecto>" |
| `Notification` | igual, `warn`, con el mensaje de Claude Code (una línea, ~120 caracteres). Sólo para los `notification_type` en que Claude espera a la persona: `permission_prompt`, `idle_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input`, `quota_auto_resume_stale`, `quota_auto_resume_disabled`, o sin tipo (versiones viejas). Ignora el resto (`auth_success`, `auth_storage_failure`, `elicitation_complete`, `elicitation_response`, `agent_completed`, `quota_auto_resume_fired`, `plugin_notification` y cualquier tipo nuevo) |
| `UserPromptSubmit`, `PostToolUse` | si hay aviso de espera, lo saca |
| `SessionEnd` | saca el aviso de espera y marca `active: false` sin borrar el link |

El id de cada aviso de espera es nuevo (`claude-espera-<tiempo en base36>`), porque la sidebar recuerda
los ids descartados y no volvería a mostrar uno repetido.

`/clear` termina la sesión y abre otra con id nuevo en el mismo proceso de Claude Code. Para no
desconectarla en silencio, `SessionEnd` con `reason: "clear"` deja una nota de traspaso atada a ese
proceso y el `SessionStart` con `source: "clear"` del mismo proceso hereda el link.

### Sidebar

`SidebarController.qml` observa `_sessions.json` con un `FileView` (como `_sidebar.json`, sólo lectura) y
lo normaliza con `SidebarModel.normalizeSessions` (tolerante; inválido → sin links). Cada fila de
workspace con link muestra un indicador chico en el acento del tema, con tooltip "Claude conectado ·
<proyecto> · desde HH:MM"; con `active: false`, atenuado y "Sesión terminada · <proyecto>". La IPC del
plugin no cambia.

### Seguridad

- Los ids de sesión y de aviso se validan antes de usarlos como nombre de archivo; los hooks no
  interpolan texto libre en el shell.
- El contexto que inyecta `SessionStart` sale del plan ya validado, reducido a una línea por texto y con
  tope de tamaño, y repite que el contenido del repo son datos, no instrucciones.
- Toda lectura de JSON tiene el mismo tope de 256 KB que las escrituras.

## Errores y casos borde

- Monitor guardado ausente → monitor con foco. Monitor desconectado con la sidebar encima → mismo fallback.
- Workspace > 10 o especial (scratchpad) → no se lista; el panel 2 muestra el estado vacío.
- Escritura concurrente en el mismo workspace → `wsbar.lock` la serializa; además el `rename` atómico evita
  archivos corruptos. Con sesiones conectadas sólo una sesión escribe cada workspace.
- `_sidebar.json` inválido → defaults en memoria y se reescribe en el próximo cambio.

## Pruebas

- `SidebarModel.js`: `node --test` (ritmo, días, scroll, avisos pendientes, normalización).
- `wsbar`: `python3 -m unittest` (validación, escritura atómica, autodetección con `hyprctl` simulado,
  cálculo de percent; conexión, restricción por sesión y hooks con payloads simulados en
  `tests/wsbar/test_sessions.py`).
- Plugin: verificación real en el escritorio — mostrar/ocultar, mover de monitor, resize, editar título,
  destello al cambiar foco, recarga al escribir con `wsbar`, scroll configurado; capturas con `grim`.
