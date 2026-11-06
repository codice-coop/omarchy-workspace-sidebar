---
name: progreso
description: >
  Mantiene el panel de progreso de la sidebar de workspaces (plugin matis.sidebar) con el CLI `wsbar`:
  dimensiona el proyecto del repo actual (objetivo, ítems con peso, hitos, foco, fecha límite), marca
  avances al terminar ítems planificados y deja avisos para que la persona revise. Usala cuando alguien
  diga "progreso", "/progreso", "dimensioná", "dimensioná el proyecto", "panel de progreso", "sidebar",
  "avance del proyecto", "cuánto falta", "actualizá el progreso", "marcá como hecho", "dejame un aviso",
  "avisame en la sidebar", "size the project", "progress panel", "project progress", "leave me a
  notice"; y sin que la pidan, al terminar un ítem de un plan ya cargado o cuando haya algo para revisar.
---

# progreso

El panel 2 de la sidebar muestra `~/.config/workspaces/sidebar/workspaceN.json` del workspace con foco.
Escribilo **sólo** con `wsbar`: valida y escribe atómico. Nunca edites ese archivo ni los planes de
`~/.local/share/wsbar/projects/` a mano. Si dudás de un flag, `wsbar <comando> --help`.

Las únicas fuentes son el repo y su `gh`. **Nunca** uses Notion ni nada fuera del repo.

## Workspace destino

`wsbar` detecta el workspace subiendo por los procesos ancestros hasta la ventana de la terminal (no
sigue el foco). Antes de escribir, corré `wsbar where`:

- Imprime `N` → seguí; todos los comandos apuntan ahí.
- Sale con 1 (no detectable; típico dentro de tmux u otro multiplexor) → preguntale a la persona en qué
  workspace está esta sesión y pasá `--ws N` en cada comando (o `export WSBAR_WS=N` en el mismo comando).

El plan es por proyecto (toplevel git del cwd); si trabajás fuera del repo, agregá `--project PATH` a
`plan …` y `publish`.

Códigos de salida: 0 ok; 1 problema de entorno (sin workspace, no es repo git, falta el archivo); 2
entrada inválida, **no escribió nada**: corregí el JSON o los flags y repetí. Si dice que un archivo
existente es inválido o tiene `version` desconocida, no lo pises: contale a la persona en el chat.

## 1. Dimensionar

Cuando lo pidan, o al empezar a trabajar en un repo sin plan (`wsbar plan show` falla con "no plan").
Si ya hay plan, no re-dimensiones: corré `wsbar publish` (el workspace puede estar mostrando otro
proyecto) y actualizá el foco.

1. Leé las fuentes del repo:
   - `docs/`, en especial `docs/superpowers/specs/` y `docs/superpowers/plans/` (el más reciente manda);
   - `tasks/` si existe;
   - `git log --oneline -n 50` y `git log --since=<fecha del spec> --stat` para ver qué ya está hecho;
   - PRs abiertos: `gh pr list --repo <owner/repo> --state open`, con el `<owner/repo>` sacado de
     `git remote get-url origin`. **Siempre** con `--repo`; nunca búsquedas globales de `gh`.
2. Proponé en el chat, corto:
   - **objetivo** (`label`, una línea: "Release 1.2 — pagos");
   - **ítems** de 4 a 15, cada uno con `id` estable en kebab-case, `label` corto y `weight` = esfuerzo
     relativo (1 chico, 2 medio, 3 grande, 5 enorme). Los que el `git log` o PRs mergeados muestran
     terminados van con `"status": "done"`;
   - **hitos** opcionales: agrupá ítems con el mismo `"milestone": "<nombre>"`; `wsbar` calcula
     done/current/pending solo, en el orden del plan;
   - **foco**: el ítem en curso y los 1–3 siguientes;
   - **start**: la fecha del spec/plan o del primer commit del objetivo; si arranca hoy, hoy;
   - **deadline**: sólo si aparece escrita en las fuentes (citá dónde). **Si no la encontrás,
     preguntala; no la inventes ni la estimes.** Si la persona dice que no hay, omití `deadline`.
3. Con el OK de la persona, aplicá:

```bash
wsbar plan set "$(cat <<'JSON'
{"label": "Release 1.2 — pagos", "start": "2026-10-20", "deadline": "2026-11-18",
 "items": [
   {"id": "modelo-datos", "label": "Modelo de datos", "weight": 2, "status": "done", "milestone": "Base"},
   {"id": "webhook", "label": "Webhook de pagos", "weight": 3, "milestone": "Checkout"},
   {"id": "reintentos", "label": "Reintentos", "weight": 1, "milestone": "Checkout"}
 ]}
JSON
)"
wsbar publish
wsbar focus --now "Webhook de pagos" --next "Reintentos" --next "Emails de recibo"
```

Usá el heredoc con `'JSON'` para que comillas y apóstrofes no rompan el shell. Fechas `YYYY-MM-DD`.
Para fechar un hito, después de `publish`: `wsbar milestones set '[{"label":"Checkout","status":"current","date":"2026-11-12"}, …]'`
con todos los hitos; los siguientes `publish` conservan esas fechas.

Re-planificar (cambió el alcance): `wsbar plan set` con el plan completo nuevo. Conserva el estado done
de los ids que no cambian, así que mantené los ids. Para reabrir un ítem, mandalo con `"status": "pending"`.

## 2. Avanzar

**Sin pedir permiso**, apenas termines y verifiques un ítem del plan (tests pasan, quedó funcionando):

```bash
wsbar plan done <item-id>          # marca, recalcula el % y publica; imprime el % nuevo
wsbar focus --now "<siguiente ítem>" --next "…" --next "…"
```

- Si no recordás los ids: `wsbar plan show` (incluye `percent`).
- `--next` reemplaza la lista entera; `--clear-next` la vacía.
- Terminado el último ítem: `wsbar focus --now "Objetivo cumplido" --clear-next` y avisá (abajo).
- No marques hecho algo a medias ni algo que no verificaste. No toques `wsbar progress --percent` si hay
  plan: el % sale de los pesos y el próximo `publish` lo pisaría.

## 3. Avisar

Cuando haya algo que la persona tenga que mirar: una decisión pendiente, CI roto, una tarea larga
terminada, algo bloqueado esperando credenciales o respuesta.

```bash
wsbar notice add --level warn "CI rojo en main: test_checkout falla tras el merge de #42"
```

- Una línea, accionable: qué pasa y qué se espera de la persona. Sin adornos.
- Nivel: `info` (terminé, para revisar), `warn` (decisión o bloqueo), `error` (algo roto).
- El comando imprime el id: recordalo. Cuando el aviso deje de aplicar (se resolvió, la persona
  respondió), sacalo con `wsbar notice rm <id>`. Si no tenés el id, buscalo con `wsbar show`.
- No dupliques: antes de agregar uno parecido, mirá `wsbar show` y reemplazá el viejo.

## Otros bloques (sólo si aportan)

- `wsbar text <id> "markdown"` — nota libre (negrita, itálica, código, links); `wsbar block rm <id>`.
- `wsbar meter <id> --label "Cobertura de tests" --percent 40` — barra secundaria (una medida aparte
  del % general, que sigue saliendo del plan); `--percent` es obligatorio al crearla.
- `wsbar block move <id> --to 0` — reordenar; `wsbar scroll top|bottom|<block-id>|0.4` — scroll inicial.
- `wsbar validate` — revisa el archivo del workspace actual.

Contale a la persona en una línea qué escribiste en el panel (p. ej. "Panel: 45 %, foco en Reintentos").
