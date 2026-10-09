import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless half of the plugin. It remembers the latest payload the panel
// displayed and exposes it over IPC, which is handy for scripts and debugging:
//   omarchy-shell translate-service last
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
      return root.lastPayload
    }

    function ping(): string {
      return "ok"
    }
  }
}
