import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PanelModel.js" as Model

// Floating translation card. The shell calls open(payloadJson) on summon and
// close() on hide; the omarchy-translate command drives everything else.
Item {
  id: root

  // Injected by the shell.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  // "input" (empty field), "loading", "result" or "error".
  property string phase: "loading"
  property string requestId: ""
  property string sourceText: ""
  property var result: null
  property var errorInfo: null

  // Settings forwarded by the command with every summon.
  property var ui: ({})
  property var cursorPos: null
  property string baseSource: "auto"
  property string baseTarget: "ru"

  // Languages picked in the switcher. They last until the panel is closed and
  // never touch the config file. Empty means "use the configured value".
  property string userSource: ""
  property string userTarget: ""
  property int requestSeq: 0
  property bool copied: false
  // The panel was opened without a selection: show the input field.
  property bool inputMode: false

  readonly property bool switcherEnabled: ui.show_language_switcher === true
  readonly property string cliPath: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-translate")).replace(/^file:\/\//, ""))
  readonly property string shownSource: userSource || baseSource
  readonly property string shownTarget: userTarget || (hasResult ? result.target : baseTarget)

  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color muted: Util.alpha(foreground, 0.62)
  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Style.gapsOut

  readonly property bool hasResult: phase === "result" && result !== null
  readonly property var senses: hasResult && Array.isArray(result.senses) ? result.senses : []

  // The service shows this over IPC for debugging, so it only gets the request
  // state; the source text and the translation never leave the panel.
  function remember(state, requestId) {
    if (root.service) root.service.lastPayload = JSON.stringify({ state: state, request_id: requestId })
  }

  // Loads a payload file written by the omarchy-translate command. A fresh
  // view per read always blocks until the file is loaded, so a reused view can
  // never hand back the previous file.
  Component {
    id: payloadFileComponent

    FileView {
      blockLoading: true
      printErrors: false
    }
  }

  // The command passes the path of a private payload file (command-line
  // arguments are readable by every local user). When it could not write one
  // it passes the JSON itself, which is returned unchanged.
  function readPayload(argument) {
    var value = String(argument || "")
    if (!Model.isPayloadPath(value)) return value
    var file = payloadFileComponent.createObject(root, { path: value })
    var text = file.text()
    file.destroy()
    return text
  }

  function applyPayload(p) {
    root.phase = p.state || "loading"
    root.result = p.result || null
    root.errorInfo = p.error || null
    root.sourceText = p.source_text || root.sourceText
  }

  function open(payloadJson) {
    var p = Model.parseJson(root.readPayload(payloadJson)) || {}
    root.ui = p.ui || {}
    root.cursorPos = p.cursor || null
    root.baseSource = p.source || "auto"
    root.baseTarget = p.target || "ru"
    root.userSource = ""
    root.userTarget = ""
    root.requestId = p.request_id || ""
    root.sourceText = p.source_text || ""
    root.inputMode = p.state === "input"
    inputBox.text = ""
    root.applyPayload(p)
    root.opened = true
    Qt.callLater(root.focusKeys)
  }

  function close() {
    root.opened = false
  }

  function focusKeys() {
    if (!root.opened) return
    if (root.inputMode) inputBox.forceActiveFocus()
    else keys.forceActiveFocus()
  }

  function onDelivered(payloadJson) {
    var p = Model.parseJson(root.readPayload(payloadJson))
    if (!p || !root.opened || p.request_id !== root.requestId) return
    root.applyPayload(p)
    root.remember(p.state, p.request_id)
  }

  // Runs `omarchy-translate --stdin` for TEXT with the languages picked in the
  // switcher. Each request gets its own process so a late answer for an older
  // request can never overwrite a newer one.
  function translate(text) {
    var trimmed = String(text || "").trim()
    if (trimmed === "") return
    var args = []
    if (root.userSource) args.push("--from", root.userSource)
    if (root.userTarget) args.push("--to", root.userTarget)
    root.requestSeq += 1
    root.requestId = "panel-" + Date.now() + "-" + root.requestSeq
    root.sourceText = trimmed
    root.result = null
    root.errorInfo = null
    root.phase = "loading"
    var proc = commandComponent.createObject(root, { reqId: root.requestId, text: trimmed, extraArgs: args })
    proc.running = true
  }

  function finishRequest(reqId, output, exitCode) {
    if (reqId !== root.requestId || root.phase !== "loading") return
    var parsed = Model.parseCommandOutput(output, exitCode)
    root.result = parsed.result || null
    root.errorInfo = parsed.error || null
    root.phase = parsed.state
    root.remember(parsed.state, reqId)
  }

  function retranslate() {
    if (root.sourceText !== "") root.translate(root.sourceText)
  }

  function setSource(code) {
    root.userSource = code
    root.retranslate()
  }

  function setTarget(code) {
    root.userTarget = code
    root.retranslate()
  }

  // Exchange the two languages. The detected language stands in for "auto".
  function swapLanguages() {
    var from = root.shownSource === "auto" && root.hasResult ? root.result.detected : root.shownSource
    var to = root.shownTarget
    if (!from || from === "auto") return
    root.userSource = to
    root.userTarget = from
    root.retranslate()
  }

  // A detached process has no stdin and command-line arguments are readable by
  // every local user, so the text travels in the process environment (readable
  // by the owner only). The helper drops the variable before wl-copy starts, so
  // the long-lived wl-copy process does not keep it either.
  Process {
    id: copyProc
    command: ["bash", "-c", "text=$OMARCHY_TRANSLATE_CLIP; unset OMARCHY_TRANSLATE_CLIP; printf %s \"$text\" | wl-copy"]
  }

  // Super+C is rebound by Omarchy to "universal copy": the compositor sends
  // Ctrl+C (Ctrl+Shift+C over a terminal) to the focused surface, so both land
  // here as an ordinary key press.
  function copyTranslation() {
    if (!root.hasResult || !root.result.translation) return
    copyProc.environment = ({ "OMARCHY_TRANSLATE_CLIP": String(root.result.translation) })
    copyProc.startDetached()
    copyProc.environment = ({})
    root.copied = true
    copiedTimer.restart()
  }

  function scrollBy(delta) {
    var max = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Util.clamp(flick.contentY + delta, 0, max)
  }

  Timer {
    id: copiedTimer
    interval: 1400
    onTriggered: root.copied = false
  }

  Component {
    id: commandComponent

    Process {
      id: proc
      property string reqId: ""
      property string text: ""
      property var extraArgs: []
      property bool delivered: false

      // The text goes in through stdin: command-line arguments are readable by
      // every local user. Closing stdin after the write gives the command EOF.
      command: [root.cliPath, "--stdin"].concat(proc.extraArgs)
      stdinEnabled: true
      onStarted: {
        proc.write(proc.text)
        proc.stdinEnabled = false
      }

      stdout: StdioCollector {
        id: collector
        onStreamFinished: {
          proc.delivered = true
          root.finishRequest(proc.reqId, collector.text, 0)
        }
      }

      onExited: function(exitCode) {
        Qt.callLater(function() {
          if (!proc.delivered) root.finishRequest(proc.reqId, collector.text, exitCode)
          proc.destroy()
        })
      }
    }
  }

  // The omarchy-translate command pushes finished results here. "closed"
  // tells it the user dismissed the panel while the request was running.
  IpcHandler {
    target: "translate"

    function show(payloadJson: string): string {
      if (!root.opened) return "closed"
      root.onDelivered(payloadJson)
      return "ok"
    }

    function state(): string {
      return root.opened ? "open" : "closed"
    }

    function ping(): string {
      return "ok"
    }
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-translate"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) root.focusKeys()

    readonly property var geometry: Model.cardGeometry({
      position: String(root.ui.position || "cursor"),
      cursor: root.cursorPos,
      screenW: window.width,
      screenH: window.height,
      width: Style.space(Number(root.ui.width) || 480),
      height: Style.space(Number(root.ui.height) || 360),
      gap: root.gap,
      barPosition: root.shell && root.shell.barConfig ? String(root.shell.barConfig.position || "top") : "top",
      barSize: Style.bar.sizeHorizontal
    })

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      x: window.geometry.x
      y: window.geometry.y
      width: window.geometry.width
      height: window.geometry.height
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var typing = inputBox.activeFocus
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_C && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
            if (typing && inputBox.selectedText.length > 0) return
            root.copyTranslation()
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.scrollBy(flick.height * 0.9)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.scrollBy(-flick.height * 0.9)
            event.accepted = true
          } else if (event.key === Qt.Key_Down && !typing) {
            root.scrollBy(Style.space(40))
            event.accepted = true
          } else if (event.key === Qt.Key_Up && !typing) {
            root.scrollBy(-Style.space(40))
            event.accepted = true
          }
        }

        Row {
          id: langRow
          visible: root.switcherEnabled
          x: card.contentLeftInset
          y: card.contentTopInset
          width: card.width - card.contentLeftInset - card.contentRightInset
          spacing: Style.spacing.rowGap

          SearchableDropdown {
            width: (parent.width - swapButton.width - parent.spacing * 2) / 2
            showLabel: false
            options: Model.languageOptions(true)
            value: root.shownSource
            triggerLabel: root.shownSource === "auto" && root.hasResult
              ? "Auto (" + Model.languageName(root.result.detected) + ")" : ""
            onChanged: function(code) { root.setSource(code) }
          }

          Button {
            id: swapButton
            anchors.verticalCenter: parent.verticalCenter
            text: "\u21C4"
            tooltipText: "Swap languages"
            onClicked: root.swapLanguages()
          }

          SearchableDropdown {
            width: (parent.width - swapButton.width - parent.spacing * 2) / 2
            showLabel: false
            options: Model.languageOptions(false)
            value: root.shownTarget
            onChanged: function(code) { root.setTarget(code) }
          }
        }

        Flickable {
          id: flick
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset + (langRow.visible ? langRow.height + Style.spacing.rowGap : 0)
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          contentWidth: width
          contentHeight: content.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar {}

          Column {
            id: content
            width: flick.width
            spacing: Style.spacing.rowGap

            Text {
              width: parent.width
              visible: root.hasResult && !root.switcherEnabled
              textFormat: Text.PlainText
              text: root.hasResult
                ? Model.languageName(root.result.detected) + "  →  " + Model.languageName(root.result.target)
                  + "  ·  " + root.result.provider
                : ""
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            InputBox {
              id: inputBox
              width: parent.width
              visible: root.inputMode
              onSubmitted: function(text) { root.translate(text) }
            }

            Text {
              width: parent.width
              visible: root.sourceText !== "" && !root.inputMode
              textFormat: Text.PlainText
              text: root.sourceText
              wrapMode: Text.Wrap
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              visible: root.phase === "loading"
              textFormat: Text.PlainText
              text: "Translating…"
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }

            Item {
              width: parent.width
              height: Math.max(translationText.implicitHeight, copyButton.implicitHeight)
              visible: root.hasResult

              Text {
                id: translationText
                anchors.left: parent.left
                anchors.right: copyButton.left
                anchors.rightMargin: Style.spacing.rowGap
                textFormat: Text.PlainText
                text: root.hasResult ? root.result.translation : ""
                wrapMode: Text.Wrap
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Button {
                id: copyButton
                anchors.right: parent.right
                anchors.top: parent.top
                iconText: root.copied ? Model.glyph(0xF012C) : Model.glyph(0xF018F)
                tooltipText: root.copied ? "Copied" : "Copy translation (Super+C)"
                onClicked: root.copyTranslation()
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap
              visible: root.phase === "error"

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.errorInfo ? String(root.errorInfo.message || "Translation failed") : ""
                wrapMode: Text.Wrap
                color: Commons.Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.errorInfo ? Model.errorHint(root.errorInfo.error) : ""
                wrapMode: Text.Wrap
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            Repeater {
              model: root.senses

              delegate: Column {
                required property var modelData
                width: content.width
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: Model.posLabel(modelData.pos)
                  color: root.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: Model.variantsLine(modelData.variants, root.ui.max_variants)
                  wrapMode: Text.Wrap
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
