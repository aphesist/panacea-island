import QtQuick
import QtQuick.Layouts

// written by portal-patch.py (panacea-island) - talking to one boopis bot from the island, built
// like the island's Claude chat (ChatView as patched by panacea-claude-bridge's chat-patch.py) and
// with its parts: your messages in a bubble on the right, the bot's replies as formatted text
// (PanaceaClaudeText), its tool steps and approval as timeline rows (PanaceaClaudeStep), the same
// message box (Enter sends, Shift+Enter a new line, send / stop button). A slim header names the
// bot (‹ goes back, Esc too); while it works its orb and a word sit under the thread.
Item {
    id: ch
    property var sys
    property var args: []
    readonly property var t: sys.pk
    readonly property var link: sys.bots
    property string botId: args[0] || link.current
    readonly property var bot: link.bot(botId)
    readonly property var thread: link.threads[botId] || []
    readonly property var steps: link.steps ? (link.steps[botId] || []) : []   // the turn in progress
    signal back()

    // the Claude chat's radius system, from the island's corner
    readonly property real islandR: sys.cfg.islandRadius > 0 ? sys.cfg.islandRadius : 26
    readonly property real boxR: Math.max(14, islandR - 6)
    readonly property real rInner: Math.max(8, boxR - 6)

    readonly property var pending: {
        var l = link.approvals || [];
        for (var i = 0; i < l.length; i++) if (l[i].bot === botId) return l[i];
        return null;
    }
    readonly property bool streaming: thread.length > 0 && !thread[thread.length - 1].done && thread[thread.length - 1].who !== "you"
    readonly property bool waitingReply: thread.length > 0 && thread[thread.length - 1].who === "you"
    readonly property bool busy: !!pending || streaming || waitingReply || steps.length > 0
        || (bot && ["thinking", "working", "compute", "speaking"].indexOf(bot.reaction) >= 0)
    readonly property string mood: pending ? "waiting" : (steps.length && !steps[steps.length - 1].done) || (bot && bot.reaction === "working") ? "working" : "thinking"

    width: 400
    implicitHeight: 520                          // the Claude chat's
    Keys.onEscapePressed: back()
    onBotIdChanged: if (botId) link.current = botId
    Component.onCompleted: {
        sys.botsChatOpen = true;
        if (sys.botsDraft) { box.text = sys.botsDraft; sys.botsDraft = ""; }   // talk mode on the stage: the dictated text, not sent
        box.input.forceActiveFocus();
        box.input.cursorPosition = box.text.length;
    }
    Component.onDestruction: sys.botsChatOpen = false
    // the orb the Bots tab's flying hero lands on: the big one while nothing's been said, else the header's
    readonly property Item hero: thread.length === 0 && !busy ? emptyOrb : headOrb
    property bool heroHidden: false
    // the header's orb: gone at once when a flight starts, fades in after one lands elsewhere
    property real headShown: heroHidden ? 0 : 1
    onHeroHiddenChanged: {
        headIn.stop();
        if (heroHidden) headShown = 0;
        else if (hero === headOrb) headShown = 1;
        else headIn.start();
    }
    NumberAnimation { id: headIn; target: ch; property: "headShown"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }

    ColumnLayout {
        // exactly the Claude chat's: the island gives the page its inset; the box sits 15 px from the bottom
        anchors.fill: parent
        anchors.bottomMargin: -8
        spacing: 10

        // ‹  orb  name  role…            state   (one 30 px row, like the Claude chat's model switcher)
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 6
            PkIconButton { sys: ch.sys; icon: "caret-left"; size: 16; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: -7   // the glyph on the inset
                           onClicked: ch.back() }
            BotOrb { instantBot: true; id: headOrb; Layout.alignment: Qt.AlignVCenter; size: 20; store: ch.sys.orbs; clock: ch.sys.clock
                     // one orb of this bot on screen while it flies: the header's waits, and fades in once it lands
                     opacity: ch.headShown
                     botId: ch.botId; shape: ch.bot ? ch.bot.shape : "circle"; color: ch.bot ? ch.bot.color : "#a6a6ab"
                     reaction: ch.bot ? ch.bot.reaction : "idle" }
            Text { Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: 4; text: ch.bot ? ch.bot.name : ""
                   color: ch.sys.colFg; font { family: ch.sys.fontBody; pixelSize: 13; bold: true } }
            Text { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: 4
                   text: ch.bot ? ch.bot.role : ""; elide: Text.ElideRight; maximumLineCount: 1
                   color: ch.sys.colMuted; font { family: ch.sys.fontBody; pixelSize: 11 } }
            Text { Layout.alignment: Qt.AlignVCenter; visible: text !== ""
                   text: ch.bot ? (ch.bot.attention ? "needs you" : ch.bot.word) : ""
                   color: ch.bot && ch.bot.attention ? ch.t.accentText : ch.sys.colMuted
                   font { family: ch.sys.fontBody; pixelSize: 11 } }
        }

        // the thread
        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: col.height
            boundsBehavior: Flickable.StopAtBounds
            // follows the conversation down while you're at the bottom
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
                    model: ch.thread
                    delegate: Column {
                        id: msg
                        required property var modelData
                        required property int index
                        readonly property bool mine: modelData.who === "you"
                        readonly property bool live: !mine && !modelData.done && index === ch.thread.length - 1
                        // the steps it took for this reply (kept on the message), or the ones running now
                        readonly property var rows: mine ? [] : live ? ch.steps : (modelData.steps || [])
                        width: col.width; spacing: 10
                        Column {
                            visible: msg.rows.length > 0
                            width: msg.width; spacing: 0
                            Repeater { model: msg.rows
                                       delegate: PanaceaClaudeStep { required property var modelData; required property int index
                                           width: msg.width; sys: ch.sys; boxR: ch.boxR; rInner: ch.rInner
                                           prevKind: index > 0 ? "tool" : ""
                                           kind: "tool"; text: String(modelData.text || ""); running: !modelData.done } }
                        }
                        Item {
                            id: body
                            readonly property string content: String(msg.modelData.text || "")
                            visible: content.length > 0
                            width: parent.width
                            height: msg.mine ? bubble.height : reply.height
                            Rectangle {
                                id: bubble
                                visible: msg.mine
                                anchors.right: parent.right
                                width: message.width + 28; height: message.implicitHeight + 20
                                radius: ch.boxR
                                color: Qt.rgba(1, 1, 1, 0.1)
                                Text { id: message; x: 14; y: 10
                                       width: Math.min(implicitWidth, msg.width * 0.78 - 28)
                                       text: msg.mine ? body.content : ""; color: ch.sys.colFg; wrapMode: Text.Wrap
                                       textFormat: Text.PlainText; lineHeight: 1.15; font { family: ch.sys.fontBody; pixelSize: 13 } }
                            }
                            PanaceaClaudeText {
                                id: reply
                                visible: !msg.mine
                                width: parent.width
                                sys: ch.sys; r: ch.rInner
                                text: msg.mine ? "" : body.content
                            }
                        }
                    }
                }
                // steps before the first word of the reply arrives
                Column {
                    visible: ch.waitingReply && ch.steps.length > 0
                    width: col.width; spacing: 0
                    Repeater { model: ch.waitingReply ? ch.steps : []
                               delegate: PanaceaClaudeStep { required property var modelData; required property int index
                                   width: col.width; sys: ch.sys; boxR: ch.boxR; rInner: ch.rInner
                                   prevKind: index > 0 ? "tool" : ""
                                   kind: "tool"; text: String(modelData.text || ""); running: !modelData.done } }
                }
                // what it asks before it acts: the kit's approval card (the Claude chat's, with the bot's orb)
                BotApproval {
                    visible: !!ch.pending
                    width: col.width
                    sys: ch.sys
                    bot: ch.bot
                    command: ch.pending ? ch.pending.command : ""
                    why: ch.pending ? ch.pending.description : ""
                    origin: ch.bot ? ch.bot.name + (ch.bot.model ? " · " + ch.bot.model : "") : ""
                    timeout: ch.pending ? ch.pending.timeout : 0
                    onAnswered: choice => ch.link.approve(choice, ch.pending)
                }
                // while it works: its orb and a word, like the pixel Claude under Claude's steps
                Row {
                    visible: ch.busy
                    spacing: 10
                    BotOrb { instantBot: true; size: 20; store: ch.sys.orbs; clock: ch.sys.clock; anchors.verticalCenter: parent.verticalCenter
                             botId: ch.botId; shape: ch.bot ? ch.bot.shape : "circle"; color: ch.bot ? ch.bot.color : "#a6a6ab"
                             reaction: ch.mood === "waiting" ? "needs" : ch.mood }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: ({ thinking: "Thinking", working: "Working", waiting: "Waiting for you" })[ch.mood]
                           color: ch.sys.colMuted; font { pixelSize: 12; family: ch.sys.fontBody } }
                }
            }
        }

        BotChatBox {
            id: box
            sys: ch.sys
            Layout.fillWidth: true
            Layout.leftMargin: -3; Layout.rightMargin: -3   // 12 px from the island, like the bottom
            Layout.preferredHeight: implicitHeight
            placeholder: "Message " + (ch.bot ? ch.bot.name : "") + "…"
            busy: ch.busy
            canStop: ch.busy && !ch.pending
            onSend: text => ch.link.send(ch.botId, text)
            onStop: ch.link.interrupt(ch.botId)
            onEscaped: ch.back()
        }
    }

    // nothing said yet: the bot, big and alive, like the Claude chat's empty state
    Column {
        anchors.centerIn: parent
        width: parent.width - 60
        spacing: 8
        visible: ch.thread.length === 0 && !ch.busy
        BotOrb { instantBot: true; id: emptyOrb; anchors.horizontalCenter: parent.horizontalCenter; size: 72; store: ch.sys.orbs; clock: ch.sys.clock
                 opacity: ch.heroHidden && ch.hero === emptyOrb ? 0 : 1
                 botId: ch.botId; shape: ch.bot ? ch.bot.shape : "circle"; color: ch.bot ? ch.bot.color : "#a6a6ab"
                 reaction: ch.bot ? ch.bot.reaction : "idle" }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Talk to " + (ch.bot ? ch.bot.name : "")
               color: ch.sys.colFg; font { family: ch.sys.fontDisplay || ch.sys.fontBody; pixelSize: 19; bold: true } }
    }
}
