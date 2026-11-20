import QtQuick
import QtQuick.Layouts

// panacea-local (portal-patch v53): the collapsed island's status toasts (Bluetooth device,
// Wi-Fi network, charger) drawn with the kit: bare Phosphor icons (no glyph fonts, no icon
// in a circle), the kit's type roles, white for state and the one red only for trouble.
// Replaces Panacea's btCapsule / wifiCapsule / acCapsule (hidden by the patcher).
Item {
    id: tt
    property var sys
    readonly property var t: sys.pk
    readonly property bool blocked: sys.recPickActive || sys.voxActive

    // a level ring (battery, signal): track + white arc, red when low; the number inside
    // icon, a caption over a name, then (optional) something on the right
    // ---- Bluetooth device connected / disconnected / low battery
    PkToastLine {
        sys: tt.sys
        visible: tt.sys.btToastActive && !tt.blocked
        readonly property string kind: tt.sys.btToastType
        icon: tt.sys.btToastDisconnected ? "bluetooth-slash"
            : kind === "earbuds" ? "headphones" : kind === "mouse" ? "mouse"
            : kind === "keyboard" ? "keyboard" : kind === "gamepad" ? "game-controller"
            : kind === "phone" ? "device-mobile" : kind === "speaker" ? "speaker-high"
            : kind === "watch" ? "watch" : "bluetooth"
        iconFilled: !tt.sys.btToastDisconnected
        bad: tt.sys.btToastDisconnected || tt.sys.btToastLowBatt
        caption: tt.sys.btToastLowBatt ? tt.sys.tr("Низкий заряд батареи")
               : tt.sys.btToastDisconnected ? tt.sys.tr("Отключено") : tt.sys.tr("Подключено")
        name: tt.sys.btToastName
        PkRing {
            sys: tt.sys
            visible: !tt.sys.btToastDisconnected && tt.sys.btConnectedBattery >= 0
            active: tt.sys.btToastActive
            level: Math.max(0, tt.sys.btConnectedBattery) / 100
            low: tt.sys.btConnectedBattery >= 0 && tt.sys.btConnectedBattery <= 20
        }
    }

    // ---- Wi-Fi network joined / lost
    PkToastLine {
        id: wifiLine
        sys: tt.sys
        visible: tt.sys.wifiToastActive && !tt.blocked
        readonly property int q: tt.sys.wifiToastQuality
        icon: tt.sys.wifiToastDisconnected ? "wifi-slash" : q > 66 ? "wifi-high" : q > 33 ? "wifi-medium" : "wifi-low"
        iconFilled: !tt.sys.wifiToastDisconnected
        bad: tt.sys.wifiToastDisconnected
        caption: tt.sys.wifiToastDisconnected ? tt.sys.tr("Отключено") : tt.sys.tr("Подключено")
        name: tt.sys.wifiToastSsid
        PkRing {
            sys: tt.sys
            visible: !tt.sys.wifiToastDisconnected && wifiLine.q >= 0
            active: tt.sys.wifiToastActive
            level: Math.max(0, wifiLine.q) / 100
            low: wifiLine.q >= 0 && wifiLine.q <= 25
        }
    }

    // ---- charger plugged in / battery low: one line, the percentage in dot-matrix-like weight
    RowLayout {
        readonly property bool low: tt.sys.acToastKind === "lowbatt"
        anchors.centerIn: parent
        spacing: tt.t.s2
        visible: tt.sys.acToastActive && !tt.blocked
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: tt.t.dFast } }
        PkIcon { sys: tt.sys; Layout.alignment: Qt.AlignVCenter; filled: true; size: tt.t.iMd
                 name: parent.low ? "battery-warning" : "lightning"
                 color: parent.low ? tt.t.accentText : tt.t.fg }
        Text { Layout.alignment: Qt.AlignVCenter
               text: parent.low ? tt.sys.tr("Низкий заряд батареи") : tt.sys.tr("Заряжается")
               color: parent.low ? tt.t.accentText : tt.t.fg
               font { family: tt.t.font; pixelSize: tt.t.tEmph; weight: Font.DemiBold } }
        Text { Layout.alignment: Qt.AlignVCenter
               text: tt.sys.batteryPct + "%"
               color: parent.low ? tt.t.accentText : tt.t.soft
               font { family: tt.t.font; pixelSize: tt.t.tEmph; weight: Font.DemiBold } }
    }
}
