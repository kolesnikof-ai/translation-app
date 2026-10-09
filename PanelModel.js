.pragma library

// Pure helpers for Panel.qml. Kept free of QML types so they can be tested
// with plain node.

var LANGUAGES = [
  ["af", "Afrikaans"], ["ar", "Arabic"], ["bg", "Bulgarian"], ["bn", "Bengali"],
  ["ca", "Catalan"], ["cs", "Czech"], ["da", "Danish"], ["de", "German"],
  ["el", "Greek"], ["en", "English"], ["es", "Spanish"], ["et", "Estonian"],
  ["fa", "Persian"], ["fi", "Finnish"], ["fr", "French"], ["he", "Hebrew"],
  ["hi", "Hindi"], ["hr", "Croatian"], ["hu", "Hungarian"], ["id", "Indonesian"],
  ["it", "Italian"], ["ja", "Japanese"], ["ko", "Korean"], ["lt", "Lithuanian"],
  ["lv", "Latvian"], ["ms", "Malay"], ["nb", "Norwegian"], ["nl", "Dutch"],
  ["pl", "Polish"], ["pt", "Portuguese"], ["ro", "Romanian"], ["ru", "Russian"],
  ["sk", "Slovak"], ["sl", "Slovenian"], ["sr", "Serbian"], ["sv", "Swedish"],
  ["th", "Thai"], ["tr", "Turkish"], ["uk", "Ukrainian"], ["vi", "Vietnamese"],
  ["zh", "Chinese"]
]

function languageName(code) {
  for (var i = 0; i < LANGUAGES.length; i++)
    if (LANGUAGES[i][0] === code) return LANGUAGES[i][1]
  return code ? String(code).toUpperCase() : ""
}

// Options for a dropdown; the source list starts with "auto".
function languageOptions(includeAuto) {
  var out = []
  if (includeAuto) out.push({ value: "auto", label: "Auto-detect" })
  for (var i = 0; i < LANGUAGES.length; i++)
    out.push({ value: LANGUAGES[i][0], label: LANGUAGES[i][1] })
  return out
}

function parseJson(text) {
  try {
    var value = JSON.parse(String(text || ""))
    return value !== null && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

// Normalize the stdout of `omarchy-translate --stdin` into
// { state: "result" | "error", result | error }.
function parseCommandOutput(text, exitCode) {
  var parsed = parseJson(String(text || "").trim())
  if (parsed && parsed.error) return { state: "error", error: parsed }
  if (parsed && typeof parsed.translation === "string") return { state: "result", result: parsed }
  var fallback = String(text || "").trim()
  return {
    state: "error",
    error: {
      error: "network",
      message: fallback || ("The translate command failed" + (exitCode ? " (exit " + exitCode + ")" : ""))
    }
  }
}

function errorHint(code) {
  if (code === "no_key") return "Add your API key to ~/.config/omarchy/translate/config.json"
  if (code === "quota") return "The provider limit is reached. Try again later or switch the provider."
  if (code === "config") return "Check ~/.config/omarchy/translate/config.json"
  return "Check your network connection."
}

function glyph(codePoint) {
  if (codePoint < 0x10000) return String.fromCharCode(codePoint)
  var offset = codePoint - 0x10000
  return String.fromCharCode(0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF))
}

function posLabel(pos) {
  return String(pos || "other")
}

function variantsLine(variants, limit) {
  var list = Array.isArray(variants) ? variants : []
  var max = Number(limit) > 0 ? Number(limit) : list.length
  return list.slice(0, max).join(", ")
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// Where the card goes inside a fullscreen surface. All numbers are logical
// pixels. `position` is "cursor", "center" or "bar".
//   opts: { position, cursor: {x,y}|null, screenW, screenH, width, height,
//           gap, barPosition, barSize }
function cardGeometry(opts) {
  var gap = opts.gap
  var w = Math.min(opts.width, Math.max(1, opts.screenW - gap * 2))
  var h = Math.min(opts.height, Math.max(1, opts.screenH - gap * 2))
  var x = (opts.screenW - w) / 2
  var y = (opts.screenH - h) / 2

  if (opts.position === "cursor" && opts.cursor) {
    var offset = 16
    x = opts.cursor.x - Math.round(w / 4)
    y = opts.cursor.y + offset
    if (y + h > opts.screenH - gap) y = opts.cursor.y - h - offset
  } else if (opts.position === "bar") {
    var edge = opts.barSize + gap * 2
    var side = opts.barPosition || "top"
    if (side === "bottom") y = opts.screenH - h - edge
    else if (side === "left") { x = edge; y = (opts.screenH - h) / 2 }
    else if (side === "right") { x = opts.screenW - w - edge; y = (opts.screenH - h) / 2 }
    else y = edge
  }

  return {
    x: Math.round(clamp(x, gap, Math.max(gap, opts.screenW - w - gap))),
    y: Math.round(clamp(y, gap, Math.max(gap, opts.screenH - h - gap))),
    width: Math.round(w),
    height: Math.round(h)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    LANGUAGES: LANGUAGES, languageName: languageName, languageOptions: languageOptions,
    parseJson: parseJson, parseCommandOutput: parseCommandOutput, errorHint: errorHint,
    glyph: glyph, posLabel: posLabel, variantsLine: variantsLine, cardGeometry: cardGeometry
  }
}
