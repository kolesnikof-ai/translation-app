import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Multi-line input with the shell's field styling. Enter submits, Shift+Enter
// inserts a line break. Esc is left to the parent so the panel can close.
TextArea {
  id: root

  property color foreground: Commons.Color.popups.text
  property color accent: Commons.Color.accent
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property int minimumLines: 3

  signal submitted(string text)

  readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), root.foreground, root.accent)
  readonly property real _lineHeight: Math.ceil(Style.font.body * 1.4)

  wrapMode: TextArea.Wrap
  selectByMouse: true
  placeholderText: "Type text and press Enter to translate"
  placeholderTextColor: Qt.darker(foreground, 1.6)
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: foreground
  selectionColor: Style.selectionFillFor(foreground, accent)
  selectedTextColor: foreground

  leftPadding: horizontalPadding + Border.left(_borderSpec)
  rightPadding: horizontalPadding + Border.right(_borderSpec)
  topPadding: verticalPadding + Border.top(_borderSpec)
  bottomPadding: verticalPadding + Border.bottom(_borderSpec)

  implicitHeight: Math.max(contentHeight, minimumLines * _lineHeight) + topPadding + bottomPadding

  background: BorderSurface {
    color: Style.controlFill(root.activeFocus, root.hovered, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }

  Keys.onPressed: function(event) {
    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return

    if (event.modifiers & Qt.ShiftModifier) {
      root.insert(root.cursorPosition, "\n")
    } else if (root.text.trim() !== "") {
      root.submitted(root.text)
    }
    event.accepted = true
  }
}
