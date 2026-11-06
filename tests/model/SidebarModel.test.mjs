import { test, describe } from "node:test"
import assert from "node:assert/strict"
import { fileURLToPath } from "node:url"
import { loadModel } from "./loadModel.mjs"

const M = loadModel(fileURLToPath(new URL("../../SidebarModel.js", import.meta.url)))

const SPEC_EXAMPLE = {
  version: 1,
  project: "/home/matis/Work/ejemplo",
  progress: { label: "Release 1.2 — pagos", percent: 62, start: "2026-10-20", deadline: "2026-11-18" },
  scroll: "top",
  blocks: [
    { id: "avisos", type: "notices", items: [
      { id: "n1", level: "warn", text: "Tests de checkout fallan en CI", at: "2026-11-06T10:12" }
    ] },
    { id: "foco", type: "focus", now: "Webhook de pagos", next: ["Reintentos", "Emails de recibo"] },
    { id: "hitos", type: "milestones", items: [
      { label: "Modelo de datos", status: "done" },
      { label: "Checkout", status: "current", date: "2026-11-12" },
      { label: "Facturación", status: "pending" }
    ] },
    { id: "nota", type: "text", text: "Esperando credenciales de **producción**." },
    { id: "sub", type: "progress", label: "Cobertura de tests", percent: 40 }
  ]
}

function normalized(obj) {
  const result = M.normalizeWorkspaceConfig(JSON.stringify(obj))
  assert.equal(result.ok, true, result.error)
  return result.config
}

