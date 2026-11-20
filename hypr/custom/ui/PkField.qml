import QtQuick

// Panacea kit - a text field: a pill like PkSearch without the glass. `password` hides the text.
Rectangle {
    id: fd
    property var sys
    readonly property var t: sys.pk
    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property bool password: false
    signal accepted()
    implicitHeight: 38; implicitWidth: 240
    radius: height / 2
    color: input.activeFocus ? t.veil(0.11) : t.surface
    Behavior on color { ColorAnimation { duration: fd.t.dFast } }
    function focusIn() { input.forceActiveFocus(); }
    TextInput {
        id: input
        x: 16; width: parent.width - 32; anchors.verticalCenter: parent.verticalCenter
        color: fd.t.fg; selectionColor: fd.t.veil(0.25); selectedTextColor: fd.t.fg
        selectByMouse: true; clip: true
        echoMode: fd.password ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        font { family: fd.t.font; pixelSize: fd.t.tBody }
        onAccepted: fd.accepted()
        PkText { sys: fd.sys; visible: !input.text && !input.preeditText; text: fd.placeholder; color: fd.t.faint
                 anchors.verticalCenter: parent.verticalCenter }
    }
}
