"""Tests for bin/wsbar, run as a subprocess against temp dirs and a fake hyprctl.

python3 -m unittest discover -s tests/wsbar -v
"""

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WSBAR = os.path.join(ROOT, "bin", "wsbar")

FAKE_HYPRCTL = """#!/bin/sh
[ "$1 $2" = "clients -j" ] || exit 1
cat "$WSBAR_FAKE_CLIENTS"
"""

GOOD_DOC = {
  "version": 1,
  "project": "/home/x/proj",
  "custom": {"keep": True},
  "progress": {"label": "Release", "percent": 62, "start": "2026-10-20", "deadline": "2026-11-18"},
  "scroll": "top",
  "blocks": [
    {"id": "avisos", "type": "notices", "items": [
      {"id": "n1", "level": "warn", "text": "CI rota", "at": "2026-11-06T10:12"}]},
    {"id": "foco", "type": "focus", "now": "Webhook", "next": ["Reintentos"]},
    {"id": "hitos", "type": "milestones", "items": [
      {"label": "Modelo", "status": "done"},
      {"label": "Checkout", "status": "current", "date": "2026-11-12"},
      {"label": "Facturación", "status": "pending"}]},
    {"id": "nota", "type": "text", "text": "Esperando **prod**."},
    {"id": "sub", "type": "progress", "label": "Cobertura", "percent": 40},
    {"id": "futuro", "type": "chart", "whatever": [1, 2]},
  ],
}


class WsbarTestCase(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.mkdtemp(prefix="wsbar-test-")
    self.config = os.path.join(self.tmp, "config", "sidebar")
    self.data = os.path.join(self.tmp, "data")
    self.state = os.path.join(self.tmp, "state")
    self.clients = os.path.join(self.tmp, "clients.json")
    self.hyprctl = os.path.join(self.tmp, "hyprctl")
    with open(self.hyprctl, "w") as f:
      f.write(FAKE_HYPRCTL)
    os.chmod(self.hyprctl, 0o755)
    self.set_clients([])
    self.repo = os.path.join(self.tmp, "repo")
    os.makedirs(os.path.join(self.repo, "sub"))
    subprocess.run(["git", "init", "-q", self.repo], check=True)

  def tearDown(self):
    shutil.rmtree(self.tmp, ignore_errors=True)

  def set_clients(self, clients):
    with open(self.clients, "w") as f:
      json.dump(clients, f)

  def env(self, **extra):
    # The suite runs inside Claude Code too: without dropping CLAUDE_CODE_SESSION_ID
    # every write would be gated by the session links (tests opt in explicitly).
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("WSBAR_") and k != "CLAUDE_CODE_SESSION_ID"}
    env.update({
      "WSBAR_CONFIG_DIR": self.config,
      "WSBAR_DATA_DIR": self.data,
      "WSBAR_STATE_DIR": self.state,
      "WSBAR_HYPRCTL": self.hyprctl,
      "WSBAR_FAKE_CLIENTS": self.clients,
    })
    env.update(extra)
    return env

  def run_wsbar(self, *args, cwd=None, **env):
    return subprocess.run([sys.executable, WSBAR, *args], capture_output=True, text=True,
                          env=self.env(**env), cwd=cwd or self.tmp)

  def ok(self, *args, **kw):
    r = self.run_wsbar(*args, **kw)
    self.assertEqual(r.returncode, 0, "wsbar %s failed: %s" % (" ".join(args), r.stderr))
    return r.stdout

  def fails(self, code, *args, **kw):
    r = self.run_wsbar(*args, **kw)
    self.assertEqual(r.returncode, code, "wsbar %s: expected %d, got %d (%s)" % (" ".join(args), code, r.returncode, r.stderr))
    self.assertTrue(r.stderr.strip(), "expected an error message")
    return r.stderr

  def ws_file(self, ws=3):
    return os.path.join(self.config, "workspace%d.json" % ws)

  def write_doc(self, doc, ws=3):
    os.makedirs(self.config, exist_ok=True)
    with open(self.ws_file(ws), "w") as f:
      json.dump(doc, f)

  def read_doc(self, ws=3):
    with open(self.ws_file(ws)) as f:
      return json.load(f)

  def raw(self, ws=3):
    with open(self.ws_file(ws), "rb") as f:
      return f.read()

  def block(self, doc, block_id):
    return next((b for b in doc["blocks"] if b["id"] == block_id), None)

  def ids(self, doc):
    return [b["id"] for b in doc["blocks"]]

  def assert_valid_file(self, ws=3):
    self.ok("validate", self.ws_file(ws))


