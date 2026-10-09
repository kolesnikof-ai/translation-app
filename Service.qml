import QtQuick
import qs.Commons

// Headless half of the plugin. It owns the `translate` IPC target so the
// omarchy-translate command can push a finished result to the panel without
// re-summoning it (a re-summon would reopen a panel the user already closed).
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // Maintained by Panel.qml so IPC callers can tell a delivered result from
  // one that arrived after the panel was closed.
  property bool panelOpen: false

  // The most recent payload accepted over IPC, kept for debugging via `state`.
  property string lastPayload: ""

  signal resultReady(string payloadJson)

  ShellIpc {
    target: "translate"

    function show(payloadJson: string): string {
      if (!root.panelOpen) return "closed"
      root.lastPayload = payloadJson
      root.resultReady(payloadJson)
      return "ok"
    }

    function state(): string {
      return root.panelOpen ? "open" : "closed"
    }

    function ping(): string {
      return "ok"
    }
  }
}
