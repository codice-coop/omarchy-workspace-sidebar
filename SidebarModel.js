.pragma library

// Pure logic for the workspace sidebar: workspaceN.json normalization, pace
// math for the progress strip, pending notices, scroll resolution, the
// _sidebar.json UI state and the _sessions.json links. Qt-free so it runs
// under `node --test` (tests/model/). Dates are ISO strings; "today" is always passed in.

var MS_PER_DAY = 86400000
var DEFAULT_WIDTH = 260
var MIN_WIDTH = 180
var MAX_WIDTH = 600
var BLOCK_TYPES = ["notices", "focus", "milestones", "text", "progress"]
var NOTICE_LEVELS = ["info", "warn", "error"]
var MILESTONE_STATUSES = ["done", "current", "pending"]

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function isFiniteNumber(value) {
  return typeof value === "number" && isFinite(value)
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim() !== ""
}

function stringOr(value, fallback) {
  return typeof value === "string" ? value : fallback
}

// Limits on what a workspace file may make the shell parse and draw. The
// shell also hosts the lock screen and polkit, so a huge file must not stall
// it: oversized files are rejected, long lists and strings are cut.
var MAX_FILE_CHARS = 256 * 1024
var MAX_BLOCKS = 50
var MAX_ITEMS = 100
var MAX_STRING = 2000
var MAX_TEXT = 8000

function cap(value, max) {
  return value.length > max ? value.slice(0, max) + "…" : value
}

function cappedString(value, fallback) {
  return typeof value === "string" ? cap(value, MAX_STRING) : fallback
}

function percentOr(value, fallback) {
  return isFiniteNumber(value) ? clamp(value, 0, 100) : fallback
}

// Day number (UTC) of a YYYY-MM-DD string, or null. Anything after the date
// (a time, a zone) is ignored; impossible dates like 2026-02-30 are rejected.
function dayNumber(value) {
  if (typeof value !== "string") return null
  var match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value)
  if (!match) return null
  var year = parseInt(match[1], 10)
  var month = parseInt(match[2], 10)
  var day = parseInt(match[3], 10)
  var ms = Date.UTC(year, month - 1, day)
  var date = new Date(ms)
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null
  return Math.round(ms / MS_PER_DAY)
}

function validDate(value) {
  return typeof value === "string" && value.length === 10 && dayNumber(value) !== null
}

// ---- workspaceN.json

function normalizeProgress(raw) {
  if (!isPlainObject(raw)) return null
  var progress = { label: cappedString(raw.label, ""), percent: percentOr(raw.percent, 0) }
  if (validDate(raw.start)) progress.start = raw.start
  if (validDate(raw.deadline)) progress.deadline = raw.deadline
  return progress
}

function normalizeScroll(raw) {
  if (raw === "top" || raw === "bottom") return raw
  if (isFiniteNumber(raw) && raw >= 0 && raw <= 1) return raw
  if (nonEmptyString(raw)) return raw
  return "top"
}

// Notice ids drive dismissal, so an item without one gets an id derived from
// its block and position: stable as long as the file keeps its order.
function normalizeNotices(raw, block) {
  var items = Array.isArray(raw.items) ? raw.items.slice(0, MAX_ITEMS) : []
  block.items = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!isPlainObject(item) || !nonEmptyString(item.text)) continue
    var notice = {
      id: nonEmptyString(item.id) ? item.id : block.id + "-n" + i,
      level: NOTICE_LEVELS.indexOf(item.level) !== -1 ? item.level : "info",
      text: cap(item.text, MAX_STRING)
    }
    if (nonEmptyString(item.at)) notice.at = cap(item.at, 40)
    block.items.push(notice)
  }
}

function normalizeFocus(raw, block) {
  block.now = cappedString(raw.now, "")
  block.next = []
  var next = Array.isArray(raw.next) ? raw.next.slice(0, MAX_ITEMS) : []
  for (var i = 0; i < next.length; i++) {
    if (nonEmptyString(next[i])) block.next.push(cap(next[i], MAX_STRING))
  }
}