class TestWorkspaceTarget(WsbarTestCase):
  def test_ws_flag_beats_env(self):
    self.assertEqual(self.ok("--ws", "4", "where", WSBAR_WS="7").strip(), "4")

  def test_ws_flag_after_subcommand(self):
    self.assertEqual(self.ok("where", "--ws", "5", WSBAR_WS="7").strip(), "5")

  def test_env_beats_autodetect(self):
    self.set_clients([{"pid": os.getpid(), "workspace": {"id": 2, "name": "2"}}])
    self.assertEqual(self.ok("where", WSBAR_WS="7").strip(), "7")

  def test_autodetect_from_ancestor(self):
    # The test process is an ancestor of the wsbar subprocess, like a terminal is of its shell.
    self.set_clients([
      {"pid": 999999999, "workspace": {"id": 9, "name": "9"}},
      {"pid": os.getpid(), "workspace": {"id": 6, "name": "6"}},
    ])
    self.assertEqual(self.ok("where").strip(), "6")

  def test_autodetect_used_by_writes(self):
    self.set_clients([{"pid": os.getpid(), "workspace": {"id": 8, "name": "8"}}])
    self.ok("text", "nota", "hola")
    self.assertEqual(self.block(self.read_doc(8), "nota")["text"], "hola")

  def test_autodetect_one_pid_on_several_workspaces(self):
    # A single-instance terminal owns windows on several workspaces with one pid.
    self.set_clients([
      {"pid": os.getpid(), "workspace": {"id": 1, "name": "1"}},
      {"pid": os.getpid(), "workspace": {"id": 2, "name": "2"}},
    ])
    err = self.fails(1, "where")
    self.assertIn("--ws", err)
    self.fails(1, "text", "nota", "x")
    self.assertFalse(os.path.exists(self.ws_file(1)))
    self.assertFalse(os.path.exists(self.ws_file(2)))

  def test_autodetect_several_windows_same_workspace(self):
    self.set_clients([
      {"pid": os.getpid(), "workspace": {"id": 4, "name": "4"}},
      {"pid": os.getpid(), "workspace": {"id": 4, "name": "4"}},
    ])
    self.assertEqual(self.ok("where").strip(), "4")

  def test_autodetect_no_match(self):
    self.set_clients([{"pid": 999999999, "workspace": {"id": 2, "name": "2"}}])
    self.assertIn("--ws", self.fails(1, "where"))

  def test_autodetect_special_workspace(self):
    self.set_clients([{"pid": os.getpid(), "workspace": {"id": -98, "name": "special:scratchpad"}}])
    self.assertIn("--ws", self.fails(1, "where"))

  def test_autodetect_hyprctl_missing(self):
    self.assertIn("--ws", self.fails(1, "where", WSBAR_HYPRCTL=os.path.join(self.tmp, "nope")))

  def test_autodetect_hyprctl_garbage(self):
    with open(self.clients, "w") as f:
      f.write("not json")
    self.fails(1, "where")

  def test_out_of_range(self):
    self.fails(2, "--ws", "11", "where")
    self.fails(2, "--ws", "0", "where")
    self.fails(2, "--ws", "x", "where")
    self.fails(2, "where", WSBAR_WS="-1")


