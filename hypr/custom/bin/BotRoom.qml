import QtQuick
import QtQuick.Layouts

// written by portal-patch.py (panacea-island) - a boopis team room (Group Chat: two to six bots
// who all read the thread), laid out like the island's other chats (BotChat, the Claude chat):
// a 30 px header (‹, the room, its members), the thread (yours in a bubble; each bot under its orb
// and name, "→ nina" when it talks to another bot, @names in white; rounds as quiet separators),
// who's working now, "Continue" when the room waits for you, and the same message box with an
// @name picker (Up/Down, Tab or Enter to complete, Esc to dismiss). Writing without an @name asks
// everyone. Data: sys.bots.room ({id, name, members, working, log, round?, waiting?}).
Item {
    id: rm
    property var sys
    readonly property var t: sys.pk
    readonly property var link: sys.bots
    readonly property var room: link.room
    signal back()
    readonly property real islandR: sys.cfg.islandRadius > 0 ? sys.cfg.islandRadius : 26
    readonly property real boxR: Math.max(14, islandR - 6)
    readonly property real rInner: Math.max(8, boxR - 6)
    readonly property var members: room ? room.members || [] : []
    readonly property var working: room ? room.working || [] : []
    readonly property var log: room ? room.log || [] : []

    width: 400
    implicitHeight: 520
    Component.onCompleted: { sys.botsChatOpen = true; box.input.forceActiveFocus(); }
    Component.onDestruction: sys.botsChatOpen = false

    function nameOf(id) { var b = link.bot(id); return b ? b.name : id; }
    function nameList(ids) {
        var n = ids.map(nameOf);
        return n.length < 2 ? n.join("") : n.slice(0, -1).join(", ") + " and " + n[n.length - 1];
    }
    // the other members a message speaks to
    function mentions(text, who) {
        var out = [], re = /@([\w-]+)/g, m;
        while ((m = re.exec(text)) !== null) {
            var id = m[1].toLowerCase();
            if (members.indexOf(id) >= 0 && id !== who && out.indexOf(id) < 0) out.push(id);
        }
        return out;
    }
    function marked(text) { return text.replace(/(^|[^\w`*])@([\w-]+)/g, function (all, pre, n) { return members.indexOf(n.toLowerCase()) >= 0 ? pre + "**@" + n + "**" : all; }); }

    // ---- the @name picker
    property int pickIndex: 0
    property string pickDismissed: ""
    readonly property string pickQuery: {
        var tx = box.text, pos = box.input.cursorPosition, pre = tx.slice(0, pos);
        var m = /(^|\s)@([\w-]*)$/.exec(pre);
        return m && box.text !== pickDismissed ? m[2].toLowerCase() : "\u0000";
    }
    readonly property var picks: pickQuery === "\u0000" ? [] : members.filter(function (id) {
        return id.indexOf(pickQuery) === 0 || rm.nameOf(id).toLowerCase().indexOf(pickQuery) === 0; })
    readonly property bool pickerShown: picks.length > 0
    onPicksChanged: pickIndex = Math.min(pickIndex, Math.max(0, picks.length - 1))
    function complete() {
        var id = picks[pickIndex]; if (!id) return;
        var tx = box.text, pos = box.input.cursorPosition, pre = tx.slice(0, pos);
        var at = pre.lastIndexOf("@");
        box.text = tx.slice(0, at) + "@" + id + " " + tx.slice(pos);
        box.input.cursorPosition = at + id.length + 2;
    }
    function keyHook(e) {
        if (!pickerShown) return false;
        if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) { pickIndex = (pickIndex + (e.key === Qt.Key_Down ? 1 : -1) + picks.length) % picks.length; return true; }
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { complete(); return true; }
        if (e.key === Qt.Key_Escape) { pickDismissed = box.text; return true; }
        return false;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: -8
        spacing: 10

        // ‹  room  · who's working                       member orbs
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 6
            PkIconButton { sys: rm.sys; icon: "caret-left"; size: 16; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: -7
                           onClicked: rm.back() }
            Text { Layout.alignment: Qt.AlignVCenter; text: rm.room ? rm.room.name : ""
                   color: rm.sys.colFg; font { family: rm.sys.fontBody; pixelSize: 13; bold: true } }
            Text { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: 4; elide: Text.ElideRight
                   text: rm.working.length ? rm.nameList(rm.working) + (rm.working.length > 1 ? " are" : " is") + " working"
                                           : rm.members.length + " bots" + (rm.room && rm.room.round ? " · round " + rm.room.round : "")
                   color: rm.sys.colMuted; font { family: rm.sys.fontBody; pixelSize: 11 } }
            Row {
                Layout.alignment: Qt.AlignVCenter; spacing: -4
                Repeater { model: rm.members
                    Item { required property var modelData
                           readonly property var b: rm.link.bot(modelData)
                           width: 22; height: 22
                        Rectangle { anchors.fill: parent; radius: 11; color: "#000" }
                        BotOrb { instantBot: true; anchors.centerIn: parent; size: 18; store: rm.sys.orbs; clock: rm.sys.clock
                                 botId: parent.modelData; shape: parent.b ? parent.b.shape : "circle"; color: parent.b ? parent.b.color : "#a6a6ab"
                                 reaction: rm.working.indexOf(parent.modelData) >= 0 ? "working" : parent.b ? parent.b.reaction : "idle" }
                        Rectangle { visible: !!(parent.b && parent.b.attention); width: 7; height: 7; radius: 3.5; color: rm.t.accent
                                    anchors.right: parent.right; anchors.top: parent.top } } }
            }
        }

        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: col.height
            boundsBehavior: Flickable.StopAtBounds
            property real lastH: 0
            onContentHeightChanged: {
                if (contentY >= lastH - height - 40) contentY = Math.max(0, contentHeight - height);
                lastH = contentHeight;
            }
            Column {
                id: col
                width: scroll.width
                spacing: 16
                Repeater {
                    model: rm.log
                    delegate: Column {
                        id: msg
                        required property var modelData
                        required property int index
                        readonly property bool mine: modelData.who === "you"
                        readonly property var prev: index > 0 ? rm.log[index - 1] : null
                        readonly property bool newRound: !!modelData.round && (!prev || prev.round !== modelData.round)
                        readonly property var to: mine ? [] : rm.mentions(String(modelData.text || ""), modelData.who)
                        readonly property var b: mine ? null : rm.link.bot(modelData.who)
                        width: col.width; spacing: 10
                        // a new round: a quiet line across
                        Item {
                            visible: msg.newRound
                            width: parent.width; height: 14
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: rm.t.hairline || Qt.rgba(1, 1, 1, 0.08) }
                            Rectangle { anchors.centerIn: parent; width: roundT.implicitWidth + 16; height: 14; color: "#000" }
                            Text { id: roundT; anchors.centerIn: parent; text: "Round " + msg.modelData.round
                                   color: rm.sys.colMuted; font { family: rm.sys.fontBody; pixelSize: 11 } }
                        }
                        // yours
                        Item {
                            visible: msg.mine
                            width: parent.width; height: visible ? bubble.height : 0
                            Rectangle {
                                id: bubble
                                anchors.right: parent.right
                                width: message.width + 28; height: message.implicitHeight + 20
                                radius: rm.boxR; color: Qt.rgba(1, 1, 1, 0.1)
                                Text { id: message; x: 14; y: 10
                                       width: Math.min(implicitWidth, msg.width * 0.78 - 28)
                                       text: msg.mine ? String(msg.modelData.text || "") : ""; color: rm.sys.colFg; wrapMode: Text.Wrap
                                       textFormat: Text.PlainText; lineHeight: 1.15; font { family: rm.sys.fontBody; pixelSize: 13 } }
                            }
                        }
                        // a bot's: its orb, name (→ who it talks to), the formatted text
                        Item {
                            visible: !msg.mine
                            width: parent.width; height: visible ? Math.max(22, botCol.height) : 0
                            BotOrb { instantBot: true; y: 0; size: 20; store: rm.sys.orbs; clock: rm.sys.clock
                                     botId: msg.modelData.who; shape: msg.b ? msg.b.shape : "circle"; color: msg.b ? msg.b.color : "#a6a6ab"; reaction: "idle" }
                            Column {
                                id: botCol
                                x: 30; width: parent.width - 30; spacing: 4
                                Row {
                                    spacing: 6
                                    Text { text: msg.b ? msg.b.name : String(msg.modelData.who); color: rm.sys.colFg
                                           font { family: rm.sys.fontBody; pixelSize: 12; bold: true } }
                                    Text { visible: msg.to.length > 0; text: "→ " + rm.nameList(msg.to); color: rm.sys.colMuted
                                           font { family: rm.sys.fontBody; pixelSize: 12 } }
                                }
                                PanaceaClaudeText { width: parent.width; sys: rm.sys; r: rm.rInner
                                                    text: msg.mine ? "" : rm.marked(String(msg.modelData.text || "")) }
                            }
                        }
                    }
                }
                // who's working now
                Row {
                    visible: rm.working.length > 0
                    spacing: 10
                    Row { spacing: -4; anchors.verticalCenter: parent.verticalCenter
                        Repeater { model: rm.working
                            BotOrb { instantBot: true; required property var modelData; readonly property var b: rm.link.bot(modelData)
                                     size: 20; store: rm.sys.orbs; clock: rm.sys.clock
                                     botId: modelData; shape: b ? b.shape : "circle"; color: b ? b.color : "#a6a6ab"; reaction: "working" } } }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: rm.nameList(rm.working) + (rm.working.length > 1 ? " are" : " is") + " replying"
                           color: rm.sys.colMuted; font { pixelSize: 12; family: rm.sys.fontBody } }
                }
            }
        }

        // the room waits for you after a round: carry on, or say something
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: -3; Layout.rightMargin: -3
            visible: !!(rm.room && rm.room.waiting) && rm.working.length === 0
            Layout.preferredHeight: 48
            radius: rm.boxR
            color: Qt.rgba(1, 1, 1, 0.055)
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 7; spacing: 6
                Text { Layout.fillWidth: true; elide: Text.ElideRight
                       text: rm.room && rm.room.round ? "Round " + rm.room.round + " done · your turn" : "Your turn"
                       color: rm.sys.colMuted; font { pixelSize: 12; family: rm.sys.fontBody } }
                Rectangle {
                    Layout.preferredWidth: 90; Layout.preferredHeight: 32; radius: rm.rInner
                    color: contMa.pressed ? Qt.rgba(1, 1, 1, 0.8) : rm.sys.colFg
                    Text { anchors.centerIn: parent; text: "Continue"; color: rm.sys.colBg; font { pixelSize: 12; bold: true; family: rm.sys.fontBody } }
                    MouseArea { id: contMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: rm.link.roomSend(rm.room.id, "continue") }
                }
            }
        }

        // @name picker, as the Claude chat's / command picker
        Rectangle {
            id: picker
            Layout.fillWidth: true
            Layout.leftMargin: -3; Layout.rightMargin: -3
            visible: rm.pickerShown
            readonly property real inset: Math.max(4, rm.boxR - 12)
            Layout.preferredHeight: Math.min(rm.picks.length, 4) * 28 + 2 * inset
            radius: rm.boxR
            color: Qt.tint(rm.sys.colBg, Qt.rgba(1, 1, 1, 0.07))
            ListView {
                id: pickList
                anchors.fill: parent; anchors.margins: picker.inset; clip: true
                model: rm.picks
                currentIndex: rm.pickIndex
                highlightMoveDuration: 90; highlightMoveVelocity: -1
                highlightResizeDuration: 0; highlightResizeVelocity: -1
                boundsBehavior: Flickable.StopAtBounds
                highlight: Rectangle { width: pickList.width; height: 28; radius: 14; color: Qt.rgba(1, 1, 1, 0.08) }
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property var b: rm.link.bot(modelData)
                    width: pickList.width; height: 28
                    BotOrb { instantBot: true; x: 8; anchors.verticalCenter: parent.verticalCenter; size: 18; store: rm.sys.orbs
                             botId: parent.modelData; shape: parent.b ? parent.b.shape : "circle"; color: parent.b ? parent.b.color : "#a6a6ab"; reaction: "idle" }
                    Text { id: pickName; x: 34; anchors.verticalCenter: parent.verticalCenter
                           text: "@" + parent.modelData; color: rm.sys.colFg; font { family: rm.sys.fontFam; pixelSize: 11; bold: true } }
                    Text { anchors.left: pickName.right; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
                           anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                           text: parent.b ? parent.b.role : ""; color: rm.sys.colMuted; font { pixelSize: 11; family: rm.sys.fontBody } }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered: rm.pickIndex = index
                                onClicked: { rm.pickIndex = index; rm.complete(); box.input.forceActiveFocus(); } }
                }
            }
        }

        BotChatBox {
            id: box
            sys: rm.sys
            Layout.fillWidth: true
            Layout.leftMargin: -3; Layout.rightMargin: -3
            Layout.preferredHeight: implicitHeight
            placeholder: "Message the team, @ for one bot"
            busy: rm.working.length > 0
            canStop: false
            keyHook: function (e) { return rm.keyHook(e); }
            onSend: text => { if (rm.room) rm.link.roomSend(rm.room.id, text); }
            onEscaped: rm.back()
        }
    }

    // a room with nothing said yet
    Column {
        anchors.centerIn: parent
        width: parent.width - 60
        spacing: 12
        visible: rm.log.length === 0 && rm.working.length === 0
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: -8
            Repeater { model: rm.members
                Item { required property var modelData; readonly property var b: rm.link.bot(modelData); width: 44; height: 44
                    Rectangle { anchors.fill: parent; radius: 22; color: "#000" }
                    BotOrb { instantBot: true; anchors.centerIn: parent; size: 40; store: rm.sys.orbs; clock: rm.sys.clock; alive: 0
                             botId: parent.modelData; shape: parent.b ? parent.b.shape : "circle"; color: parent.b ? parent.b.color : "#a6a6ab"; reaction: "idle" } } }
        }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: rm.room ? rm.room.name : ""
               color: rm.sys.colFg; font { family: rm.sys.fontDisplay || rm.sys.fontBody; pixelSize: 19; bold: true } }
    }
}