function normalizeMilestones(raw, block) {
  var items = Array.isArray(raw.items) ? raw.items.slice(0, MAX_ITEMS) : []
  block.items = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!isPlainObject(item) || !nonEmptyString(item.label)) continue
    var milestone = {
      label: cap(item.label, MAX_STRING),
      status: MILESTONE_STATUSES.indexOf(item.status) !== -1 ? item.status : "pending"
    }
    if (validDate(item.date)) milestone.date = item.date
    block.items.push(milestone)
  }
}

function normalizeBlock(raw, index, usedIds) {
  if (!isPlainObject(raw) || BLOCK_TYPES.indexOf(raw.type) === -1) return null

  // Ids are meant to be unique; a missing or repeated one falls back to
  // "b<index>" so scroll targets and notice ids never collide.
  var id = nonEmptyString(raw.id) && raw.id.length <= 200 && !usedIds[raw.id] ? raw.id : "b" + index
  while (usedIds[id]) id = id + "_"
  usedIds[id] = true

  var block = { id: id, type: raw.type }
  if (raw.type === "notices") normalizeNotices(raw, block)
  else if (raw.type === "focus") normalizeFocus(raw, block)
  else if (raw.type === "milestones") normalizeMilestones(raw, block)
  else if (raw.type === "text") block.text = typeof raw.text === "string" ? cap(raw.text, MAX_TEXT) : ""
  else if (raw.type === "progress") {
    block.label = cappedString(raw.label, "")
    block.percent = percentOr(raw.percent, 0)
  }
  return block
}

// Only bad JSON, a non-object or a version other than 1 fail; everything else
// degrades field by field, since the sidebar keeps the last valid config on
// failure and a single bad block should not freeze it.
function normalizeWorkspaceConfig(rawText) {
  var data
  var source = String(rawText === undefined || rawText === null ? "" : rawText)
  if (source.length > MAX_FILE_CHARS) {
    return { ok: false, config: null, error: "Archivo demasiado grande (más de " + (MAX_FILE_CHARS / 1024) + " KB)" }
  }
  try {
    data = JSON.parse(source)
  } catch (e) {
    return { ok: false, config: null, error: "JSON inválido: " + e.message }
  }

  if (!isPlainObject(data)) return { ok: false, config: null, error: "El archivo no es un objeto JSON" }
  if (data.version !== 1) {
    var shown = data.version === undefined ? "ausente" : JSON.stringify(data.version)
    return { ok: false, config: null, error: "Versión no soportada: " + shown }
  }

  var blocks = []
  var usedIds = {}
  var rawBlocks = Array.isArray(data.blocks) ? data.blocks.slice(0, MAX_BLOCKS) : []
  for (var i = 0; i < rawBlocks.length; i++) {
    var block = normalizeBlock(rawBlocks[i], i, usedIds)
    if (block) blocks.push(block)
  }

  return {
    ok: true,
    config: {
      version: 1,
      project: cappedString(data.project, ""),
      progress: normalizeProgress(data.progress),
      scroll: normalizeScroll(data.scroll),
      blocks: blocks
    },
    error: ""
  }
}

// ---- Progress strip

// Expected percent is linear between start and deadline. A zero (or negative)
// span has no ramp, so it reads as fully due from the start date on.
function paceInfo(progress, today) {
  var info = { percent: 0, expected: null, behind: false, daysLeft: null, daysLabel: "", tooltip: "" }
  if (!isPlainObject(progress)) return info

  info.percent = percentOr(progress.percent, 0)
  var todayDay = dayNumber(today)
  var startDay = dayNumber(progress.start)
  var deadlineDay = dayNumber(progress.deadline)

  if (todayDay !== null && startDay !== null && deadlineDay !== null) {
    var span = deadlineDay - startDay
    var ratio = span > 0 ? (todayDay - startDay) / span : (todayDay >= startDay ? 1 : 0)
    info.expected = clamp(ratio, 0, 1) * 100
    info.behind = info.percent < info.expected
  }

  if (todayDay !== null && deadlineDay !== null) {
    info.daysLeft = deadlineDay - todayDay
    info.daysLabel = info.daysLeft === 0 ? "hoy" : info.daysLeft + "d"
  }

  var lines = []
  if (nonEmptyString(progress.label)) lines.push(progress.label)
  if (validDate(progress.deadline)) lines.push("Fecha límite: " + progress.deadline)
  if (info.expected !== null) {
    var diff = Math.round(Math.abs(info.percent - info.expected))
    if (info.behind) lines.push("Atrasado " + Math.max(1, diff) + " %")
    else if (diff === 0) lines.push("En ritmo")
    else lines.push("Adelantado " + diff + " %")
  }
  info.tooltip = lines.join("\n")
  return info
}