class TestValidation(WsbarTestCase):
  def validate_doc(self, doc):
    path = os.path.join(self.tmp, "doc.json")
    with open(path, "w") as f:
      json.dump(doc, f)
    return self.run_wsbar("validate", path)

  def test_good_doc_is_valid(self):
    r = self.validate_doc(GOOD_DOC)
    self.assertEqual(r.returncode, 0, r.stderr)

  def test_minimal_doc_is_valid(self):
    self.assertEqual(self.validate_doc({"version": 1}).returncode, 0)

  def test_bad_docs(self):
    def with_block(block):
      return {"version": 1, "blocks": [block]}
    bad = [
      [],
      {"blocks": []},
      {"version": 2, "blocks": []},
      {"version": 1, "project": 3},
      {"version": 1, "progress": {"label": "x"}},
      {"version": 1, "progress": {"percent": 101}},
      {"version": 1, "progress": {"percent": True}},
      {"version": 1, "progress": {"percent": 5, "deadline": "18/11/2026"}},
      {"version": 1, "progress": {"percent": 5, "deadline": "2026-02-30"}},
      {"version": 1, "progress": {"percent": 5, "start": "2026-12-01", "deadline": "2026-11-01"}},
      {"version": 1, "scroll": 1.5},
      {"version": 1, "scroll": ""},
      {"version": 1, "scroll": None},
      {"version": 1, "blocks": {}},
      {"version": 1, "blocks": [{"id": "a", "type": "text", "text": ""}, {"id": "a", "type": "text", "text": ""}]},
      with_block({"type": "text", "text": "x"}),
      with_block({"id": "a", "text": "x"}),
      with_block({"id": "a", "type": "notices"}),
      with_block({"id": "a", "type": "notices", "items": [{"id": "n1", "level": "fatal", "text": "x"}]}),
      with_block({"id": "a", "type": "notices", "items": [{"id": "n1", "level": "info"}]}),
      with_block({"id": "a", "type": "notices", "items": [
        {"id": "n1", "level": "info", "text": "x"}, {"id": "n1", "level": "info", "text": "y"}]}),
      with_block({"id": "a", "type": "focus", "next": "uno"}),
      with_block({"id": "a", "type": "milestones", "items": [{"label": "x", "status": "late"}]}),
      with_block({"id": "a", "type": "milestones", "items": [{"label": "x", "status": "done", "date": "mañana"}]}),
      with_block({"id": "a", "type": "text", "text": 3}),
      with_block({"id": "a", "type": "progress", "percent": -1}),
    ]
    for doc in bad:
      with self.subTest(doc=doc):
        r = self.validate_doc(doc)
        self.assertEqual(r.returncode, 2, "accepted: %r" % (doc,))
        self.assertIn("invalid", r.stderr)

  def test_strict_json_and_version(self):
    bad = [
      '{"version": true, "blocks": []}',
      '{"version": 1.0, "blocks": []}',
      '{"version": 1, "blocks": [], "x": NaN}',
      '{"version": 1, "blocks": [], "x": Infinity}',
      '{"version": 1, "blocks": [], "x": 1e999}',
      '{"version": 1, "blocks": [{"id": "a", "type": "notices", "items": [{"id": [1], "level": "info", "text": "t"}]}]}',
      '{"version": 1, "blocks": [{"id": "a", "type": "notices", "items": [{"id": {}, "level": "info", "text": "t"}]}]}',
    ]
    os.makedirs(self.config, exist_ok=True)
    for text in bad:
      with self.subTest(text=text):
        with open(self.ws_file(), "w") as f:
          f.write(text)
        err = self.fails(2, "validate", "--ws", "3")
        self.assertNotIn("Traceback", err)
        err = self.fails(2, "--ws", "3", "text", "nota", "x")
        self.assertNotIn("Traceback", err)
        with open(self.ws_file()) as f:
          self.assertEqual(f.read(), text)

  def test_non_finite_arguments_rejected(self):
    for text in ('[{"label": "a", "status": "done", "x": NaN}]', '[{"label": "a", "status": "done", "x": -Infinity}]',
                 '[{"label": "a", "status": "done", "x": 1e400}]'):
      with self.subTest(text=text):
        err = self.fails(2, "--ws", "3", "milestones", "set", text)
        self.assertNotIn("Traceback", err)
        self.assertFalse(os.path.exists(self.ws_file()))
    for v in ("nan", "inf", "-inf"):
      with self.subTest(percent=v):
        self.fails(2, "--ws", "3", "progress", "--percent", v)
    self.assertFalse(os.path.exists(self.ws_file()))

  def test_invalid_json_file(self):
    path = os.path.join(self.tmp, "broken.json")
    with open(path, "w") as f:
      f.write("{ nope")
    self.fails(2, "validate", path)

  def test_validate_default_target(self):
    self.write_doc(GOOD_DOC, ws=2)
    self.assertIn("workspace2.json", self.ok("--ws", "2", "validate"))
    self.fails(1, "--ws", "3", "validate")

  def test_rejected_input_does_not_write(self):
    self.write_doc(GOOD_DOC)
    before = self.raw()
    attempts = [
      ("progress", "--percent", "150"),
      ("progress", "--deadline", "2026-13-01"),
      ("progress", "--start", "2026-12-30"),
      ("milestones", "set", "not json"),
      ("milestones", "set", '[{"label": "x", "status": "late"}]'),
      ("milestones", "set", '{"label": "x"}'),
      ("milestone", "status", "Nope", "done"),
      ("milestone", "status", "Modelo", "late"),
      ("notice", "add", "--level", "fatal", "x"),
      ("notice", "add", "  "),
      ("notice", "rm", "n404"),
      ("text", "foco", "the focus block is not a text block"),
      ("block", "rm", "nope"),
      ("block", "move", "nota", "--to", "99"),
      ("scroll", "1.5"),
      ("scroll", "no-such-block"),
      ("focus",),
    ]
    for args in attempts:
      with self.subTest(args=args):
        self.fails(2, "--ws", "3", *args)
        self.assertEqual(self.raw(), before)
    leftovers = [n for n in os.listdir(self.config) if n.endswith(".tmp")]
    self.assertEqual(leftovers, [])

  def test_invalid_existing_file_is_not_overwritten(self):
    os.makedirs(self.config)
    with open(self.ws_file(), "w") as f:
      f.write('{"version": 1, "blocks": [')
    self.fails(2, "--ws", "3", "text", "nota", "x")
    with open(self.ws_file()) as f:
      self.assertEqual(f.read(), '{"version": 1, "blocks": [')
    self.write_doc({"version": 9, "blocks": []})
    self.fails(2, "--ws", "3", "notice", "add", "x")
    self.assertEqual(self.read_doc()["version"], 9)


class TestAtomicWrite(WsbarTestCase):
  def test_creates_dirs_and_valid_file(self):
    self.assertFalse(os.path.exists(self.config))
    self.ok("--ws", "3", "text", "nota", "hola")
    self.assert_valid_file()
    self.assertEqual(self.read_doc(), {"version": 1, "blocks": [{"id": "nota", "type": "text", "text": "hola"}]})
    self.assertEqual(sorted(os.listdir(self.config)), ["workspace3.json"])
    self.assertEqual(stat.S_IMODE(os.stat(self.ws_file()).st_mode), 0o644)

  def test_write_replaces_inode(self):
    # os.replace swaps in a new file instead of truncating the one the sidebar is reading.
    self.write_doc(GOOD_DOC)
    before = os.stat(self.ws_file()).st_ino
    self.ok("--ws", "3", "text", "nota", "nuevo")
    self.assertNotEqual(os.stat(self.ws_file()).st_ino, before)
    self.assert_valid_file()

  def test_unicode_kept_readable(self):
    self.ok("--ws", "3", "text", "nota", "Facturación — ñandú")
    self.assertIn("Facturación — ñandú", self.raw().decode("utf-8"))


