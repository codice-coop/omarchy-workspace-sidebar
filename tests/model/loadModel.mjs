// Loads a Quickshell `.pragma library` JS file under node: drops the pragma
// line and evaluates the rest in this realm (so deepStrictEqual sees plain
// Arrays/Objects), returning every top-level function and var.
import { readFileSync } from "node:fs"
import vm from "node:vm"

export function loadModel(path) {
  const source = readFileSync(path, "utf8")
  const lines = source.split("\n")
  if (lines[0].trim() !== ".pragma library") throw new Error(path + ": first line must be .pragma library")
  const body = lines.slice(1).join("\n")
  const names = [...body.matchAll(/^(?:function|var)\s+([A-Za-z_$][\w$]*)/gm)].map(m => m[1])
  const wrapped = "(function() {\n" + body + "\nreturn {" + names.join(", ") + "}\n})()"
  return vm.runInThisContext(wrapped, { filename: path })
}