describe("normalizeWorkspaceConfig", () => {
  test("accepts the spec example unchanged", () => {
    const result = M.normalizeWorkspaceConfig(JSON.stringify(SPEC_EXAMPLE))
    assert.equal(result.ok, true)
    assert.equal(result.error, "")
    assert.deepEqual(result.config, SPEC_EXAMPLE)
  })

  test("invalid JSON fails with a message", () => {
    for (const raw of ["{", "", "not json", undefined, null]) {
      const result = M.normalizeWorkspaceConfig(raw)
      assert.equal(result.ok, false)
      assert.equal(result.config, null)
      assert.ok(result.error.length > 0)
    }
  })

  test("non-object JSON fails", () => {
    for (const raw of ["[]", "1", "\"x\"", "null"]) {
      assert.equal(M.normalizeWorkspaceConfig(raw).ok, false)
    }
  })

  test("version must be exactly 1", () => {
    for (const version of [undefined, 2, "1", 0, null]) {
      const result = M.normalizeWorkspaceConfig(JSON.stringify({ version, blocks: [] }))
      assert.equal(result.ok, false, "version " + version)
      assert.match(result.error, /ersión/)
    }
  })

  test("minimal file gets defaults", () => {
    assert.deepEqual(normalized({ version: 1 }), {
      version: 1, project: "", progress: null, scroll: "top", blocks: []
    })
  })

  test("unknown and malformed blocks are dropped, order kept", () => {
    const config = normalized({ version: 1, blocks: [
      { id: "a", type: "text", text: "uno" },
      { id: "x", type: "chart", data: [1, 2] },
      "string block",
      null,
      { id: "y" },
      { id: "b", type: "text", text: "dos" }
    ] })
    assert.deepEqual(config.blocks.map(b => b.id), ["a", "b"])
  })

  test("blocks without id get b<index> (index in the file)", () => {
    const config = normalized({ version: 1, blocks: [
      { type: "chart" },
      { type: "text", text: "sin id" },
      { id: "", type: "text" },
      { id: 7, type: "text" }
    ] })
    assert.deepEqual(config.blocks.map(b => b.id), ["b1", "b2", "b3"])
  })

  test("duplicate block ids are made unique", () => {
    const config = normalized({ version: 1, blocks: [
      { id: "a", type: "text" },
      { id: "a", type: "text" },
      { id: "b1", type: "text" },
      { id: "b1", type: "text" }
    ] })
    assert.deepEqual(config.blocks.map(b => b.id), ["a", "b1", "b2", "b3"])
  })

  test("fallback ids never collide with explicit ones", () => {
    const config = normalized({ version: 1, blocks: [
      { id: "b1", type: "text" },
      { type: "text" }
    ] })
    assert.deepEqual(config.blocks.map(b => b.id), ["b1", "b1_"])
  })

  test("invalid optional top-level fields are dropped, not fatal", () => {
    const config = normalized({ version: 1, project: 42, progress: "60%", scroll: 7, blocks: "nope" })
    assert.deepEqual(config, { version: 1, project: "", progress: null, scroll: "top", blocks: [] })
  })

  test("progress: percent clamped, bad dates dropped", () => {
    assert.deepEqual(normalized({ version: 1, progress: { percent: 140, start: "2026-02-30", deadline: "18/11/2026" } }).progress,
      { label: "", percent: 100 })
    assert.deepEqual(normalized({ version: 1, progress: { label: "x", percent: -5, deadline: "2026-11-18" } }).progress,
      { label: "x", percent: 0, deadline: "2026-11-18" })
    assert.deepEqual(normalized({ version: 1, progress: { percent: "62" } }).progress, { label: "", percent: 0 })
    assert.deepEqual(normalized({ version: 1, progress: { start: "2026-10-20T08:00" } }).progress, { label: "", percent: 0 })
  })

  test("scroll variants", () => {
    assert.equal(normalized({ version: 1, scroll: "bottom" }).scroll, "bottom")
    assert.equal(normalized({ version: 1, scroll: "hitos" }).scroll, "hitos")
    assert.equal(normalized({ version: 1, scroll: 0.4 }).scroll, 0.4)
    assert.equal(normalized({ version: 1, scroll: 0 }).scroll, 0)
    assert.equal(normalized({ version: 1, scroll: 1 }).scroll, 1)
    assert.equal(normalized({ version: 1, scroll: 1.5 }).scroll, "top")
    assert.equal(normalized({ version: 1, scroll: -0.1 }).scroll, "top")
    assert.equal(normalized({ version: 1, scroll: "" }).scroll, "top")
    assert.equal(normalized({ version: 1, scroll: null }).scroll, "top")
  })

  test("notices: bad items dropped, level defaulted, missing id derived", () => {
    const config = normalized({ version: 1, blocks: [{ id: "av", type: "notices", items: [
      { id: "n1", level: "fatal", text: "nivel raro" },
      { level: "error", text: "sin id" },
      { id: "n3", text: "" },
      "texto suelto",
      { id: "n5", level: "info", text: "ok", at: 12 }
    ] }] })
    assert.deepEqual(config.blocks[0].items, [
      { id: "n1", level: "info", text: "nivel raro" },
      { id: "av-n1", level: "error", text: "sin id" },
      { id: "n5", level: "info", text: "ok" }
    ])
  })

  test("notices without items array get an empty list", () => {
    assert.deepEqual(normalized({ version: 1, blocks: [{ id: "av", type: "notices" }] }).blocks[0],
      { id: "av", type: "notices", items: [] })
  })

  test("focus: now defaulted, next filtered to strings", () => {
    assert.deepEqual(normalized({ version: 1, blocks: [{ id: "f", type: "focus", now: 3, next: ["a", 2, "", "b"] }] }).blocks[0],
      { id: "f", type: "focus", now: "", next: ["a", "b"] })
    assert.deepEqual(normalized({ version: 1, blocks: [{ id: "f", type: "focus", next: "a" }] }).blocks[0],
      { id: "f", type: "focus", now: "", next: [] })
  })

  test("milestones: status defaulted, unlabeled dropped, bad date dropped", () => {
    assert.deepEqual(normalized({ version: 1, blocks: [{ id: "h", type: "milestones", items: [
      { label: "A", status: "doing", date: "mañana" },
      { status: "done" },
      { label: "B", status: "done", date: "2026-11-12" }
    ] }] }).blocks[0].items, [
      { label: "A", status: "pending" },
      { label: "B", status: "done", date: "2026-11-12" }
    ])
  })

  test("text and progress blocks", () => {
    const config = normalized({ version: 1, blocks: [
      { id: "t", type: "text" },
      { id: "p", type: "progress", label: 5, percent: 250 },
      { id: "q", type: "progress", percent: "40" }
    ] })
    assert.deepEqual(config.blocks, [
      { id: "t", type: "text", text: "" },
      { id: "p", type: "progress", label: "", percent: 100 },
      { id: "q", type: "progress", label: "", percent: 0 }
    ])
  })

  test("unknown extra fields are not carried over", () => {
    const config = normalized({ version: 1, extra: true, blocks: [{ id: "t", type: "text", text: "x", color: "red" }] })
    assert.equal("extra" in config, false)
    assert.deepEqual(config.blocks[0], { id: "t", type: "text", text: "x" })
  })
})

