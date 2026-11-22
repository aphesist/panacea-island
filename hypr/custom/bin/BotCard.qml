import QtQuick

// A bot's notification card (it drops out of the island like the toasts): the bot's live orb
// where PkNotifCard has the app tile, "name · time" (red dot when it needs you), a title, up to
// `lines` of its message, and Reply / Open. Reply turns the card's bottom into a field in place.
Rectangle {
    id: c
    property var sys
    readonly property var t: sys.pk
    property var bot: null                     // {id, name, shape, color, reaction, attention}
    property string time: "now"
    property string title: ""
    property string body: ""
    property int lines: 3
    property bool replying: false
    signal opened()
    signal closed()
    signal replied(string text)

    width: 380
    implicitHeight: col.implicitHeight + 28
    radius: t.rSurface
    color: ma.containsMouse ? t.veil(0.1) : t.surface
    Behavior on color { ColorAnimation { duration: c.t.dFast } }

    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.opened() }

    BotOrb { instantBot: true; id: orb; x: 14; y: 14; size: 36; store: c.sys.orbs
             botId: c.bot ? c.bot.id : ""; shape: c.bot ? c.bot.shape : "circle"
             color: c.bot ? c.bot.color : "#a6a6ab"; reaction: c.bot ? c.bot.reaction : "idle" }

    PkIconButton { sys: c.sys; anchors.right: parent.right; anchors.rightMargin: 8; y: 8; icon: "x"; size: 13
                   opacity: ma.containsMouse ? 1 : 0; z: 2
                   Behavior on opacity { NumberAnimation { duration: c.t.dFast } }
                   onClicked: c.closed() }

    Column {
        id: col
        x: 62; y: 13; width: parent.width - x - 16
        spacing: 3
        Row {
            spacing: 6
            Rectangle { visible: !!(c.bot && c.bot.attention); anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3; color: c.t.accent }
            PkText { sys: c.sys; role: "caption"; text: (c.bot ? c.bot.name : "") + "  ·  " + c.time }
        }
        PkText { sys: c.sys; role: "emph"; width: parent.width; text: c.title; visible: text !== ""; elide: Text.ElideRight }
        Text { width: parent.width; visible: c.body !== ""; text: c.body; color: c.t.soft; wrapMode: Text.Wrap
               maximumLineCount: c.lines; elide: Text.ElideRight; lineHeight: 1.1
               font { family: c.t.font; pixelSize: c.t.tLabel } }
        Item { width: 1; height: 6 }
        Item {
            width: parent.width; height: 30
            Row { spacing: 6; visible: !c.replying
                PkButton { sys: c.sys; small: true; text: "Reply"; icon: "arrow-bend-up-left"; onClicked: c.replying = true }
                PkButton { sys: c.sys; small: true; kind: "ghost"; text: "Open"; onClicked: c.opened() } }
            PkField { sys: c.sys; anchors.fill: parent; visible: c.replying; placeholder: "Reply to " + (c.bot ? c.bot.name : "") + "…"
                      onAccepted: { c.replied(text); text = ""; c.replying = false; } }
        }
    }
}
