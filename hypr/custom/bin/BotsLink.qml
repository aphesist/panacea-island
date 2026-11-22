import QtQuick
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-island) - boopis bots on the island. No UI: runs
// scripts/custom/boopis-bridge.mjs while Settings > Bots is on and keeps what the views read:
// the roster with each bot's look and state, the thread of the bot you talk to, pending approvals,
// the team rooms. The shell holds one as `sys.bots`. Cards for the island's toasts come out as
// the `card(kind, data)` signal.
Item {
    id: bl
    property var sys
    visible: false

    property bool up: false
    property string why: "closed"            // closed (boopis not running) | nohome (never set up) | error
    property var bots: []
    property string current: ""
    property var threads: ({})               // bot id -> [{id, who, text, done}]
    property var steps: ({})                 // bot id -> [{text, done}] of the turn in progress
    property var approvals: []               // [{bot, id, command, description, choices, timeout}]
    readonly property var approval: approvals.length ? approvals[0] : null
    property var rooms: []
    property string lastError: ""
    property var room: null                  // the open room: {id, name, members, working, log}
    signal card(string kind, var data)       // "reply" | "approval": the island shows a BotCard / BotApproval

    readonly property string script: Quickshell.env("HOME") + "/.config/panacea/scripts/custom/boopis-bridge.mjs"
    function _send(o) { if (bridge.running) bridge.write(JSON.stringify(o) + "\n"); }
    function send(botId, text) { _send({ cmd: "send", bot: botId, text: text }); }
    function approve(choice, a) { a = a || approval; if (a) _send({ cmd: "approve", bot: a.bot, id: a.id, choice: choice }); }
    function interrupt(botId) { _send({ cmd: "interrupt", bot: botId }); }
    function openRoom(id) {
        var r = null;
        for (var i = 0; i < rooms.length; i++) if (rooms[i].id === id) r = rooms[i];
        if (!r) return;
        room = { id: r.id, name: r.name, members: r.members, working: [], log: [] };
        _send({ cmd: "room", room: id });
    }
    function roomSend(id, text) { _send({ cmd: "roomSend", room: id, text: text }); }
    function refresh() { _send({ cmd: "refresh" }); }
    readonly property var busyWords: ["working", "thinking", "compute", "speaking", "listening"]
    readonly property bool anyBusy: bots.some(function (b) { return b.attention || busyWords.indexOf(b.reaction) >= 0; })
    readonly property bool anyNeeds: bots.some(function (b) { return b.attention; })
    function bot(id) { for (var i = 0; i < bots.length; i++) if (bots[i].id === id) return bots[i]; return null; }

    function _patchBot(m) {
        bots = bots.map(function (b) {
            if (b.id !== m.id) return b;
            var n = Object.assign({}, b, m, { t: undefined });
            var was = busyWords.indexOf(b.reaction) >= 0, now = busyWords.indexOf(n.reaction) >= 0;
            if (now && !was) n.since = m.since || Date.now();              // a turn started: the stage's clock
            if (!now && was && !m.lastAt) n.lastAt = Date.now();           // and ended: "last activity"
            return n;
        });
    }
    // what a bot is doing, for the stage: {summary, n, of, since}. boopis 0.1.8 will send summary /
    // stepN / stepOf itself; until then the turn's tool steps stand in ("Running a command", 2 of 2).
    readonly property var _toolWords: ({ terminal: "Running a command", shell: "Running a command", read_file: "Reading a file",
        write_file: "Writing a file", patch: "Editing a file", search_files: "Searching files", web_search: "Searching the web",
        web_extract: "Reading a page", browser: "Using the browser", vision: "Looking at an image", a2a_forward: "Handing work over",
        kanban: "Updating the board", delegate_task: "Delegating" })
    function activity(b) {
        if (!b) return null;
        var list = steps[b.id] || [], cur = null, done = 0;
        for (var i = 0; i < list.length; i++) { if (list[i].done) done++; else cur = list[i]; }
        var name = cur ? cur.text : list.length ? list[list.length - 1].text : "";
        var summary = b.summary || (name ? (_toolWords[name] || name.replace(/[_.]/g, " ").replace(/^./, function (c) { return c.toUpperCase(); }))
                                        : b.reaction === "speaking" ? "Replying" : "Thinking");
        var of = b.stepOf || list.length, n = b.stepN || Math.min(of, done + (cur ? 1 : 0));
        return { summary: summary, n: n, of: of, since: b.since || 0 };
    }
    function _msg(m) {
        var th = (threads[m.bot] || []).slice(), at = -1;
        for (var i = th.length - 1; i >= 0; i--) if (th[i].id === m.id) { at = i; break; }
        var row = { id: m.id, who: m.who, text: m.text, done: !!m.done };
        if (m.done && m.who !== "you" && (steps[m.bot] || []).length)   // the reply keeps the steps it took
            row.steps = steps[m.bot].map(function (x) { return { text: x.text, done: true }; });
        if (at < 0) th.push(row); else th[at] = row;
        var t = Object.assign({}, threads); t[m.bot] = th; threads = t;
        if (m.done && m.who !== "you") { var s = Object.assign({}, steps); delete s[m.bot]; steps = s; }
    }
    function _step(m) {
        var list = (steps[m.bot] || []).slice(), at = -1;
        for (var i = 0; i < list.length; i++) if (list[i].text === m.name && !list[i].done) at = i;
        if (at >= 0) list[at] = { text: m.name, done: !!m.done }; else list.push({ text: m.name, done: !!m.done });
        var s = Object.assign({}, steps); s[m.bot] = list; steps = s;
    }

    Process {
        id: bridge
        command: ["node", bl.script]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                var m; try { m = JSON.parse(line); } catch (e) { return; }
                switch (m.t) {
                case "link": bl.up = !!m.up; bl.why = m.up ? "" : (m.why || "closed"); if (!m.up) bl.bots = []; break;
                case "bots": bl.bots = m.bots; if (!bl.bot(bl.current) && m.bots.length) bl.current = m.bots[0].id; break;
                case "bot": bl._patchBot(m); break;
                case "msg": bl._msg(m); break;
                case "tool": bl._step(m); break;
                case "approval": bl.approvals = bl.approvals.concat([m]); if (bl.sys.cfg.botsApprovals) bl.card("approval", m); break;
                case "settled": bl.approvals = bl.approvals.filter(function (a) { return a.id !== m.id; }); break;
                case "notify": if (bl.sys.cfg.botsCards && !(bl.sys.expanded && bl.sys.page === "bots")) bl.card("reply", m); break;
                case "error": console.warn("bots:", m.cmd, m.detail); bl.lastError = (m.cmd || "") + ": " + (m.detail || ""); break;
                case "rooms": bl.rooms = m.rooms; break;
                case "roomlog": if (bl.room && bl.room.id === m.room) bl.room = Object.assign({}, bl.room, { log: m.events }); break;
                case "roomstate": if (bl.room && bl.room.id === m.room) bl.room = Object.assign({}, bl.room, { working: m.working || [], round: m.round || 0, waiting: !!m.waiting }); break;
                }
            }
        }
        onExited: { bl.up = false; bl.why = "closed"; if (bl.want) restartLater.restart(); }
    }
    readonly property bool want: !!(bl.sys && bl.sys.cfg.botsEnabled)
    onWantChanged: { restartLater.stop(); bridge.running = bl.want; }
    Component.onCompleted: bridge.running = bl.want
    Timer { id: restartLater; interval: 5000; onTriggered: if (bl.want) bridge.running = true }
}
