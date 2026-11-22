import QtQuick

// written by portal-patch.py (panacea-island) - the collapsed island while bots are around
// (sys.botsPillShown): BotsPill, and when a bot finishes a reply or asks before it acts, the
// island grows down and holds its card (BotCard / BotApproval). The island's own shape springs
// to implicitWidth/implicitHeight (like MpvBar); the card fades in with the room it has. A reply
// card folds back after a while unless you're on it; an approval stays until it's answered.
Item {
    id: isl
    property var sys
    readonly property var t: sys.pk
    readonly property var link: sys.bots
    property var shown: null                   // {kind: "reply"|"approval", data}
    readonly property bool cardOpen: shown !== null
    readonly property real cardW: 400
    readonly property int pillH: sys.pillH || 38

    implicitWidth: cardOpen ? cardW : pill.implicitWidth
    implicitHeight: cardOpen ? pillH + 8 + (ld.item ? ld.item.implicitHeight : 0) + 15 : pillH

    property var queue: []
    function push(kind, data) {
        if (kind === "reply" && shown && shown.kind === "reply" && shown.data.bot === data.bot) { shown = { kind: kind, data: data }; hold.restart(); return; }
        if (!shown) { shown = { kind: kind, data: data }; hold.restart(); }
        else queue = queue.concat([{ kind: kind, data: data }]);
    }
    function next() {
        if (queue.length) { shown = queue[0]; queue = queue.slice(1); hold.restart(); }
        else shown = null;
    }
    Connections { target: isl.link; function onCard(kind, data) { isl.push(kind, data); } }
    // an approval answered anywhere leaves the island
    Connections {
        target: isl.link
        function onApprovalsChanged() {
            if (isl.shown && isl.shown.kind === "approval"
                && !isl.link.approvals.some(function (a) { return a.id === isl.shown.data.id; })) isl.next();
            isl.queue = isl.queue.filter(function (q) { return q.kind !== "approval" || isl.link.approvals.some(function (a) { return a.id === q.data.id; }); });
        }
    }
    Timer { id: hold; interval: 9000
            onTriggered: { if (!isl.shown || isl.shown.kind !== "reply") return;
                           if (hov.hovered || (ld.item && ld.item.replying)) restart(); else isl.next(); } }
    HoverHandler { id: hov }

    BotsPill {
        id: pill
        sys: isl.sys
        width: parent.width; height: isl.pillH
        focusId: isl.shown ? isl.shown.data.bot : ""
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: isl.sys.botsOpen(isl.shown ? isl.shown.data.bot : (pill.lead ? pill.lead.id : ""), false) }
    }
    Loader {
        id: ld
        x: (isl.width - width) / 2; y: isl.pillH + 8; width: isl.cardW - 30
        active: isl.cardOpen
        sourceComponent: !isl.shown ? null : isl.shown.kind === "approval" ? approvalC : replyC
        readonly property real room: Math.max(0, Math.min(1, (isl.height - isl.pillH - 8) / Math.max(1, 0.6 * (item ? item.implicitHeight : 1))))
                                   * Math.max(0, Math.min(1, (isl.width - isl.cardW + 24) / 24))
        opacity: room * room
        visible: opacity > 0.01
        onLoaded: item.width = Qt.binding(function () { return ld.width; })
    }
    Component {
        id: replyC
        BotCard {
            sys: isl.sys
            readonly property var d: isl.shown ? isl.shown.data : ({})
            bot: isl.link.bot(d.bot)
            title: d.title || ""
            body: d.body || ""
            onOpened: { var id = d.bot; isl.next(); isl.sys.botsOpen(id, true); }
            onClosed: isl.next()
            onReplied: text => { isl.link.send(d.bot, text); isl.next(); }
        }
    }
    Component {
        id: approvalC
        BotApproval {
            sys: isl.sys
            readonly property var d: isl.shown ? isl.shown.data : ({})
            readonly property var b: isl.link.bot(d.bot)
            bot: b
            command: d.command || ""
            why: d.description || ""
            origin: b ? b.name + (b.model ? " · " + b.model : "") : ""
            timeout: d.timeout || 0
            onAnswered: choice => { isl.link.approve(choice, d); isl.next(); }
        }
    }
}