describe("paceInfo", () => {
  const base = { label: "Release", percent: 62, start: "2026-10-20", deadline: "2026-11-18" }

  test("spec example on 2026-11-06", () => {
    const info = M.paceInfo(base, "2026-11-06")
    // 17 of 29 days elapsed
    assert.ok(Math.abs(info.expected - (17 / 29) * 100) < 1e-9)
    assert.equal(info.percent, 62)
    assert.equal(info.behind, false)
    assert.equal(info.daysLeft, 12)
    assert.equal(info.daysLabel, "12d")
    assert.equal(info.tooltip, "Release\nFecha límite: 2026-11-18\nAdelantado 3 %")
  })

  test("behind schedule", () => {
    const info = M.paceInfo({ ...base, percent: 30 }, "2026-11-06")
    assert.equal(info.behind, true)
    assert.match(info.tooltip, /Atrasado 29 %$/)
  })

  test("slightly behind never reads as 0 %", () => {
    // expected = 50 exactly on day 10 of 20
    const info = M.paceInfo({ percent: 49.8, start: "2026-11-01", deadline: "2026-11-21" }, "2026-11-11")
    assert.equal(info.expected, 50)
    assert.equal(info.behind, true)
    assert.match(info.tooltip, /Atrasado 1 %$/)
  })

  test("exactly on pace", () => {
    const info = M.paceInfo({ percent: 50, start: "2026-11-01", deadline: "2026-11-21" }, "2026-11-11")
    assert.equal(info.behind, false)
    assert.match(info.tooltip, /En ritmo$/)
  })

  test("deadline today", () => {
    const info = M.paceInfo(base, "2026-11-18")
    assert.equal(info.daysLeft, 0)
    assert.equal(info.daysLabel, "hoy")
    assert.equal(info.expected, 100)
    assert.equal(info.behind, true)
  })

  test("deadline passed", () => {
    const info = M.paceInfo(base, "2026-11-21")
    assert.equal(info.daysLeft, -3)
    assert.equal(info.daysLabel, "-3d")
    assert.equal(info.expected, 100)
    assert.equal(info.behind, true)
  })

  test("done project past deadline is not behind", () => {
    const info = M.paceInfo({ ...base, percent: 100 }, "2026-12-01")
    assert.equal(info.behind, false)
  })

  test("before start, expected is 0", () => {
    const info = M.paceInfo({ ...base, percent: 0 }, "2026-10-01")
    assert.equal(info.expected, 0)
    assert.equal(info.behind, false)
    assert.equal(info.daysLeft, 48)
  })

  test("deadline == start", () => {
    const p = { percent: 40, start: "2026-11-06", deadline: "2026-11-06" }
    assert.equal(M.paceInfo(p, "2026-11-05").expected, 0)
    assert.equal(M.paceInfo(p, "2026-11-06").expected, 100)
    assert.equal(M.paceInfo(p, "2026-11-06").behind, true)
    assert.equal(M.paceInfo(p, "2026-11-06").daysLabel, "hoy")
  })

  test("deadline before start does not divide by zero or go negative", () => {
    const info = M.paceInfo({ percent: 10, start: "2026-11-10", deadline: "2026-11-01" }, "2026-11-12")
    assert.equal(info.expected, 100)
    assert.ok(Number.isFinite(info.expected))
  })

  test("missing start: no expected mark, days still shown", () => {
    const info = M.paceInfo({ percent: 20, deadline: "2026-11-18" }, "2026-11-06")
    assert.equal(info.expected, null)
    assert.equal(info.behind, false)
    assert.equal(info.daysLabel, "12d")
    assert.equal(info.tooltip, "Fecha límite: 2026-11-18")
  })

  test("missing deadline: no expected, no days", () => {
    const info = M.paceInfo({ label: "L", percent: 20, start: "2026-11-01" }, "2026-11-06")
    assert.equal(info.expected, null)
    assert.equal(info.daysLeft, null)
    assert.equal(info.daysLabel, "")
    assert.equal(info.tooltip, "L")
  })

  test("no progress at all", () => {
    for (const p of [null, undefined, "x", []]) {
      assert.deepEqual(M.paceInfo(p, "2026-11-06"),
        { percent: 0, expected: null, behind: false, daysLeft: null, daysLabel: "", tooltip: "" })
    }
  })

  test("percent is clamped and defaulted", () => {
    assert.equal(M.paceInfo({ percent: 180 }, "2026-11-06").percent, 100)
    assert.equal(M.paceInfo({ percent: -3 }, "2026-11-06").percent, 0)
    assert.equal(M.paceInfo({ percent: "50" }, "2026-11-06").percent, 0)
  })

  test("invalid today yields no date math", () => {
    const info = M.paceInfo(base, "")
    assert.equal(info.expected, null)
    assert.equal(info.daysLeft, null)
    assert.equal(info.daysLabel, "")
  })

  test("today with a time part is accepted", () => {
    assert.equal(M.paceInfo(base, "2026-11-06T23:59:00").daysLeft, 12)
  })

  test("crosses DST and month boundaries by whole days", () => {
    assert.equal(M.paceInfo({ percent: 0, deadline: "2027-04-01" }, "2027-03-01").daysLeft, 31)
    assert.equal(M.paceInfo({ percent: 0, deadline: "2027-01-01" }, "2026-12-31").daysLeft, 1)
  })
})

