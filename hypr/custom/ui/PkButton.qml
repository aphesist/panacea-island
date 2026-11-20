import QtQuick

// Panacea kit - a pill button. primary: white (the one main action on a screen);
// secondary: a grey veil; ghost: bare until hovered; danger: red (confirming something
// destructive). Optional icon (Phosphor name). small: 28 high.
Rectangle {
    id: b
    property var sys
    readonly property var t: sys.pk
    property string text: ""
    property string icon: ""
    property url image: ""            // an image instead of an icon (e.g. the Claude logo)
    property string kind: "secondary"
    property bool small: false
    property bool enabled: true
    signal clicked()
    implicitHeight: small ? 28 : 34
    implicitWidth: row.implicitWidth + (small ? 22 : 30)
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    readonly property color ink: kind === "primary" ? t.onInk : t.fg
    color: kind === "primary" ? (ma.pressed ? Qt.darker(t.on, 1.12) : ma.containsMouse ? Qt.darker(t.on, 1.05) : t.on)
         : kind === "danger" ? (ma.pressed ? Qt.darker(t.accent, 1.2) : ma.containsMouse ? Qt.lighter(t.accent, 1.1) : t.accent)
         : kind === "ghost" ? (ma.pressed ? t.pressed : ma.containsMouse ? t.hover : "transparent")
         : (ma.pressed ? t.veil(0.2) : ma.containsMouse ? t.veil(0.15) : t.veil(0.1))
    Behavior on color { ColorAnimation { duration: b.t.dFast } }
    Row {
        id: row
        anchors.centerIn: parent; spacing: 6
        PkIcon { sys: b.sys; visible: b.icon !== "" && b.image == ""; name: b.icon; filled: true
                 size: b.small ? 14 : 16; color: b.ink; anchors.verticalCenter: parent.verticalCenter }
        Image { visible: b.image != ""; source: b.image; width: b.small ? 13 : 15; height: width
                sourceSize: Qt.size(60, 60); smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
        PkText { sys: b.sys; visible: b.text !== ""; text: b.text; color: b.ink; anchors.verticalCenter: parent.verticalCenter
                 font.pixelSize: b.small ? b.t.tCaption : b.t.tLabel; font.weight: Font.DemiBold }
    }
    MouseArea { id: ma; anchors.fill: parent; enabled: b.enabled; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