// ---- Notices

function pendingNotices(config, dismissedIds) {
  var dismissed = Array.isArray(dismissedIds) ? dismissedIds : []
  var pending = []
  var blocks = isPlainObject(config) && Array.isArray(config.blocks) ? config.blocks : []
  for (var i = 0; i < blocks.length; i++) {
    var block = blocks[i]
    if (!isPlainObject(block) || block.type !== "notices" || !Array.isArray(block.items)) continue
    for (var j = 0; j < block.items.length; j++) {
      var item = block.items[j]
      if (isPlainObject(item) && dismissed.indexOf(item.id) === -1) pending.push(item)
    }
  }
  return pending
}

function pendingCount(config, dismissedIds) {
  return pendingNotices(config, dismissedIds).length
}

// ---- Scroll

function resolveScroll(scroll, blockOffsets, contentHeight, viewHeight) {
  var content = isFiniteNumber(contentHeight) ? contentHeight : 0
  var view = isFiniteNumber(viewHeight) ? viewHeight : 0
  var max = Math.max(0, content - view)

  if (scroll === "top") return 0
  if (scroll === "bottom") return max
  if (isFiniteNumber(scroll)) return clamp(scroll, 0, 1) * max
  if (typeof scroll === "string" && isPlainObject(blockOffsets)
      && Object.prototype.hasOwnProperty.call(blockOffsets, scroll)
      && isFiniteNumber(blockOffsets[scroll])) {
    return clamp(blockOffsets[scroll], 0, max)
  }
  return 0
}

// ---- Workspace list (same rule as the omarchy.workspaces bar widget)

