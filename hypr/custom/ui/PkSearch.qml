import QtQuick

// Panacea kit - a search pill: magnifier, the field, a clear button once there's text.
Rectangle {
    id: se
    property var sys
    readonly property var t: sys.pk
    property alias text: input.text
    property alias input: input
    property string placeholder: "Search"
    signal accepted()
    implicitHeight: 34; implicitWidth: 240
    radius: height / 2
    color: input.activeFocus ? t.veil(0.095) : t.surface
    Behavior on color { ColorAnimation { duration: se.t.dFast } }
    PkIcon { id: sIcon; sys: se.sys; x: 12; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; size: 16
             color: input.activeFocus ? se.t.fg : se.t.muted }
    TextInput {
        id: input
        x: 36; width: parent.width - x - 34; anchors.verticalCenter: parent.verticalCenter
        color: se.t.fg; selectionColor: se.t.veil(0.25); selectedTextColor: se.t.fg
        selectByMouse: true; clip: true
        font { family: se.t.font; pixelSize: se.t.tLabel + 1 }
        onAccepted: se.accepted()
        PkText { sys: se.sys; visible: !input.text && !input.preeditText; text: se.placeholder; color: se.t.faint
                 font.pixelSize: se.t.tLabel + 1; anchors.verticalCenter: parent.verticalCenter }
    }
    PkIconButton { sys: se.sys; visible: input.text !== ""; icon: "x"; size: 13
                   anchors.right: parent.right; anchors.rightMargin: 3; anchors.verticalCenter: parent.verticalCenter
                   onClicked: { input.text = ""; input.forceActiveFocus(); } }
}
