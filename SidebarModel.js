.pragma library

// Pure logic for the workspace sidebar: workspaceN.json normalization, pace
// math for the progress strip, pending notices, scroll resolution and the
// _sidebar.json UI state. Qt-free so it runs under `node --test`
// (tests/model/). Dates are ISO strings; "today" is always passed in.

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
  var progress = { label: stringOr(raw.label, ""), percent: percentOr(raw.percent, 0) }
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
  var items = Array.isArray(raw.items) ? raw.items : []
  block.items = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!isPlainObject(item) || !nonEmptyString(item.text)) continue
    var notice = {
      id: nonEmptyString(item.id) ? item.id : block.id + "-n" + i,
      level: NOTICE_LEVELS.indexOf(item.level) !== -1 ? item.level : "info",
      text: item.text
    }
    if (nonEmptyString(item.at)) notice.at = item.at
    block.items.push(notice)
  }
}

function normalizeFocus(raw, block) {
  block.now = stringOr(raw.now, "")
  block.next = []
  var next = Array.isArray(raw.next) ? raw.next : []
  for (var i = 0; i < next.length; i++) {
    if (nonEmptyString(next[i])) block.next.push(next[i])
  }
}

function normalizeMilestones(raw, block) {
  var items = Array.isArray(raw.items) ? raw.items : []
  block.items = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!isPlainObject(item) || !nonEmptyString(item.label)) continue
    var milestone = {
      label: item.label,
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
  var id = nonEmptyString(raw.id) && !usedIds[raw.id] ? raw.id : "b" + index
  while (usedIds[id]) id = id + "_"
  usedIds[id] = true

  var block = { id: id, type: raw.type }
  if (raw.type === "notices") normalizeNotices(raw, block)
  else if (raw.type === "focus") normalizeFocus(raw, block)
  else if (raw.type === "milestones") normalizeMilestones(raw, block)
  else if (raw.type === "text") block.text = stringOr(raw.text, "")
  else if (raw.type === "progress") {
    block.label = stringOr(raw.label, "")
    block.percent = percentOr(raw.percent, 0)
  }
  return block
}

// Only bad JSON, a non-object or a version other than 1 fail; everything else
// degrades field by field, since the sidebar keeps the last valid config on
// failure and a single bad block should not freeze it.
function normalizeWorkspaceConfig(rawText) {
  var data
  try {
    data = JSON.parse(String(rawText === undefined || rawText === null ? "" : rawText))
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
  var rawBlocks = Array.isArray(data.blocks) ? data.blocks : []
  for (var i = 0; i < rawBlocks.length; i++) {
    var block = normalizeBlock(rawBlocks[i], i, usedIds)
    if (block) blocks.push(block)
  }

  return {
    ok: true,
    config: {
      version: 1,
      project: stringOr(data.project, ""),
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

function cleanDismissed(raw) {
  var dismissed = {}
  if (!isPlainObject(raw)) return dismissed
  var keys = Object.keys(raw)
  for (var i = 0; i < keys.length; i++) {
    var list = Array.isArray(raw[keys[i]]) ? raw[keys[i]] : []
    var ids = []
    for (var j = 0; j < list.length; j++) {
      if (nonEmptyString(list[j]) && ids.indexOf(list[j]) === -1) ids.push(list[j])
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
  try {
    data = JSON.parse(String(rawText === undefined || rawText === null ? "" : rawText))
  } catch (e) {
    data = null
  }
  return sanitizeSidebarState(data)
}

function dismiss(state, ws, noticeId) {
  var next = sanitizeSidebarState(state)
  if (!nonEmptyString(noticeId)) return next
  var key = String(ws)
  var ids = next.dismissed[key] || []
  if (ids.indexOf(noticeId) === -1) ids.push(noticeId)
  next.dismissed[key] = ids
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
