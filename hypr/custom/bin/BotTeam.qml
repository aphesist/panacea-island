import QtQuick
import QtQuick.Layouts

// written by portal-patch.py (panacea-island) - the Bots tab's teams: pick a boopis room (Group
// Chat) - each with its members' orbs, who's working in it, its last line - then its chat
// (BotRoom). ‹ / Esc goes back: from a room to the list, from the list to the stage.
Item {
    id: tm
    property var sys
    property var args: []
    readonly property var t: sys.pk
    readonly property var link: sys.bots
    property string roomId: ""                    // the open room ("" = the list)
    signal back()
    width: 400
    implicitHeight: roomId ? 520 : list.implicitHeight
    focus: true
    Keys.onEscapePressed: goBack()
    function goBack() { if (roomId) { roomId = ""; tm.forceActiveFocus(); } else back(); }
    function open(id) { link.openRoom(id); roomId = id; }
    // the Bots tab's hero lands on the bot's own orb in the first room it's in (else the header's corner)
    property Item hero: null
    readonly property int firstRoomOf: { for (var i = 0; i < link.rooms.length; i++) if ((link.rooms[i].members || []).slice(0, 5).indexOf(link.current) >= 0) return i; return -1; }
    property bool heroHidden: false
    readonly property point heroSpot: Qt.point(0, 15)

    // ---- the list
    ColumnLayout {
        id: list
        visible: !tm.roomId
        width: parent.width
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 6
            PkIconButton { sys: tm.sys; icon: "caret-left"; size: 16; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: -7
                           onClicked: tm.back() }
            Text { Layout.alignment: Qt.AlignVCenter; text: "Teams"; color: tm.sys.colFg
                   font { family: tm.sys.fontBody; pixelSize: 13; bold: true } }
            Text { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: 4
                   text: tm.link.rooms.length + (tm.link.rooms.length === 1 ? " room" : " rooms"); color: tm.sys.colMuted
                   font { family: tm.sys.fontBody; pixelSize: 11 } }
        }
        Text {
            visible: tm.link.rooms.length === 0
            Layout.fillWidth: true; Layout.topMargin: 20; Layout.bottomMargin: 20
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "No team rooms yet. Make one in boopis (Group Chat) and it shows here."
            color: tm.sys.colMuted; font { family: tm.sys.fontBody; pixelSize: 12 }
        }
        Repeater {
            model: tm.link.rooms
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property var members: modelData.members || []
                readonly property var working: modelData.working || []
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: tm.t.rSurface
                color: rowMa.containsMouse ? tm.t.veil(0.1) : tm.t.surface
                Behavior on color { ColorAnimation { duration: tm.t.dFast } }
                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: tm.open(row.modelData.id) }
                Row {
                    id: orbs
                    x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: -8
                    Repeater { model: row.members.slice(0, 5)
                        Item { required property var modelData; readonly property var b: tm.link.bot(modelData); width: 30; height: 30
                            Rectangle { anchors.fill: parent; radius: 15; color: tm.t.surface }
                            BotOrb { instantBot: true; id: mo; anchors.centerIn: parent; size: 26; store: tm.sys.orbs; clock: tm.sys.clock
                                     readonly property bool isHero: tm.hero === mo
                                     opacity: isHero && tm.heroHidden ? 0 : 1
                                     Component.onCompleted: if (!tm.hero && parent.modelData === tm.link.current && row.index === tm.firstRoomOf) tm.hero = mo
                                     Component.onDestruction: if (tm.hero === mo) tm.hero = null
                                     botId: parent.modelData; shape: parent.b ? parent.b.shape : "circle"; color: parent.b ? parent.b.color : "#a6a6ab"
                                     reaction: row.working.indexOf(parent.modelData) >= 0 ? "working" : "idle" } } }
                }
                Column {
                    anchors.left: orbs.right; anchors.leftMargin: 12; anchors.right: chev.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter; spacing: 3
                    Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.name
                           color: tm.sys.colFg; font { family: tm.sys.fontBody; pixelSize: 13; bold: true } }
                    Text { width: parent.width; elide: Text.ElideRight
                           text: row.working.length ? row.working.map(function (i) { var b = tm.link.bot(i); return b ? b.name : i; }).join(", ") + " working"
                                                    : row.modelData.last ? row.modelData.last
                                                    : row.members.map(function (i) { var b = tm.link.bot(i); return b ? b.name : i; }).join(", ")
                           color: tm.sys.colMuted; font { family: tm.sys.fontBody; pixelSize: 11 } }
                }
                PkIcon { id: chev; sys: tm.sys; name: "caret-right"; size: 14; color: tm.t.muted
                         anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // ---- the room
    readonly property Item room: roomLd.item
    Loader {
        id: roomLd
        active: tm.roomId !== ""
        visible: active
        width: parent.width; height: 520
        sourceComponent: BotRoom { sys: tm.sys; onBack: tm.goBack() }
    }
}