describe("pendingNotices / pendingCount", () => {
  const config = normalized({ version: 1, blocks: [
    { id: "a", type: "notices", items: [{ id: "n1", text: "uno" }, { id: "n2", text: "dos" }] },
    { id: "t", type: "text", text: "x" },
    { id: "b", type: "notices", items: [{ id: "n3", level: "error", text: "tres" }] }
  ] })

  test("collects notices from every notices block in order", () => {
    assert.deepEqual(M.pendingNotices(config, []).map(n => n.id), ["n1", "n2", "n3"])
    assert.equal(M.pendingCount(config, []), 3)
  })

  test("dismissed ids are excluded", () => {
    assert.deepEqual(M.pendingNotices(config, ["n2", "zz"]).map(n => n.id), ["n1", "n3"])
    assert.equal(M.pendingCount(config, ["n1", "n2", "n3"]), 0)
  })

  test("tolerates missing config or dismissed list", () => {
    assert.equal(M.pendingCount(config, undefined), 3)
    assert.equal(M.pendingCount(config, null), 3)
    assert.deepEqual(M.pendingNotices(null, []), [])
    assert.equal(M.pendingCount(undefined, undefined), 0)
    assert.equal(M.pendingCount({ blocks: [{ type: "notices" }] }, []), 0)
  })

  test("returns the notice items themselves", () => {
    assert.deepEqual(M.pendingNotices(config, ["n1", "n2"]), [{ id: "n3", level: "error", text: "tres" }])
  })
})

