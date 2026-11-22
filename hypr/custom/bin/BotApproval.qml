import QtQuick

// A bot asks before it acts (the engine's approval.request): the bot's orb with the needs face,
// "iris wants to run a command", the command sunk into the card, where it comes from (bot · model
// · tool), and the engine's four answers: Deny, Allow once (the main one), This session, Always.
Rectangle {
    id: a
    property var sys
    readonly property var t: sys.pk
    property var bot: null
    property string what: "run a command"
    property string command: ""
    property string why: ""
    property string origin: ""
    property int timeout: 0                   // seconds left, 0 = none
    signal answered(string choice)            // once | session | always | deny

    width: 380
    implicitHeight: col.implicitHeight + 28
    radius: t.rSurface
    color: t.surface

    BotOrb { instantBot: true; x: 14; y: 14; size: 36; store: a.sys.orbs
             botId: a.bot ? a.bot.id : ""; shape: a.bot ? a.bot.shape : "circle"
             color: a.bot ? a.bot.color : "#a6a6ab"; reaction: "needs" }

    Column {
        id: col
        x: 62; y: 13; width: parent.width - x - 16
        spacing: 3
        Row { spacing: 6
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: a.t.accent }
            PkText { sys: a.sys; role: "caption"; text: a.origin + (a.timeout > 0 ? "  ·  " + a.timeout + " s" : "") } }
        PkText { sys: a.sys; role: "emph"; width: parent.width; text: (a.bot ? a.bot.name : "") + " wants to " + a.what }
        Text { width: parent.width; visible: a.why !== ""; text: a.why; color: a.t.soft; wrapMode: Text.Wrap
               font { family: a.t.font; pixelSize: a.t.tLabel } }
        Item { width: 1; height: 6 }
        Rectangle {
            width: parent.width; height: cmd.implicitHeight + 18; radius: a.t.rSmall; color: a.t.scrim
            Text { id: cmd; x: 10; y: 9; width: parent.width - 20; text: a.command; color: a.t.accentText; wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                   font { family: a.t.font; pixelSize: a.t.tLabel } }
        }
        Item { width: 1; height: 8 }
        Row {
            spacing: 6
            PkButton { sys: a.sys; small: true; kind: "primary"; text: "Allow once"; onClicked: a.answered("once") }
            PkButton { sys: a.sys; small: true; text: "This session"; onClicked: a.answered("session") }
            PkButton { sys: a.sys; small: true; kind: "ghost"; text: "Deny"; onClicked: a.answered("deny") }
        }
        PkText { sys: a.sys; role: "caption"; text: "Always allow this command"; color: a.t.faint
                 MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: a.answered("always") } }
    }
}
