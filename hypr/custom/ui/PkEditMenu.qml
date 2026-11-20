import QtQuick
import QtQuick.Controls

// Panacea kit - the right-click menu for text, in the kit's look (Qt's own falls back to a grey
// desktop style). Use: TextArea { ContextMenu.menu: PkEditMenu { sys: ...; target: <the text item> } }
// Works with TextEdit, TextArea, TextInput and TextField.
Menu {
    id: m
    property var sys
    readonly property var t: sys.pk
    property var target
    readonly property bool hasSel: !!target && target.selectionStart !== target.selectionEnd
    readonly property bool editable: !!target && !target.readOnly

    popupType: Popup.Item          // inside the island's own window, never a separate one
    padding: 6
    margins: 8
    implicitWidth: 210
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: m.t.dFast } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: m.t.dFast } }
    background: Rectangle {
        implicitWidth: 210
        radius: m.t.rControl + 4
        color: m.t.raised
        border.width: 1; border.color: m.t.veil(0.08)
    }
    delegate: MenuItem {
        id: mi
        implicitHeight: 32
        padding: 0
        contentItem: Item {
            Text {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: mi.text
                color: mi.enabled ? m.t.fg : m.t.faint
                font { family: m.t.font; pixelSize: m.t.tLabel }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                text: mi.action ? mi.action.objectName : ""      // the shortcut, as a hint only
                color: m.t.faint
                font { family: m.t.font; pixelSize: m.t.tCaption }
            }
        }
        background: Rectangle {
            radius: m.t.rSmall
            color: mi.highlighted && mi.enabled ? m.t.selected : "transparent"
        }
    }

    Action { text: "Undo"; objectName: "Ctrl+Z"; enabled: m.editable && m.target.canUndo; onTriggered: m.target.undo() }
    Action { text: "Redo"; objectName: "Ctrl+Shift+Z"; enabled: m.editable && m.target.canRedo; onTriggered: m.target.redo() }
    MenuSeparator { padding: 4; contentItem: Rectangle { implicitHeight: 1; color: m.t.veil(0.1) } }
    Action { text: "Cut"; objectName: "Ctrl+X"; enabled: m.editable && m.hasSel; onTriggered: m.target.cut() }
    Action { text: "Copy"; objectName: "Ctrl+C"; enabled: m.hasSel; onTriggered: m.target.copy() }
    Action { text: "Paste"; objectName: "Ctrl+V"; enabled: m.editable && m.target.canPaste; onTriggered: m.target.paste() }
    Action { text: "Delete"; objectName: "Del"; enabled: m.editable && m.hasSel
             onTriggered: m.target.remove(m.target.selectionStart, m.target.selectionEnd) }
    MenuSeparator { padding: 4; contentItem: Rectangle { implicitHeight: 1; color: m.t.veil(0.1) } }
    Action { text: "Select all"; objectName: "Ctrl+A"; enabled: !!m.target && m.target.length > 0; onTriggered: m.target.selectAll() }
}