describe("resolveScroll", () => {
  const offsets = { foco: 120, hitos: 900, neg: -20, bad: "x" }

  test("top and bottom", () => {
    assert.equal(M.resolveScroll("top", offsets, 1000, 400), 0)
    assert.equal(M.resolveScroll("bottom", offsets, 1000, 400), 600)
  })

  test("fraction of the scrollable range", () => {
    assert.equal(M.resolveScroll(0.5, offsets, 1000, 400), 300)
    assert.equal(M.resolveScroll(0, offsets, 1000, 400), 0)
    assert.equal(M.resolveScroll(1, offsets, 1000, 400), 600)
    assert.equal(M.resolveScroll(3, offsets, 1000, 400), 600)
    assert.equal(M.resolveScroll(-1, offsets, 1000, 400), 0)
  })

  test("block id resolves to its offset, clamped", () => {
    assert.equal(M.resolveScroll("foco", offsets, 1000, 400), 120)
    assert.equal(M.resolveScroll("hitos", offsets, 1000, 400), 600)
    assert.equal(M.resolveScroll("neg", offsets, 1000, 400), 0)
  })

  test("unknown or invalid targets go to 0", () => {
    assert.equal(M.resolveScroll("nope", offsets, 1000, 400), 0)
    assert.equal(M.resolveScroll("bad", offsets, 1000, 400), 0)
    assert.equal(M.resolveScroll("toString", offsets, 1000, 400), 0)
    assert.equal(M.resolveScroll("foco", null, 1000, 400), 0)
    assert.equal(M.resolveScroll(undefined, offsets, 1000, 400), 0)
    assert.equal(M.resolveScroll(NaN, offsets, 1000, 400), 0)
  })

  test("content shorter than the view never scrolls", () => {
    assert.equal(M.resolveScroll("bottom", offsets, 300, 400), 0)
    assert.equal(M.resolveScroll(0.5, offsets, 300, 400), 0)
    assert.equal(M.resolveScroll("foco", offsets, 300, 400), 0)
  })

  test("bad heights are treated as 0", () => {
    assert.equal(M.resolveScroll("bottom", offsets, NaN, 400), 0)
    assert.equal(M.resolveScroll("bottom", offsets, 500, undefined), 500)
  })
})

describe("workspaceIds", () => {
  test("always 1..5", () => {
    assert.deepEqual(M.workspaceIds([]), [1, 2, 3, 4, 5])
    assert.deepEqual(M.workspaceIds(undefined), [1, 2, 3, 4, 5])
  })

  test("adds existing ids up to 10, sorted, no duplicates", () => {
    assert.deepEqual(M.workspaceIds([9, 2, 7, 7, 10]), [1, 2, 3, 4, 5, 7, 9, 10])
  })

  test("ignores special, out of range and non-integer ids", () => {
    assert.deepEqual(M.workspaceIds([-98, 0, 11, 6.5, "x", null, 8]), [1, 2, 3, 4, 5, 8])
  })
})

describe("titles", () => {
  test("defaultTitle", () => {
    assert.equal(M.defaultTitle(3), "Workspace 3")
  })

  test("titleFor uses override or default", () => {
    const state = M.normalizeSidebarState(JSON.stringify({ version: 1, titles: { 3: "Cliente X — API" } }))
    assert.equal(M.titleFor(state, 3), "Cliente X — API")
    assert.equal(M.titleFor(state, "3"), "Cliente X — API")
    assert.equal(M.titleFor(state, 4), "Workspace 4")
    assert.equal(M.titleFor(null, 2), "Workspace 2")
    assert.equal(M.titleFor({ titles: { 1: "  " } }, 1), "Workspace 1")
  })

  test("setTitle trims, stores and does not mutate", () => {
    const state = M.normalizeSidebarState("")
    const next = M.setTitle(state, 3, "  Cliente X  ")
    assert.equal(next.titles["3"], "Cliente X")
    assert.deepEqual(state.titles, {})
    assert.notEqual(next, state)
  })

  test("setTitle with empty title removes the override", () => {
    const state = M.setTitle(M.normalizeSidebarState(""), 3, "Cliente X")
    for (const empty of ["", "   ", null, undefined]) {
      const cleared = M.setTitle(state, 3, empty)
      assert.equal("3" in cleared.titles, false)
      assert.equal(M.titleFor(cleared, 3), "Workspace 3")
    }
    assert.equal(state.titles["3"], "Cliente X")
  })
})