function workspaceIds(existingIds) {
  var ids = [1, 2, 3, 4, 5]
  var existing = Array.isArray(existingIds) ? existingIds : []
  for (var i = 0; i < existing.length; i++) {
    var id = Number(existing[i])
    if (id === Math.floor(id) && id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }
  ids.sort(function(left, right) { return left - right })
  return ids
}

function defaultTitle(n) {
  return "Workspace " + n
}

function titleFor(state, n) {
  var titles = isPlainObject(state) && isPlainObject(state.titles) ? state.titles : {}
  var title = titles[String(n)]
  return nonEmptyString(title) ? title : defaultTitle(n)
}

// ---- _sidebar.json

function clampWidth(w) {
  var width = Number(w)
  if (w === null || w === "" || typeof w === "boolean" || !isFinite(width)) return DEFAULT_WIDTH
  return clamp(Math.round(width), MIN_WIDTH, MAX_WIDTH)
}

function defaultSidebarState() {
  return { version: 1, monitor: "", width: DEFAULT_WIDTH, visible: true, titles: {}, dismissed: {} }
}

function cleanTitles(raw) {
  var titles = {}
  if (!isPlainObject(raw)) return titles
  var keys = Object.keys(raw)
  for (var i = 0; i < keys.length; i++) {
    if (nonEmptyString(raw[keys[i]])) titles[keys[i]] = raw[keys[i]].trim()
  }
  return titles
}

// Dismissed notice ids kept per workspace. The Claude Code hook gives every
// "Claude espera" notice a new id, so the lists are pruned on dismiss and
// capped here (the newest ids are kept).
var MAX_DISMISSED = 100
var MAX_STATE_CHARS = 256 * 1024

function cleanDismissed(raw) {
  var dismissed = {}
  if (!isPlainObject(raw)) return dismissed
  var keys = Object.keys(raw)
  for (var i = 0; i < keys.length; i++) {
    var list = Array.isArray(raw[keys[i]]) ? raw[keys[i]] : []
    var ids = []
    var seen = {}
    for (var j = list.length - 1; j >= 0 && ids.length < MAX_DISMISSED; j--) {
      if (nonEmptyString(list[j]) && !Object.prototype.hasOwnProperty.call(seen, list[j])) {
        seen[list[j]] = true
        ids.unshift(list[j])
      }
    }
    if (ids.length > 0) dismissed[keys[i]] = ids
  }
  return dismissed
}

// Works on parsed objects too, so dismiss/setTitle can copy whatever state
// they are handed without mutating it.
function sanitizeSidebarState(data) {
  var state = defaultSidebarState()
  if (!isPlainObject(data) || (data.version !== undefined && data.version !== 1)) return state
  if (typeof data.monitor === "string") state.monitor = data.monitor
  if (data.width !== undefined) state.width = clampWidth(data.width)
  if (typeof data.visible === "boolean") state.visible = data.visible
  state.titles = cleanTitles(data.titles)
  state.dismissed = cleanDismissed(data.dismissed)
  return state
}

// Tolerant by design: a broken _sidebar.json falls back to defaults and is
// rewritten on the next change.
function normalizeSidebarState(rawText) {
  var data = null
  var source = String(rawText === undefined || rawText === null ? "" : rawText)
  try {
    data = source.length > MAX_STATE_CHARS ? null : JSON.parse(source)
  } catch (e) {
    data = null
  }
  return sanitizeSidebarState(data)
}

// Every notice id in a workspace config, or null when there is no config to
// tell (missing or never loaded), so callers can skip pruning.
function noticeIds(config) {
  if (!isPlainObject(config) || !Array.isArray(config.blocks)) return null
  var ids = []
  for (var i = 0; i < config.blocks.length; i++) {
    var block = config.blocks[i]
    if (!isPlainObject(block) || block.type !== "notices" || !Array.isArray(block.items)) continue
    for (var j = 0; j < block.items.length; j++) {
      if (isPlainObject(block.items[j]) && nonEmptyString(block.items[j].id)) ids.push(block.items[j].id)
    }
  }
  return ids
}

// currentIds: the notice ids the workspace has now (noticeIds). When given,
// ids of notices that are gone are dropped: they can only come back with the
// same id through `wsbar notice add --id`, and then showing them again is right.
function dismiss(state, ws, noticeId, currentIds) {
  var next = sanitizeSidebarState(state)
  if (!nonEmptyString(noticeId)) return next
  var key = String(ws)
  var ids = next.dismissed[key] || []
  if (Array.isArray(currentIds)) {
    ids = ids.filter(function(id) { return currentIds.indexOf(id) !== -1 })
  }
  var at = ids.indexOf(noticeId)
  if (at !== -1) ids.splice(at, 1)
  ids.push(noticeId)
  next.dismissed[key] = ids.slice(-MAX_DISMISSED)
  return next
}

function setTitle(state, ws, title) {
  var next = sanitizeSidebarState(state)
  var trimmed = typeof title === "string" ? title.trim() : ""
  if (trimmed === "") delete next.titles[String(ws)]
  else next.titles[String(ws)] = trimmed
  return next
}

function serializeSidebarState(state) {
  return JSON.stringify(sanitizeSidebarState(state), null, 2) + "\n"
}

// ---- _sessions.json (Claude Code sessions linked to workspaces)

// Written only by wsbar (`wsbar connect`); the sidebar just reads it to mark
// the workspaces that have a session. Tolerant like _sidebar.json: anything
// broken reads as "no sessions", and bad entries are dropped one by one.
var MAX_SESSIONS_CHARS = 64 * 1024
var MAX_PROJECT = 1024
var SESSION_ID_RE = /^[A-Za-z0-9_-]{1,128}$/
var SINCE_RE = /^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d$/

function validSessionId(value) {
  return typeof value === "string" && SESSION_ID_RE.test(value)
}

function normalizeSessions(rawText) {
  var sessions = {}
  var source = String(rawText === undefined || rawText === null ? "" : rawText)
  if (source.length > MAX_SESSIONS_CHARS) return sessions
  var data
  try {
    data = JSON.parse(source)
  } catch (e) {
    return sessions
  }
  if (!isPlainObject(data) || data.version !== 1 || !isPlainObject(data.workspaces)) return sessions

  // A session lives in one workspace; a file that lists it twice keeps the
  // lowest-numbered one, so the indicator never shows up in two rows.
  var seen = {}
  for (var n = 1; n <= 10; n++) {
    var key = String(n)
    if (!Object.prototype.hasOwnProperty.call(data.workspaces, key)) continue
    var raw = data.workspaces[key]
    if (!isPlainObject(raw) || !validSessionId(raw.session) || seen[raw.session]) continue
    seen[raw.session] = true
    var project = typeof raw.project === "string" && raw.project.length <= MAX_PROJECT
      && (raw.project === "" || raw.project.charAt(0) === "/") ? raw.project : ""
    var since = typeof raw.since === "string" && SINCE_RE.test(raw.since) && dayNumber(raw.since) !== null
      ? raw.since : ""
    sessions[key] = { session: raw.session, project: project, since: since, active: raw.active === true }
  }
  return sessions
}

// Last path segment of a project path ("" when there is none), capped for a
// tooltip line.
function projectName(path) {
  if (typeof path !== "string") return ""
  var parts = path.split("/").filter(function(part) { return part !== "" })
  return parts.length > 0 ? cap(parts[parts.length - 1], 80) : ""
}

// "Claude conectado · <project> · desde HH:MM" for an active link (the date
// joins the time when the link is from another day), "Sesión terminada ·
// <project>" for an ended one. Empty parts are left out.
function sessionTooltip(link, today) {
  if (!isPlainObject(link)) return ""
  var parts = [link.active === true ? "Claude conectado" : "Sesión terminada"]
  var name = projectName(link.project)
  if (name !== "") parts.push(name)
  if (link.active === true && typeof link.since === "string" && SINCE_RE.test(link.since)) {
    var day = link.since.slice(0, 10)
    var time = link.since.slice(11, 16)
    parts.push("desde " + (day === today ? time : day.slice(8, 10) + "/" + day.slice(5, 7) + " " + time))
  }
  return parts.join(" · ")
}

// ---- text blocks

function escapeHtml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function inlineMarkdown(text) {
  return text
    .replace(/\[([^\]\n]+)\]\((https:\/\/[^)\s]+)\)/g, '<a href="$2">$1</a>')
    .replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
    .replace(/(^|[^\w*])\*([^*\n]+)\*(?![\w*])/g, "$1<i>$2</i>")
    .replace(/(^|[^\w])_([^_\n]+)_(?!\w)/g, "$1<i>$2</i>")
}

// Renders the small Markdown subset of text blocks (bold, italic, `code`,
// https links) as Qt StyledText. Everything is HTML-escaped first, so the only
// tags in the result are the ones built here: no images, no raw HTML, no
// links other than https. Text blocks never go through Text.MarkdownText,
// which fetches images, including from local devices.
function markdownToStyled(text) {
  var source = typeof text === "string" ? cap(text, MAX_TEXT) : ""
  var parts = escapeHtml(source).split("`")
  var out = ""
  for (var i = 0; i < parts.length; i++) {
    // Odd parts sit between backticks; an unpaired trailing one stays literal.
    if (i % 2 === 1 && i < parts.length - 1) out += "<tt>" + parts[i] + "</tt>"
    else out += (i % 2 === 1 ? "`" : "") + inlineMarkdown(parts[i])
  }
  return out.replace(/\n/g, "<br>")
}

function isSafeLink(url) {
  return typeof url === "string" && /^https:\/\/[^\s]+$/i.test(url)
}