class TestCommands(WsbarTestCase):
  def setUp(self):
    super().setUp()
    self.write_doc(GOOD_DOC)

  def run3(self, *args):
    return self.ok("--ws", "3", *args)

  def assert_untouched_except(self, doc, *changed):
    for key in ("project", "custom", "progress", "scroll"):
      if key not in changed:
        self.assertEqual(doc.get(key), GOOD_DOC.get(key), key)
    for b in GOOD_DOC["blocks"]:
      if b["id"] not in changed:
        self.assertEqual(self.block(doc, b["id"]), b, b["id"])
    self.assert_valid_file()

  def test_show(self):
    self.assertEqual(json.loads(self.run3("show")), GOOD_DOC)
    self.fails(1, "--ws", "4", "show")

  def test_show_does_not_write(self):
    before = os.stat(self.ws_file())
    self.run3("show")
    after = os.stat(self.ws_file())
    self.assertEqual((before.st_ino, before.st_mtime_ns), (after.st_ino, after.st_mtime_ns))

  def test_progress_partial_update(self):
    self.run3("progress", "--percent", "70")
    doc = self.read_doc()
    self.assertEqual(doc["progress"], {"label": "Release", "percent": 70, "start": "2026-10-20", "deadline": "2026-11-18"})
    self.assert_untouched_except(doc, "progress")

  def test_progress_full_and_remove_dates(self):
    self.run3("progress", "--label", "Otra", "--percent", "12.5", "--start", "", "--deadline", "2026-12-01")
    self.assertEqual(self.read_doc()["progress"], {"label": "Otra", "percent": 12.5, "deadline": "2026-12-01"})

  def test_progress_new_requires_percent(self):
    self.fails(2, "--ws", "4", "progress", "--label", "x")
    self.assertFalse(os.path.exists(self.ws_file(4)))
    self.ok("--ws", "4", "progress", "--label", "x", "--percent", "0")
    self.assertEqual(self.read_doc(4)["progress"], {"label": "x", "percent": 0})

  def test_progress_clear(self):
    self.run3("progress", "--clear")
    doc = self.read_doc()
    self.assertNotIn("progress", doc)
    self.assert_untouched_except(doc, "progress")

  def test_focus_update(self):
    self.run3("focus", "--now", "Emails")
    doc = self.read_doc()
    self.assertEqual(self.block(doc, "foco"), {"id": "foco", "type": "focus", "now": "Emails", "next": ["Reintentos"]})
    self.assert_untouched_except(doc, "foco")
    self.run3("focus", "--next", "A", "--next", "B")
    self.assertEqual(self.block(self.read_doc(), "foco")["next"], ["A", "B"])
    self.run3("focus", "--clear-next")
    self.assertEqual(self.block(self.read_doc(), "foco")["next"], [])

  def test_focus_created_after_notices(self):
    self.ok("--ws", "4", "notice", "add", "aviso")
    self.ok("--ws", "4", "text", "nota", "x")
    self.ok("--ws", "4", "focus", "--now", "Algo", "--next", "Luego")
    self.assertEqual(self.ids(self.read_doc(4)), ["avisos", "foco", "nota"])

  def test_milestones_set_replaces_in_place(self):
    self.run3("milestones", "set", '[{"label": "Uno", "status": "current", "date": "2026-11-20"}]')
    doc = self.read_doc()
    self.assertEqual(self.ids(doc), self.ids(GOOD_DOC))
    self.assertEqual(self.block(doc, "hitos")["items"], [{"label": "Uno", "status": "current", "date": "2026-11-20"}])
    self.assert_untouched_except(doc, "hitos")

  def test_milestones_set_accepts_items_object_and_creates(self):
    self.ok("--ws", "4", "focus", "--now", "x")
    self.ok("--ws", "4", "milestones", "set", '{"items": [{"label": "A", "status": "pending"}]}')
    self.assertEqual(self.ids(self.read_doc(4)), ["foco", "hitos"])

  def test_milestone_status(self):
    self.run3("milestone", "status", "Checkout", "done")
    doc = self.read_doc()
    self.assertEqual(self.block(doc, "hitos")["items"][1], {"label": "Checkout", "status": "done", "date": "2026-11-12"})
    self.assert_untouched_except(doc, "hitos")

  def test_notice_add_and_rm(self):
    nid = self.run3("notice", "add", "--level", "error", "Deploy falló").strip()
    self.assertRegex(nid, r"^n[0-9a-z]+$")
    doc = self.read_doc()
    items = self.block(doc, "avisos")["items"]
    self.assertEqual(items[0]["id"], "n1")
    self.assertEqual(items[1]["id"], nid)
    self.assertEqual(items[1]["level"], "error")
    self.assertEqual(items[1]["text"], "Deploy falló")
    self.assertRegex(items[1]["at"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$")
    self.assert_untouched_except(doc, "avisos")
    self.run3("notice", "rm", "n1")
    items = self.block(self.read_doc(), "avisos")["items"]
    self.assertEqual([n["id"] for n in items], [nid])
    self.assert_untouched_except(self.read_doc(), "avisos")

  def test_notice_ids_unique_and_default_level(self):
    ids = [self.ok("--ws", "4", "notice", "add", "aviso %d" % i).strip() for i in range(5)]
    self.assertEqual(len(set(ids)), 5)
    doc = self.read_doc(4)
    self.assertEqual(self.ids(doc), ["avisos"])
    self.assertEqual({n["level"] for n in doc["blocks"][0]["items"]}, {"info"})

  def test_notice_block_created_at_top(self):
    self.ok("--ws", "4", "text", "nota", "x")
    self.ok("--ws", "4", "notice", "add", "y")
    self.assertEqual(self.ids(self.read_doc(4)), ["avisos", "nota"])

  def test_text_update_and_create(self):
    self.run3("text", "nota", "Nuevo *texto*")
    doc = self.read_doc()
    self.assertEqual(self.block(doc, "nota")["text"], "Nuevo *texto*")
    self.assert_untouched_except(doc, "nota")
    self.run3("text", "otra", "al final")
    self.assertEqual(self.ids(self.read_doc())[-1], "otra")

  def test_meter_update_and_create(self):
    self.run3("meter", "sub", "--percent", "75")
    doc = self.read_doc()
    self.assertEqual(self.block(doc, "sub")["percent"], 75)
    self.assertEqual(self.block(doc, "sub")["label"], "Cobertura")
    self.assert_untouched_except(doc, "sub")
    self.run3("meter", "cov", "--label", "Cobertura", "--percent", "40")
    doc = self.read_doc()
    self.assertEqual(self.ids(doc)[-1], "cov")
    self.assertEqual(self.block(doc, "cov"), {"id": "cov", "type": "progress", "label": "Cobertura", "percent": 40})

  def test_meter_needs_percent_when_new(self):
    before = self.raw()
    r = self.run_wsbar("--ws", "3", "meter", "nuevo", "--label", "x")
    self.assertEqual(r.returncode, 2)
    self.assertEqual(self.raw(), before)

  def test_meter_rejects_other_block_type(self):
    r = self.run_wsbar("--ws", "3", "meter", "nota", "--percent", "10")
    self.assertEqual(r.returncode, 2)

  def test_block_rm(self):
    self.run3("block", "rm", "sub")
    doc = self.read_doc()
    self.assertNotIn("sub", self.ids(doc))
    self.assert_untouched_except(doc, "sub")

  def test_block_move(self):
    self.run3("block", "move", "nota", "--to", "0")
    self.assertEqual(self.ids(self.read_doc()), ["nota", "avisos", "foco", "hitos", "sub", "futuro"])
    self.run3("block", "move", "nota", "--to", "5")
    self.assertEqual(self.ids(self.read_doc()), ["avisos", "foco", "hitos", "sub", "futuro", "nota"])
    self.assert_untouched_except(self.read_doc())

  def test_scroll(self):
    for target, expected in (("bottom", "bottom"), ("0.4", 0.4), ("1", 1), ("hitos", "hitos"), ("top", "top")):
      with self.subTest(target=target):
        self.run3("scroll", target)
        doc = self.read_doc()
        self.assertEqual(doc["scroll"], expected)
        self.assert_untouched_except(doc, "scroll")

  def test_scroll_numeric_block_id(self):
    self.run3("text", "1", "hola")
    self.run3("scroll", "1")
    self.assertEqual(self.read_doc()["scroll"], "1")
    self.run3("scroll", "0.5")
    self.assertEqual(self.read_doc()["scroll"], 0.5)
    for bad in ("nan", "inf", "2", "nope"):
      with self.subTest(target=bad):
        self.fails(2, "--ws", "3", "scroll", bad)
    self.assertEqual(self.read_doc()["scroll"], 0.5)

  def test_unknown_block_type_preserved(self):
    self.run3("notice", "add", "x")
    self.assertEqual(self.block(self.read_doc(), "futuro"), {"id": "futuro", "type": "chart", "whatever": [1, 2]})

  def test_other_workspaces_untouched(self):
    self.write_doc({"version": 1, "blocks": []}, ws=5)
    before = self.raw(5)
    self.run3("text", "nota", "x")
    self.assertEqual(self.raw(5), before)


class TestPlan(WsbarTestCase):
  PLAN = {
    "label": "Release 1.2",
    "start": "2026-10-20",
    "deadline": "2026-11-18",
    "items": [
      {"id": "modelo", "label": "Modelo de datos", "weight": 2, "milestone": "Datos"},
      {"id": "api", "label": "API", "weight": 3, "milestone": "Checkout"},
      {"id": "ui", "label": "UI", "milestone": "Checkout"},
      {"id": "docs", "label": "Docs"},
      {"id": "factura", "label": "Factura", "weight": 2, "milestone": "Facturación"},
    ],
  }

  def plan_file(self, repo=None):
    root = os.path.realpath(repo or self.repo)
    slug = root.replace("/", "-").lstrip("-") + "-" + hashlib.sha1(root.encode()).hexdigest()[:10]
    return os.path.join(self.data, "projects", slug + ".json")

  def make_repo(self, *parts):
    path = os.path.join(self.tmp, *parts)
    os.makedirs(path)
    subprocess.run(["git", "init", "-q", path], check=True)
    return path

  def set_plan(self, plan=None, **kw):
    return self.ok("plan", "set", json.dumps(plan or self.PLAN), cwd=os.path.join(self.repo, "sub"), **kw)

  def in_repo(self, *args, **kw):
    return self.ok(*args, cwd=self.repo, **kw)

  def test_slug_and_defaults(self):
    out = self.set_plan()
    self.assertEqual(out.strip(), self.plan_file())
    self.assertFalse(os.path.basename(self.plan_file()).startswith("-"))
    with open(self.plan_file()) as f:
      plan = json.load(f)
    self.assertEqual([it["weight"] for it in plan["items"]], [2, 3, 1, 1, 2])
    self.assertEqual({it["status"] for it in plan["items"]}, {"pending"})
    self.assertEqual(plan["history"][-1]["event"], "set")

  def test_project_flag(self):
    self.ok("plan", "set", "--project", os.path.join(self.repo, "sub"), json.dumps(self.PLAN))
    self.assertTrue(os.path.exists(self.plan_file()))
    shown = json.loads(self.ok("plan", "show", "--project", self.repo))
    self.assertEqual(shown["project"], os.path.realpath(self.repo))

  def test_outside_git_requires_project(self):
    outside = os.path.join(self.tmp, "outside")
    os.makedirs(outside)
    self.fails(1, "plan", "set", json.dumps(self.PLAN), cwd=outside)
    # An explicit non-git directory is accepted as its own project.
    self.ok("plan", "set", "--project", outside, json.dumps(self.PLAN))

  def test_plan_set_rejects_bad_plans(self):
    bad = [
      "not json",
      {"items": []},
      {"label": "x"},
      {"label": "x", "items": [{"id": "a", "label": "A", "weight": 0}]},
      {"label": "x", "items": [{"id": "a", "label": "A", "status": "half"}]},
      {"label": "x", "items": [{"id": "a", "label": "A"}, {"id": "a", "label": "B"}]},
      {"label": "x", "deadline": "pronto", "items": []},
    ]
    for plan in bad:
      with self.subTest(plan=plan):
        text = plan if isinstance(plan, str) else json.dumps(plan)
        self.fails(2, "plan", "set", text, cwd=self.repo)
        self.assertFalse(os.path.exists(self.plan_file()))

  def test_plan_set_rejects_more_bad_plans(self):
    bad = [
      '{"label": "x", "items": [{"id": "a", "label": "A", "weight": NaN}]}',
      '{"label": "x", "items": [{"id": "a", "label": "A", "weight": Infinity}]}',
      '{"label": "x", "items": [{"id": "a", "label": "A", "weight": 1e999}]}',
      '{"label": "x", "items": [{"id": {}, "label": "A"}]}',
      '{"label": "x", "items": [{"id": ["a"], "label": "A"}]}',
      '{"label": "x", "start": "2026-12-01", "deadline": "2026-11-01", "items": []}',
    ]
    for text in bad:
      with self.subTest(plan=text):
        err = self.fails(2, "plan", "set", text, cwd=self.repo)
        self.assertNotIn("Traceback", err)
        self.assertFalse(os.path.exists(self.plan_file()))
    self.set_plan({"label": "x", "start": "2026-11-01", "deadline": "2026-11-01", "items": []})

  def test_similar_paths_get_separate_plans(self):
    # a-b and a/b would share a slug if '/' simply became '-'.
    one = self.make_repo("w", "foo-bar")
    two = self.make_repo("w", "foo", "bar")
    self.assertNotEqual(self.plan_file(one), self.plan_file(two))
    self.ok("plan", "set", json.dumps({"label": "A", "items": [{"id": "x", "label": "X"}]}), cwd=one)
    self.ok("plan", "done", "x", "--no-publish", cwd=one)
    self.ok("plan", "set", json.dumps({"label": "B", "items": [{"id": "x", "label": "X"}]}), cwd=two)
    shown_one = json.loads(self.ok("plan", "show", cwd=one))
    shown_two = json.loads(self.ok("plan", "show", cwd=two))
    self.assertEqual((shown_one["label"], shown_one["percent"]), ("A", 100))
    # B does not inherit A's done status or history.
    self.assertEqual((shown_two["label"], shown_two["percent"]), ("B", 0))
    self.assertEqual([h["event"] for h in shown_two["history"]], ["set"])
    self.assertEqual(shown_two["root"], os.path.realpath(two))

  def test_plan_of_another_root_refused(self):
    self.set_plan()
    with open(self.plan_file()) as f:
      plan = json.load(f)
    plan["root"] = "/somewhere/else"
    with open(self.plan_file(), "w") as f:
      json.dump(plan, f)
    self.fails(1, "plan", "show", cwd=self.repo)
    self.fails(1, "publish", "--ws", "3", cwd=self.repo)
    self.assertFalse(os.path.exists(self.ws_file()))

  def test_publish_other_project_without_milestones(self):
    other = self.make_repo("p1")
    self.ok("plan", "set", json.dumps({"label": "P1", "items": [{"id": "a", "label": "A", "milestone": "Hito de P1"}]}), cwd=other)
    self.ok("publish", "--ws", "3", cwd=other)
    self.ok("--ws", "3", "focus", "--now", "Cosa de P1")
    self.ok("--ws", "3", "text", "nota", "x")
    self.set_plan({"label": "P2", "items": [{"id": "b", "label": "B"}]})
    self.in_repo("publish", "--ws", "3")
    doc = self.read_doc()
    self.assertEqual(doc["project"], os.path.realpath(self.repo))
    self.assertEqual(doc["progress"]["label"], "P2")
    # The milestones and focus of P1 are gone; other blocks stay.
    self.assertEqual(self.ids(doc), ["nota"])

  def test_replan_dropping_milestones_removes_block(self):
    self.set_plan()
    self.in_repo("publish", "--ws", "3")
    self.assertIsNotNone(self.block(self.read_doc(), "hitos"))
    self.set_plan({"label": "x", "items": [{"id": "a", "label": "A"}]})
    self.in_repo("publish", "--ws", "3")
    self.assertIsNone(self.block(self.read_doc(), "hitos"))

  def test_milestone_dates_not_carried_across_projects(self):
    other = self.make_repo("p1")
    plan = {"label": "P", "items": [{"id": "a", "label": "A", "milestone": "Beta"}]}
    self.ok("plan", "set", json.dumps(plan), cwd=other)
    self.ok("publish", "--ws", "3", cwd=other)
    self.ok("--ws", "3", "milestones", "set", '[{"label": "Beta", "status": "current", "date": "2026-11-30"}]')
    self.ok("publish", "--ws", "3", cwd=other)
    self.assertEqual(self.block(self.read_doc(), "hitos")["items"][0].get("date"), "2026-11-30")
    self.set_plan(plan)
    self.in_repo("publish", "--ws", "3")
    self.assertNotIn("date", self.block(self.read_doc(), "hitos")["items"][0])

  def test_done_with_unwritable_workspace_keeps_plan(self):
    self.set_plan()
    os.makedirs(self.config)
    with open(self.ws_file(), "w") as f:
      f.write("garbage")
    with open(self.plan_file(), "rb") as f:
      before = f.read()
    self.fails(2, "plan", "done", "modelo", "--ws", "3", cwd=self.repo)
    with open(self.plan_file(), "rb") as f:
      self.assertEqual(f.read(), before)

  def test_percent_math(self):
    self.set_plan()
    self.assertEqual(json.loads(self.in_repo("plan", "show"))["percent"], 0)
    # Total weight 9: 2/9 -> 22, 5/9 -> 56, 6/9 -> 67, 7/9 -> 78, 9/9 -> 100.
    for item, expected in (("modelo", 22), ("api", 56), ("ui", 67), ("docs", 78), ("factura", 100)):
      with self.subTest(item=item):
        self.assertEqual(self.in_repo("plan", "done", item, "--ws", "3").strip(), "%d%%" % expected)
        self.assertEqual(self.read_doc()["progress"]["percent"], expected)

  def test_percent_rounds_half_up(self):
    self.set_plan({"label": "x", "items": [{"id": "a", "label": "A"}, {"id": "b", "label": "B", "weight": 7}]})
    self.assertEqual(self.in_repo("plan", "done", "a", "--no-publish").strip(), "13%")

  def test_done_publishes(self):
    self.write_doc(dict(GOOD_DOC, project=os.path.realpath(self.repo)))
    self.set_plan()
    self.in_repo("plan", "done", "modelo", "--ws", "3")
    doc = self.read_doc()
    self.assertEqual(doc["project"], os.path.realpath(self.repo))
    self.assertEqual(doc["progress"], {"label": "Release 1.2", "percent": 22, "start": "2026-10-20", "deadline": "2026-11-18"})
    # The milestones block is replaced in place, keeping known dates.
    self.assertEqual(self.ids(doc), self.ids(GOOD_DOC))
    self.assertEqual(self.block(doc, "hitos")["items"], [
      {"label": "Datos", "status": "done"},
      {"label": "Checkout", "status": "current", "date": "2026-11-12"},
      {"label": "Facturación", "status": "pending"},
    ])
    for key in ("custom", "scroll"):
      self.assertEqual(doc[key], GOOD_DOC[key])
    for bid in ("avisos", "foco", "nota", "sub", "futuro"):
      self.assertEqual(self.block(doc, bid), self.block(GOOD_DOC, bid))
    self.assert_valid_file()
    with open(self.plan_file()) as f:
      plan = json.load(f)
    self.assertEqual(plan["history"][-1]["item"], "modelo")
    self.assertEqual(plan["history"][-1]["event"], "done")

  def test_milestone_derivation(self):
    self.set_plan()
    self.in_repo("plan", "done", "api", "--ws", "3")
    statuses = lambda: [(m["label"], m["status"]) for m in self.block(self.read_doc(), "hitos")["items"]]
    # Datos is not done, so it is current even though Checkout has progress.
    self.assertEqual(statuses(), [("Datos", "current"), ("Checkout", "pending"), ("Facturación", "pending")])
    self.in_repo("plan", "done", "modelo", "--ws", "3")
    self.assertEqual(statuses(), [("Datos", "done"), ("Checkout", "current"), ("Facturación", "pending")])
    self.in_repo("plan", "done", "ui", "--ws", "3")
    self.assertEqual(statuses(), [("Datos", "done"), ("Checkout", "done"), ("Facturación", "current")])
    self.in_repo("plan", "done", "factura", "--ws", "3")
    self.assertEqual(statuses(), [("Datos", "done"), ("Checkout", "done"), ("Facturación", "done")])

  def test_milestones_block_inserted_after_notices(self):
    self.ok("--ws", "3", "text", "nota", "x")
    self.ok("--ws", "3", "notice", "add", "aviso")
    self.set_plan()
    self.in_repo("publish", "--ws", "3")
    self.assertEqual(self.ids(self.read_doc()), ["avisos", "hitos", "nota"])

  def test_milestones_block_at_top_without_notices(self):
    self.ok("--ws", "3", "text", "nota", "x")
    self.set_plan()
    self.in_repo("publish", "--ws", "3")
    self.assertEqual(self.ids(self.read_doc()), ["hitos", "nota"])

  def test_no_milestones_no_block(self):
    plan = {"label": "Simple", "items": [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}]}
    self.set_plan(plan)
    self.assertIn("50%", self.in_repo("plan", "done", "a", "--ws", "3"))
    doc = self.read_doc()
    self.assertEqual(doc["blocks"], [])
    self.assertEqual(doc["progress"], {"label": "Simple", "percent": 50})

  def test_replan_keeps_done_and_history(self):
    self.set_plan()
    self.in_repo("plan", "done", "modelo", "--no-publish")
    self.assertFalse(os.path.exists(self.ws_file()))
    self.set_plan()
    shown = json.loads(self.in_repo("plan", "show"))
    self.assertEqual(shown["percent"], 22)
    self.assertEqual([h["event"] for h in shown["history"]], ["set", "done", "set"])

  def test_done_unknown_item(self):
    self.set_plan()
    self.fails(2, "plan", "done", "nope", "--ws", "3", cwd=self.repo)
    self.assertFalse(os.path.exists(self.ws_file()))

  def test_done_without_plan(self):
    self.fails(2, "plan", "done", "x", "--ws", "3", cwd=self.repo)

  def test_done_needs_workspace_before_writing(self):
    self.set_plan()
    with open(self.plan_file(), "rb") as f:
      before = f.read()
    self.fails(1, "plan", "done", "modelo", cwd=self.repo)
    with open(self.plan_file(), "rb") as f:
      self.assertEqual(f.read(), before)

  def test_publish_autodetects_workspace(self):
    self.set_clients([{"pid": os.getpid(), "workspace": {"id": 9, "name": "9"}}])
    self.set_plan()
    self.assertIn("workspace 9", self.in_repo("publish"))
    self.assertEqual(self.read_doc(9)["progress"]["percent"], 0)

  def test_publish_refuses_invalid_workspace_file(self):
    os.makedirs(self.config)
    with open(self.ws_file(), "w") as f:
      f.write("garbage")
    self.set_plan()
    self.fails(2, "publish", "--ws", "3", cwd=self.repo)
    with open(self.ws_file()) as f:
      self.assertEqual(f.read(), "garbage")


class TestCli(WsbarTestCase):
  def test_help_documents_env(self):
    out = self.ok("--help")
    for name in ("WSBAR_CONFIG_DIR", "WSBAR_DATA_DIR", "WSBAR_WS", "WSBAR_HYPRCTL"):
      self.assertIn(name, out)

  def test_usage_errors_exit_2(self):
    self.fails(2)
    self.fails(2, "bogus")
    self.fails(2, "notice")

  def test_executable_with_shebang(self):
    self.assertTrue(os.access(WSBAR, os.X_OK))
    with open(WSBAR) as f:
      self.assertEqual(f.readline().strip(), "#!/usr/bin/env python3")


class TestHardening(WsbarTestCase):
  """Content arrives from sessions that read untrusted repo text."""

  def test_markdown_rejects_images_html_and_non_https_links(self):
    for bad in ("![i](http://x/y.png)", "<img src=x>", "</b>", "<!-- c -->",
                "[x](file:///etc/passwd)", "[x](http://a.b)", "[r]: file:///etc"):
      self.fails(2, "--ws", "3", "text", "n", bad)
    self.assertFalse(os.path.exists(self.ws_file()))

  def test_markdown_allows_https_links_and_comparisons(self):
    self.ok("--ws", "3", "text", "n", "**ok** [x](https://a.b) a < b y 3>2")

  def test_rejects_deep_nesting_without_traceback(self):
    deep = "[" * 60000 + "]" * 60000
    err = self.fails(2, "--ws", "3", "milestones", "set", deep)
    self.assertNotIn("Traceback", err)
    err = self.fails(2, "--ws", "3", "milestones", "set", "[" * 20 + "]" * 20)
    self.assertIn("nests deeper", err)

  def test_rejects_oversized_strings_and_lists(self):
    self.fails(2, "--ws", "3", "notice", "add", "--level", "info", "x" * 5000)
    many = json.dumps([{"label": "m%d" % i, "status": "pending"} for i in range(300)])
    self.fails(2, "--ws", "3", "milestones", "set", many)

  def test_created_files_follow_umask(self):
    old = os.umask(0o077)
    try:
      self.ok("--ws", "3", "text", "n", "hola")
    finally:
      os.umask(old)
    self.assertEqual(os.stat(self.ws_file()).st_mode & 0o777, 0o600)


if __name__ == "__main__":
  unittest.main()
