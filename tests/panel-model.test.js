// Plain-node tests for PanelModel.js. The file is a QML library script, so the
// `.pragma library` line is stripped before evaluation.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "PanelModel.js"), "utf8")
  .replace(/^\.pragma library\n/, "")
const mod = { exports: {} }
new Function("module", source)(mod)
const m = mod.exports

const base = { screenW: 1920, screenH: 1080, width: 480, height: 360, gap: 5, barSize: 26 }

// cursor placement: below the cursor, clamped into the screen
let g = m.cardGeometry({ ...base, position: "cursor", cursor: { x: 800, y: 300 } })
assert.strictEqual(g.y, 316)
assert.ok(g.x >= 5 && g.x + g.width <= 1915)

g = m.cardGeometry({ ...base, position: "cursor", cursor: { x: 1900, y: 1000 } })
assert.ok(g.x + g.width <= 1915, "clamped at the right edge")
assert.ok(g.y + g.height <= 1075, "flipped above the cursor near the bottom edge")
assert.ok(g.y < 1000)

g = m.cardGeometry({ ...base, position: "cursor", cursor: { x: 0, y: 0 } })
assert.ok(g.x >= 5 && g.y >= 5)

// cursor mode without a cursor falls back to the centre
g = m.cardGeometry({ ...base, position: "cursor", cursor: null })
assert.deepStrictEqual([g.x, g.y], [720, 360])

g = m.cardGeometry({ ...base, position: "center", cursor: { x: 1, y: 1 } })
assert.deepStrictEqual([g.x, g.y, g.width, g.height], [720, 360, 480, 360])

// bar mode: under a top bar, above a bottom bar, beside side bars
g = m.cardGeometry({ ...base, position: "bar", barPosition: "top" })
assert.strictEqual(g.y, 26 + 10)
assert.strictEqual(g.x, 720)
g = m.cardGeometry({ ...base, position: "bar", barPosition: "bottom" })
assert.strictEqual(g.y, 1080 - 360 - 36)
g = m.cardGeometry({ ...base, position: "bar", barPosition: "left" })
assert.strictEqual(g.x, 36)
g = m.cardGeometry({ ...base, position: "bar", barPosition: "right" })
assert.strictEqual(g.x, 1920 - 480 - 36)

// the card never exceeds a small screen
g = m.cardGeometry({ ...base, screenW: 300, screenH: 200, position: "center" })
assert.ok(g.width <= 290 && g.height <= 190)

// command output parsing
let r = m.parseCommandOutput('{"source":"a","translation":"b","provider":"deepl","senses":[]}', 0)
assert.strictEqual(r.state, "result")
assert.strictEqual(r.result.translation, "b")
r = m.parseCommandOutput('{"error":"quota","message":"limit"}', 1)
assert.strictEqual(r.state, "error")
assert.strictEqual(r.error.error, "quota")
r = m.parseCommandOutput("", 127)
assert.strictEqual(r.state, "error")
assert.match(r.error.message, /127/)
r = m.parseCommandOutput("not json at all", 1)
assert.strictEqual(r.error.message, "not json at all")

// payload files: only the private files the command writes are read
assert.strictEqual(m.isPayloadPath("/home/u/.cache/omarchy-translate/ipc/payload.aB3xYz"), true)
assert.strictEqual(m.isPayloadPath("/tmp/t/cache/ipc/payload.Zz9Zz9"), true)
assert.strictEqual(m.isPayloadPath('{"state":"loading"}'), false, "inline JSON is not a path")
assert.strictEqual(m.isPayloadPath("/etc/passwd"), false)
assert.strictEqual(m.isPayloadPath("/home/u/.cache/omarchy-translate/ipc/../../.ssh/id_ed25519"), false)
assert.strictEqual(m.isPayloadPath("/home/u/.cache/x/ipc/../ipc/payload.abc123"), false)
assert.strictEqual(m.isPayloadPath("ipc/payload.abc123"), false, "relative paths are refused")
assert.strictEqual(m.isPayloadPath("/home/u/ipc/payload.abc/../../secret"), false)
assert.strictEqual(m.isPayloadPath(""), false)
assert.strictEqual(m.isPayloadPath(undefined), false)

// languages
assert.strictEqual(m.languageName("ru"), "Russian")
assert.strictEqual(m.languageName("xx"), "XX")
assert.strictEqual(m.languageName(""), "")
assert.strictEqual(m.languageOptions(true)[0].value, "auto")
assert.notStrictEqual(m.languageOptions(false)[0].value, "auto")
assert.ok(m.LANGUAGES.every(([code]) => /^[a-z]{2}$/.test(code)), "codes are lowercase ISO 639-1")

// variants and glyphs
assert.strictEqual(m.variantsLine(["a", "b", "c"], 2), "a, b")
assert.strictEqual(m.variantsLine(["a", "b"], 0), "a, b")
assert.strictEqual(m.variantsLine(undefined, 5), "")
assert.strictEqual(m.glyph(0xF018F).codePointAt(0), 0xF018F)
assert.strictEqual(m.glyph(0x41), "A")

// hints
assert.match(m.errorHint("no_key"), /API key/)
assert.match(m.errorHint("quota"), /limit/)

console.log("panel-model: ok")
