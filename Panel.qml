import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string payload: ""

  function open(payloadJson) {
    root.payload = payloadJson || "{}"
    root.opened = true
    if (root.service) root.service.panelOpen = true
  }

  function close() {
    root.opened = false
    if (root.service) root.service.panelOpen = false
  }

  OverlayWindow {
    shown: root.opened
    WlrLayershell.namespace: "omarchy-translate"

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      width: Style.space(480)
      height: Style.space(120)
      anchors.centerIn: parent
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.payload
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
