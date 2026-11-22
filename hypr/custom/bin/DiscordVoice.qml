import QtQuick
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-island) - Discord (Vesktop) voice, for the island's Discord
// tab (DiscordView.qml) and the corner overlay (DiscordOverlay.qml). No UI: runs
// scripts/custom/discord-bridge.mjs while Settings > Discord is on, keeps the call's state and
// its people as a ListModel updated row by row (speaking changes one role, nothing rebuilds).
// The shell holds one as `sys.discord`.
Item {
    id: dv
    property var sys
    visible: false

    // the bridge's link: Discord running and reachable?
    property bool up: false
    property string why: "closed"        // closed | noflag (no port in vesktop-flags.conf) | restart (started before it)
    property bool call: false
    property string channel: ""
    property string guild: ""
    property string guildIcon: ""
    property real since: 0
    property bool mute: false
    property bool deaf: false
    property var noise: null             // null: not available
    property string rtc: ""
    property int ping: 0
    property string meId: ""
    readonly property bool running: up || why === "noflag" || why === "restart"
    readonly property bool inCall: up && call
    property ListModel people: ListModel {}

    readonly property string script: Quickshell.env("HOME") + "/.config/panacea/scripts/custom/discord-bridge.mjs"

    function send(o) { if (bridge.running) bridge.write(JSON.stringify(o) + "\n"); }
    function toggleMute() { send({ cmd: "mute" }); }
    function toggleDeaf() { send({ cmd: "deafen" }); }
    function disconnect() { send({ cmd: "disconnect" }); }
    function toggleNoise() { send({ cmd: "noise" }); }
    function toggleLocalMute(id) { send({ cmd: "localMute", id: id }); }
    function setVolume(id, v) { send({ cmd: "volume", id: id, v: Math.round(v) }); }
    function focusApp() {
        // its window if it has one, else the single-instance launch brings it back from the tray
        Quickshell.execDetached(["sh", "-c", "a=$(hyprctl clients -j | jq -r '[.[] | select(.class == \"vesktop\")][0].address // empty'); "
            + "if [ -n \"$a\" ]; then hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$a\\\" })\"; else gtk-launch vesktop; fi"]);
    }

    function indexOfId(id) { for (var i = 0; i < people.count; i++) if (people.get(i).uid === id) return i; return -1; }

    function apply(s) {
        dv.up = true; dv.why = "";
        dv.call = !!s.call; dv.channel = s.channel || ""; dv.guild = s.guild || ""; dv.guildIcon = s.guildIcon || "";
        dv.since = s.since || 0; dv.mute = !!s.mute; dv.deaf = !!s.deaf;
        dv.noise = (s.noise === null || s.noise === undefined) ? null : !!s.noise;
        dv.rtc = s.rtc || ""; dv.ping = s.ping || 0; dv.meId = s.me || "";
        var list = s.people || [];
        // drop who left
        var keep = {};
        for (var k = 0; k < list.length; k++) keep[list[k].id] = true;
        for (var i = people.count - 1; i >= 0; i--) if (!keep[people.get(i).uid]) people.remove(i);
        // update in place, insert who joined, keep the bridge's order
        for (var j = 0; j < list.length; j++) {
            var p = list[j];
            var row = { uid: p.id, name: p.name, avatar: p.avatar, me: !!p.me, muted: !!p.mute, deafened: !!p.deaf,
                        serverMute: !!p.serverMute, serverDeaf: !!p.serverDeaf, video: !!p.video, stream: !!p.stream,
                        speaking: !!p.speaking, localMute: !!p.localMute, volume: p.volume === undefined ? 100 : p.volume };
            var at = indexOfId(p.id);
            if (at < 0) { people.insert(Math.min(j, people.count), row); continue; }
            if (at !== j) { people.move(at, j, 1); at = j; }
            var cur = people.get(at);
            for (var key in row) if (cur[key] !== row[key]) people.setProperty(at, key, row[key]);
        }
    }
    function down(why) {
        dv.up = false; dv.why = why || "closed"; dv.call = false;
        people.clear();
    }

    Process {
        id: bridge
        command: ["node", dv.script]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                var m; try { m = JSON.parse(line); } catch (e) { return; }
                if (m.t === "state") dv.apply(m);
                else if (m.t === "speak") { var i = dv.indexOfId(m.id); if (i >= 0 && dv.people.get(i).speaking !== !!m.on) dv.people.setProperty(i, "speaking", !!m.on); }
                else if (m.t === "link") dv.down(m.why);
            }
        }
        onExited: { dv.down("closed"); if (dv.want) restartLater.restart(); }
    }
    // on while Settings > Discord is on; set by hand (not bound) so a crash can restart it
    readonly property bool want: !!(dv.sys && dv.sys.cfg.discordEnabled)
    onWantChanged: { restartLater.stop(); bridge.running = dv.want; }
    Component.onCompleted: bridge.running = dv.want
    Timer { id: restartLater; interval: 5000; onTriggered: if (dv.want) bridge.running = true }
}
