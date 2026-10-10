import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless half of the plugin. It remembers the state of the latest request the
// panel handled and exposes it over IPC, which is handy for scripts and
// debugging:
//   omarchy-shell translate-service last
// Only the state and the request id are exposed: any local client can call this
// target, so the source text and the translation must never pass through it.
// The panel owns the `translate` IPC target the command talks to, so nothing
// here is required for translating.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  property string lastPayload: ""

  IpcHandler {
    target: "translate-service"

    function last(): string {
      var p = null
      try {
        p = JSON.parse(root.lastPayload)
      } catch (e) {
        p = null
      }
      return JSON.stringify({
        state: p && typeof p.state === "string" ? p.state : "",
        request_id: p && typeof p.request_id === "string" ? p.request_id : ""
      })
    }

    function ping(): string {
      return "ok"
    }
  }
}