describe("sidebar state", () => {
  const DEFAULTS = { version: 1, monitor: "", width: 260, visible: true, titles: {}, dismissed: {} }

  test("spec example parses as-is", () => {
    const raw = { version: 1, monitor: "DP-1", width: 260, visible: true,
      titles: { 3: "Cliente X — API" }, dismissed: { 3: ["n1"] } }
    assert.deepEqual(M.normalizeSidebarState(JSON.stringify(raw)), {
      version: 1, monitor: "DP-1", width: 260, visible: true,
      titles: { "3": "Cliente X — API" }, dismissed: { "3": ["n1"] }
    })
  })

  test("invalid input falls back to defaults", () => {
    for (const raw of ["", "{", "null", "[]", "5", undefined, null, JSON.stringify({ version: 2, width: 400 })]) {
      assert.deepEqual(M.normalizeSidebarState(raw), DEFAULTS, String(raw))
    }
  })

  test("invalid fields fall back individually", () => {
    assert.deepEqual(M.normalizeSidebarState(JSON.stringify({
      monitor: 3, width: "wide", visible: "no", titles: [], dismissed: { 1: "n1", 2: ["a", 3, "a", "b"], 4: [] }
    })), { ...DEFAULTS, dismissed: { "2": ["a", "b"] } })
    assert.deepEqual(M.normalizeSidebarState(JSON.stringify({ visible: false, width: 1000, titles: { 2: "", 5: 9 } })),
      { ...DEFAULTS, visible: false, width: 600 })
  })

  test("clampWidth", () => {
    assert.equal(M.clampWidth(100), 180)
    assert.equal(M.clampWidth(180), 180)
    assert.equal(M.clampWidth(333.6), 334)
    assert.equal(M.clampWidth(600), 600)
    assert.equal(M.clampWidth(9999), 600)
    assert.equal(M.clampWidth(-5), 180)
    assert.equal(M.clampWidth("300"), 300)
    for (const bad of [NaN, Infinity, undefined, null, "", "x", true]) {
      const w = M.clampWidth(bad)
      assert.ok(Number.isInteger(w) && w >= 180 && w <= 600, String(bad))
    }
  })

  test("dismiss appends once and never mutates the input", () => {
    const state = M.normalizeSidebarState(JSON.stringify({ version: 1, dismissed: { 3: ["n1"] } }))
    const snapshot = JSON.stringify(state)
    const next = M.dismiss(state, 3, "n2")
    assert.deepEqual(next.dismissed, { "3": ["n1", "n2"] })
    assert.equal(JSON.stringify(state), snapshot)
    assert.notEqual(next, state)
    assert.notEqual(next.dismissed, state.dismissed)
    assert.notEqual(next.dismissed["3"], state.dismissed["3"])

    const again = M.dismiss(next, "3", "n2")
    assert.deepEqual(again.dismissed, { "3": ["n1", "n2"] })

    const other = M.dismiss(next, 5, "x")
    assert.deepEqual(other.dismissed, { "3": ["n1", "n2"], "5": ["x"] })
    assert.deepEqual(next.dismissed, { "3": ["n1", "n2"] })
  })

  test("dismiss keeps the rest of the state and ignores empty ids", () => {
    const state = M.setTitle(M.normalizeSidebarState(JSON.stringify({ monitor: "HDMI-A-1", width: 300, visible: false })), 2, "T")
    const next = M.dismiss(state, 2, "n1")
    assert.equal(next.monitor, "HDMI-A-1")
    assert.equal(next.width, 300)
    assert.equal(next.visible, false)
    assert.deepEqual(next.titles, { "2": "T" })
    assert.deepEqual(M.dismiss(state, 2, "").dismissed, {})
  })

  test("dismiss from defaults when handed garbage", () => {
    assert.deepEqual(M.dismiss(null, 1, "n1"), { ...DEFAULTS, dismissed: { "1": ["n1"] } })
  })

  test("dismissed notices drop out of the pending count", () => {
    const config = normalized(SPEC_EXAMPLE)
    let state = M.normalizeSidebarState("")
    assert.equal(M.pendingCount(config, state.dismissed["3"]), 1)
    state = M.dismiss(state, 3, "n1")
    assert.equal(M.pendingCount(config, state.dismissed["3"]), 0)
  })

  test("serialize is 2-space pretty JSON that round-trips", () => {
    const state = M.dismiss(M.setTitle(M.normalizeSidebarState(JSON.stringify({ monitor: "DP-1", width: 420 })), 3, "API"), 3, "n1")
    const text = M.serializeSidebarState(state)
    assert.equal(text, JSON.stringify(state, null, 2) + "\n")
    assert.match(text, /^\{\n  "version": 1,\n  "monitor": "DP-1",/)
    assert.deepEqual(M.normalizeSidebarState(text), state)
  })

  test("serialize sanitizes what it is given", () => {
    assert.deepEqual(JSON.parse(M.serializeSidebarState({ width: 50, extra: 1 })), { ...DEFAULTS, width: 180 })
  })
})
