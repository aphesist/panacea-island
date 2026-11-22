import QtQuick

// The collapsed island while bots are around: the bot that matters most (needs you > working >
// the one you last talked to), its name and state word; the other bots that are busy as small
// orbs on the right, a red dot on any that needs you. Orbs here hold still (`live: false`) and only
// move when something changes, so a quiet desktop costs no frames.
Item {
    id: p
    property var sys
    readonly property var t: sys.pk
    readonly property var link: sys.bots
    property string focusId: ""                    // override: the bot to show (else picked)
    readonly property var lead: {
        var bs = link ? link.bots || [] : [], best = null, score = -1;
        for (var i = 0; i < bs.length; i++) {
            var b = bs[i], s = b.attention ? 3 : ["working", "thinking", "compute", "speaking"].indexOf(b.reaction) >= 0 ? 2
                    : b.id === link.current ? 1 : 0;
            if (b.id === focusId) s = 9;
            if (s > score) { score = s; best = b; }
        }
        return best;
    }
    readonly property var others: (link ? link.bots || [] : []).filter(function (b) {
        return b !== p.lead && (b.attention || ["working", "thinking", "compute", "speaking"].indexOf(b.reaction) >= 0);
    })
    implicitWidth: row.implicitWidth + 24
    implicitHeight: 38

    Row {
        id: row
        anchors.centerIn: parent; spacing: 8
        BotOrb { store: p.sys.orbs; size: 22; live: !!(p.lead && p.lead.reaction !== "idle" && p.lead.reaction !== "sleeping")
                 anchors.verticalCenter: parent.verticalCenter
                 botId: p.lead ? p.lead.id : ""; shape: p.lead ? p.lead.shape : "circle"
                 color: p.lead ? p.lead.color : "#a6a6ab"; reaction: p.lead ? p.lead.reaction : "idle" }
        Text { anchors.verticalCenter: parent.verticalCenter; text: p.lead ? p.lead.name : ""
               color: p.t.fg; font { family: p.t.font; pixelSize: p.t.tBody; weight: Font.DemiBold } }
        Text { anchors.verticalCenter: parent.verticalCenter; visible: text !== ""
               text: p.lead ? (p.lead.attention ? "needs you" : p.lead.word) : ""
               color: p.lead && p.lead.attention ? p.t.accentText : p.t.muted
               font { family: p.t.font; pixelSize: p.t.tLabel } }
        Item { width: p.others.length ? 4 : 0; height: 1 }
        Row {
            anchors.verticalCenter: parent.verticalCenter; spacing: -4
            Repeater { model: p.others
                Item { width: 18; height: 18
                    Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; color: "#000" }
                    BotOrb { anchors.centerIn: parent; store: p.sys.orbs; size: 15; live: false
                             botId: modelData.id; shape: modelData.shape; color: modelData.color; reaction: modelData.reaction }
                    Rectangle { visible: modelData.attention; width: 6; height: 6; radius: 3; color: p.t.accent
                                anchors.right: parent.right; anchors.top: parent.top }
                }
            }
        }
    }
}
