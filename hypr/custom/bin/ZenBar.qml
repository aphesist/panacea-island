import QtQuick
import QtQuick.Layouts
import Quickshell

// written by portal-patch.py (panacea-config) - Zen-only mode: while Zen is alone on the
// screen (floating windows aside), the collapsed island is Zen's address bar and Zen hides
// its own dock. Idle it is small: the site's icon and domain, as wide as they need (like
// the dock). Hovering anywhere on it grows a strip along the top with the island's tabs;
// the address opens the search (ZenSearchView) right there, middle click in a new tab.
// The address and icons come from panacea-dock.uc.js ($XDG_RUNTIME_DIR). Plain code, no AI.
Item {
    id: bar
    property var sys

    readonly property var tab: sys.zenTab || ({})
    readonly property bool web: /^https?:/.test(tab.url || "")
    readonly property string shown: web ? String(tab.host || tab.url).replace(/^www\d*\./, "") : ""   // without www. (as on the dock)
    readonly property bool hovered: hover.hovered

    readonly property int stripH: 34
    readonly property real idleW: Math.max(170, Math.min(sys.zenBarW, metrics.advanceWidth + (icon.visible ? 26 : 0) + 64))
    readonly property real hoverW: Math.max(idleW, Math.min(sys.zenBarW, Math.max(320, tabs.implicitWidth + 48)))
    implicitWidth: hovered ? hoverW : idleW
    implicitHeight: hovered ? sys.pillH + stripH : sys.pillH

    HoverHandler { id: hover }
    // clicks between the tabs and the address stop here: below them, the island's own handler
    // would take them (it opened the media page)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: mouse => mouse.accepted = true
    }

    TextMetrics {
        id: metrics
        font: label.font
        text: label.text
    }

    // ---------------------------------------------------------------- the island's tabs (hover)
    Row {
        id: tabs
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6
        // Shown only where the island already has room for it: the opacity follows the island's
        // animated size (laid out on it, see shell.qml), so no frame shows the strip cut by a corner.
        // `want` only says whether to show it at all; the geometry says how much.
        property real want: bar.hovered ? 1 : 0
        Behavior on want { NumberAnimation { duration: 120 } }
        readonly property real room: Math.max(0, Math.min(1, (bar.height - bar.sys.pillH) / bar.stripH))
                                   * Math.max(0, Math.min(1, (bar.width - tabs.implicitWidth - 12) / 36))
        opacity: want * room * room
        visible: opacity > 0.01

        Repeater {
            // the island's own tab icons: the filled house, Claude's logo, Zen's circles
            model: [{ page: "main", title: "Home", icon: 0xF02DC },
                    { page: "chat", title: "Claude", icon: 0, logo: "file://" + Quickshell.env("HOME") + "/.config/panacea-claude/claude-logo.svg" },
                    { page: "zentab", title: "Zen", icon: 0, logo: Qt.resolvedUrl("zen-logo.svg") }]
            delegate: Rectangle {
                id: tabBtn
                required property var modelData
                width: tabRow.implicitWidth + 22
                height: 26
                radius: 13
                color: tabMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                Behavior on color { ColorAnimation { duration: 120 } }
                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: 7
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !tabBtn.modelData.icon
                        width: 13; height: 13
                        source: tabBtn.modelData.logo || ""
                        sourceSize: Qt.size(52, 52)
                        smooth: true; mipmap: true
                        opacity: tabMa.containsMouse ? 1 : 0.6
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!tabBtn.modelData.icon
                        text: tabBtn.modelData.icon ? String.fromCodePoint(tabBtn.modelData.icon) : ""
                        color: tabMa.containsMouse ? bar.sys.colFg : bar.sys.colMuted
                        font { family: bar.sys.fontFam; pixelSize: 13 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabBtn.modelData.title
                        color: tabMa.containsMouse ? bar.sys.colFg : bar.sys.colMuted
                        font { family: bar.sys.fontFam; pixelSize: 11; bold: true }
                    }
                }
                MouseArea {
                    id: tabMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.sys.zenOpenIsland(tabBtn.modelData.page)
                }
            }
        }
    }

    // ---------------------------------------------------------------- the address
    Rectangle {
        id: field
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        anchors.bottomMargin: 5
        height: bar.sys.pillH - 10
        radius: height / 2
        color: fieldMa.containsMouse ? Qt.rgba(1, 1, 1, 0.085) : bar.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        Row {
            anchors.centerIn: parent
            spacing: 8
            Image {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                sourceSize: Qt.size(32, 32)
                smooth: true
                source: bar.web && bar.tab.icon ? "file://" + bar.tab.icon : ""
                visible: status === Image.Ready
            }
            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, field.width - 40 - (icon.visible ? 24 : 0))
                text: bar.shown || "Search or address"
                color: bar.shown ? bar.sys.colFg : bar.sys.colMuted
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font { family: bar.sys.fontFam; pixelSize: 13; bold: !!bar.shown }
            }
        }
        MouseArea {
            id: fieldMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.IBeamCursor
            onClicked: mouse => bar.sys.zenOpenSearch(mouse.button === Qt.MiddleButton)
        }
    }
}
