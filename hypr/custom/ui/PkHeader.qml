import QtQuick

// Panacea kit - a page header: back caret (sub-pages), a big title with an optional line
// under it, and whatever goes on the right (a switch, icon buttons, a Save button).
Item {
    id: hd
    property var sys
    readonly property var t: sys.pk
    property string title: ""
    property string sub: ""
    property bool back: false
    property bool dirty: false        // a white dot after the title (unsaved)
    default property alias actions: act.data
    signal backClicked()
    implicitWidth: 400; implicitHeight: sub !== "" ? 40 : 32
    PkIconButton { id: bk; sys: hd.sys; visible: hd.back; icon: "caret-left"; size: hd.t.iMd; x: -7
                   anchors.verticalCenter: parent.verticalCenter; onClicked: hd.backClicked() }
    Column {
        x: hd.back ? 30 : 0; width: parent.width - x - act.width - 10
        anchors.verticalCenter: parent.verticalCenter; spacing: 2
        Row {
            spacing: 8; width: parent.width
            PkText { sys: hd.sys; role: "title"; text: hd.title; width: Math.min(implicitWidth, parent.width - 16)
                     font.pixelSize: hd.sub !== "" ? 16 : hd.t.tTitle }
            Rectangle { visible: hd.dirty; width: 7; height: 7; radius: 3.5; color: hd.t.fg; anchors.verticalCenter: parent.verticalCenter }
        }
        PkText { sys: hd.sys; role: "sub"; visible: hd.sub !== ""; width: parent.width; text: hd.sub }
    }
    Row { id: act; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10 }
}
