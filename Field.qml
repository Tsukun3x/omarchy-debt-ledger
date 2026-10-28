import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string label: ""
  property string value: ""
  property string placeholder: ""
  readonly property bool activeEditor: input.activeFocus

  signal edited(string text)
  signal tabRequested(int direction)

  function focusEditor() {
    input.forceActiveFocus()
  }

  implicitHeight: Style.space(58)

  Column {
    anchors.fill: parent
    spacing: Style.space(4)

    Text {
      text: root.label
      color: Color.popups.text
      font.family: "monospace"
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }

    Rectangle {
      width: parent.width
      height: Style.space(34)
      color: Qt.alpha(Color.popups.text, 0.035)
      border.width: 1
      border.color: input.activeFocus ? Color.accent : Color.popups.border
      radius: 0

      TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        color: Color.popups.text
        selectionColor: Color.accent
        selectedTextColor: Color.popups.background
        cursorDelegate: Rectangle {
          width: 1
          color: Color.accent
        }
        font.family: "monospace"
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        clip: true
        onTextEdited: root.edited(text)
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
            event.accepted = true
          }
        }
      }

      Text {
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        verticalAlignment: Text.AlignVCenter
        text: root.placeholder
        color: Qt.alpha(Color.popups.text, 0.4)
        font.family: "monospace"
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        visible: input.text.length === 0 && !input.activeFocus
      }

      Connections {
        target: root
        function onValueChanged() {
          if (input.text !== root.value) input.text = root.value
        }
      }
    }
  }
}
