import QtQuick

// Panacea kit - a control tile (Wi-Fi, Bluetooth, VPN, Focus): icon at the top, title and
// state at the bottom. On: the whole tile turns white, ink black, the icon fills.
// Click toggles. With `hasPage`, only the icon toggles and the rest of the tile opens its page
// (`opened`), shown by a small caret; right-click or press-and-hold always opens it.
Rectangle {
    id: tl
    property var sys
    readonly property var t: sys.pk
    property string icon: ""
    property string title: ""
    property string sub: ""
    property bool on: false
    property bool hasPage: false
    signal toggled()
    signal opened()
    implicitWidth: 139; implicitHeight: 86
    radius: t.rSurface
    color: on ? (ma.pressed ? Qt.darker(t.on, 1.08) : t.on)
              : (ma.pressed ? t.veil(0.12) : ma.containsMouse ? t.veil(0.095) : t.surface)
    Behavior on color { ColorAnimation { duration: tl.t.dBase } }
    PkIcon { sys: tl.sys; x: 14; y: 14; name: tl.icon; filled: tl.on; size: tl.t.iLg; color: tl.on ? tl.t.onInk : tl.t.fg }
    PkIcon { sys: tl.sys; visible: tl.hasPage; anchors.right: parent.right; anchors.rightMargin: 12; y: 16
             name: "caret-right"; size: 13; color: tl.on ? tl.t.onSub : tl.t.faint }
    Column {
        x: 14; width: parent.width - 28
        anchors.bottom: parent.bottom; anchors.bottomMargin: 12
        spacing: 1
        PkText { sys: tl.sys; role: "label"; width: parent.width; text: tl.title; color: tl.on ? tl.t.onInk : tl.t.fg }
        PkText { sys: tl.sys; role: "sub"; width: parent.width; text: tl.sub; visible: text !== ""; color: tl.on ? tl.t.onSub : tl.t.muted }
    }
    MouseArea {
        id: ma
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            if (m.button === Qt.RightButton) tl.opened();
            else if (tl.hasPage && !(m.x < 52 && m.y < 52)) tl.opened();
            else tl.toggled();
        }
        onPressAndHold: tl.opened()
    }
}
