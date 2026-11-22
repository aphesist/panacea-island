import QtQuick
import Quickshell

// written by portal-patch.py (panacea-island) - the island's Bots tab (boopis): the bots one at a
// time (BotsView), a bot's chat (BotChat) and the teams (BotTeam: rooms, then a room's chat), and
// what to do when boopis isn't running. State and commands: sys.bots (BotsLink.qml).
//
// Going between the stage and a chat the bot itself travels: a hero orb takes over the stage orb's
// exact frame and life, flies on the PkMorph spring (BotSpring, the bots' clock) to the chat's orb -
// the big one while nothing's been said, else the header's - and hands its frame back there; the
// pages cross-fade and slide on the same spring. Back runs it in reverse, and turning round
// mid-flight bends the spring rather than restarting it. Teams: the hero goes to the list's corner.
FocusScope {
    id: pg
    property var sys
    readonly property var t: sys.pk
    readonly property var link: sys.bots
    property string sub: "view"            // view | chat | team
    property string away: "chat"           // the page the stage goes to / comes back from
    property string chatId: ""
    readonly property bool ready: link.up && link.bots.length > 0
    width: 400
    implicitHeight: !ready ? empty.implicitHeight + 2 * t.pad
                  : sub === "chat" ? Math.min(520, sys.pageMaxH || 545)
                  : sub === "team" ? Math.min(team.item ? team.item.implicitHeight : 200, sys.pageMaxH || 545)
                  : view.implicitHeight
    focus: true
    Keys.onEscapePressed: { if (sub !== "view") back(); else sys.collapse(); }

    function back() { go("view"); view.forceActiveFocus(); }
    function openChat(id) { chatId = id; link.current = id; go("chat"); }
    function go(s) {
        if (s !== "view") away = s;
        var from = sub;
        sub = s;
        if (from === "view" && s !== "view") takeoff();
        else if (s === "view" && from !== "view" && !flying) {         // home: from the chat's orb
            hero.jump();
            if (dstOrb) { hero.adoptFrame(dstOrb.frameSnapshot()); hero.adoptLife(dstOrb.lifeSnapshot()); }
            flying = true;
        }
    }
    function show(id) { var i = -1; for (var k = 0; k < link.bots.length; k++) if (link.bots[k].id === id) i = k;
                        if (i >= 0) { view.idx = i; link.current = id; } }
    Component.onCompleted: {
        var i = 0;
        for (var k = 0; k < link.bots.length; k++) if (link.bots[k].id === link.current) i = k;
        view.idx = i;
        if (sys.botsOpenChat) { var c = sys.botsOpenChat; sys.botsOpenChat = ""; chatId = c; link.current = c; away = "chat"; sub = "chat"; fly.snap(); }
    }
    Connections { target: pg.sys; function onBotsStepped(d) { if (pg.sub === "view") pg.view.cycle(d); } }
    // talk mode: dictation on the stage (no box there) opens the bot's chat with the text in it, not sent
    Connections {
        target: pg.sys
        function onVoxChatTextArrived(text) {
            if (pg.sub !== "view" || !pg.ready || !text) return;
            pg.sys.botsDraft = text;
            talkLater.restart();
        }
    }
    Timer { id: talkLater; interval: 0; onTriggered: pg.openChat(pg.link.current) }
    property alias view: view
    property alias team: team

    // ---- the flight
    BotSpring { id: fly; clock: pg.sys.clock; to: pg.sub === "view" ? 0 : 1
                ms: pg.sys.animMs || 380; bounce: pg.sys.animBounce || 0; still: !!pg.sys.noMotion }
    readonly property real p: fly.value
    readonly property real pc: Math.max(0, Math.min(1, p))
    // the pages' cross-fade and slide are done by 85 % of the way: no faint page popping off on the
    // spring's overshoot, no sub-pixel creep (text snapping a pixel) at the tail
    readonly property real fadeIn: Math.min(1, pc / 0.85)
    readonly property real fadeOut: Math.max(0, 1 - pc / 0.85)
    readonly property Item awayItem: away === "chat" ? chat.item : team.item
    readonly property Item dstOrb: awayItem && awayItem.hero ? awayItem.hero : null
    property bool flying: false
    function takeoff() {
        var src = view.stageOrb;
        hero.jump();                                   // the bot being opened, before its first frame
        hero.adoptFrame(src.frameSnapshot());
        hero.adoptLife(src.lifeSnapshot());
        flying = true;
    }
    function land() {
        flying = false;
        if (sub === "view") {
            view.stageOrb.adoptFrame(hero.frameSnapshot()); view.stageOrb.adoptLife(hero.lifeSnapshot());
        } else if (dstOrb) {
            dstOrb.adoptFrame(hero.frameSnapshot()); dstOrb.adoptLife(hero.lifeSnapshot());
        }
    }
    onPChanged: if (flying && Math.abs(fly.to - p) < 0.002 && Math.abs(fly.velocity) < 0.05) land()
    function rectOf(it) { return it ? it.mapToItem(pg, 0, 0, it.width, it.height) : Qt.rect(0, 0, 0, 0); }

    BotsView {
        id: view
        sys: pg.sys
        width: pg.width
        visible: pg.ready && opacity > 0.002
        opacity: pg.fadeOut
        transform: Translate { y: -10 * (1 - pg.fadeOut) }
        heroHidden: pg.flying
        focus: pg.sub === "view"
        onOpenChat: id => pg.openChat(id)
        onOpenTeam: pg.go("team")
        onOpenSettings: { pg.sys.openSettingsPage ? pg.sys.openSettingsPage("bots") : pg.sys.collapse(); }
    }
    Loader {
        id: chat
        active: pg.ready && (pg.sub === "chat" || (pg.away === "chat" && pg.p > 0.001))
        visible: active
        opacity: pg.away === "chat" ? pg.fadeIn : 0
        transform: Translate { y: 14 * (1 - pg.fadeIn) }
        width: pg.width; height: Math.min(520, pg.sys.pageMaxH || 545)
        focus: pg.sub === "chat"
        sourceComponent: BotChat { sys: pg.sys; args: [pg.chatId]; width: pg.width; focus: true; onBack: pg.back()
                                   heroHidden: pg.flying }
    }
    Loader {
        id: team
        active: pg.ready && (pg.sub === "team" || (pg.away === "team" && pg.p > 0.001))
        visible: active
        opacity: pg.away === "team" ? pg.fadeIn : 0
        transform: Translate { y: 14 * (1 - pg.fadeIn) }
        width: pg.width
        focus: pg.sub === "team"
        sourceComponent: BotTeam { sys: pg.sys; width: pg.width; focus: true; onBack: pg.back(); heroHidden: pg.flying }
    }

    // the bot in flight
    BotOrb {
        id: hero
        readonly property var b: pg.link.bot(pg.link.current)
        readonly property rect ra: { pg.p; return pg.rectOf(view.stageOrb); }
        readonly property rect rb: { pg.p; if (pg.dstOrb) return pg.rectOf(pg.dstOrb);
                                    var s = team.item ? team.item.heroSpot : Qt.point(0, 15);
                                    return Qt.rect(team.x + s.x, team.y + s.y, 20, 20); }
        readonly property real k: pg.p
        z: 10
        visible: pg.flying && pg.ready
        opacity: pg.away === "team" && !pg.dstOrb ? 1 - Math.max(0, Math.min(1, (pg.pc - 0.35) / 0.55)) : 1
        store: pg.sys.orbs; clock: pg.sys.clock; alive: 1; lifeScale: 0; live: true; instantBot: true
        botId: b ? b.id : ""; shape: b ? b.shape : "circle"; color: b ? b.color : "#a6a6ab"; reaction: b ? b.reaction : "idle"
        size: Math.max(8, ra.width + (rb.width - ra.width) * k)
        x: ra.x + ra.width / 2 + ((rb.x + rb.width / 2) - (ra.x + ra.width / 2)) * k - size / 2
        y: ra.y + ra.height / 2 + ((rb.y + rb.height / 2) - (ra.y + ra.height / 2)) * k - size / 2
    }

    // boopis isn't running, never set up, or has no bots
    Column {
        id: empty
        visible: !pg.ready
        x: pg.t.pad; y: pg.t.pad; width: pg.width - 2 * pg.t.pad
        spacing: 10
        PkIcon { sys: pg.sys; name: "robot"; size: 28; color: pg.t.muted; anchors.horizontalCenter: parent.horizontalCenter }
        PkText { sys: pg.sys; role: "emph"; anchors.horizontalCenter: parent.horizontalCenter
                 text: !pg.link.up && pg.link.why === "nohome" ? "boopis isn't set up yet"
                     : !pg.link.up ? "boopis isn't running" : "No bots yet" }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
               color: pg.t.muted; font { family: pg.t.font; pixelSize: pg.t.tLabel }
               text: !pg.link.up ? "Your bots show here as soon as boopis is open." : "Make a bot in boopis and it shows here." }
        PkButton { sys: pg.sys; anchors.horizontalCenter: parent.horizontalCenter; text: "Open boopis"; icon: "arrow-square-out"
                   onClicked: { Quickshell.execDetached(["gtk-launch", "boopis"]); pg.sys.collapse(); } }
    }
}
