import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-config) - the island's task manager (Super+Shift+Esc).
// Processes (apps grouped with everything they started, your background processes,
// system ones; icons, sort, search, end or force-kill), Performance (your actual parts:
// CPU, memory, both GPUs, the SSD, Wi-Fi, battery, live) and Services (user and system
// units). Data from scripts/custom/taskman.py. Panacea's palette and the chat's radius
// system, no outlines. Nothing here is rebuilt on each update: lists are ListModels
// updated row by row, everything else binds to the live values in place.
FocusScope {
    id: view
    property var sys
    implicitHeight: 680
    focus: true

    readonly property real islandR: sys.cfg.islandRadius > 0 ? sys.cfg.islandRadius : 26
    readonly property real boxR: Math.max(14, islandR - 6)
    readonly property real rInner: Math.max(8, boxR - 6)
    readonly property string tm: sys.scriptDir + "/custom/taskman.py"

    property string tab: "processes"
    property var snap: ({})
    property var hw: ({})
    property string query: ""
    property string sortKey: "cpu"
    property bool sortDesc: true
    property int selPid: -1
    property string selName: ""
    property var openApps: ({})
    property string device: "cpu"
    property string error: ""
    // histories, newest last
    property var hCpu: []
    property var hMem: []
    property var hGpu: []
    property var hIgpu: []
    property var hDiskR: []
    property var hDiskW: []
    property var hRx: []
    property var hTx: []
    property var hBat: []
    property var units: []
    property string unitQuery: ""
    property string busyAction: ""

    function goBack() {
        if (menu.visible) { menu.visible = false; return true; }
        if (query) { query = ""; search.text = ""; return true; }
        return false;
    }
    function push(arr, v) { var a = arr.slice(-59); a.push(v || 0); return a; }
    function fmtBytes(b) {
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TB";
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576) return (b / 1048576).toFixed(b >= 104857600 ? 0 : 1) + " MB";
        if (b >= 1024) return Math.round(b / 1024) + " KB";
        return Math.round(b) + " B";
    }
    function fmtRate(b) { return fmtBytes(b) + "/s"; }
    function fmtUptime(s) {
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
    }
    function iconSource(icon) {
        if (!icon) return "";
        if (icon.charAt(0) === "/") return "file://" + icon;
        return Quickshell.iconPath(icon, true) || "";
    }

    // ------------------------------------------------------------------ data
    Process {
        id: streamProc
        command: ["python3", "-I", view.tm, "stream"]
        running: true
        stdout: SplitParser { onRead: line => { try { view.take(JSON.parse(line)); } catch (e) {} } }
        onExited: restartTimer.start()
    }
    Timer { id: restartTimer; interval: 2000; onTriggered: streamProc.running = true }
    Process { id: hwProc; command: ["python3", "-I", view.tm, "hw"]; running: true
              stdout: StdioCollector { onStreamFinished: { try { view.hw = JSON.parse(text); } catch (e) {} } } }
    function take(d) {
        var m = d.mem || {};
        hCpu = push(hCpu, (d.cpu || {}).total);
        hMem = push(hMem, m.total ? 100 * m.used / m.total : 0);
        hGpu = push(hGpu, d.gpu && d.gpu.awake ? d.gpu.util || 0 : 0);
        hIgpu = push(hIgpu, d.igpuMHz || 0);
        hDiskR = push(hDiskR, (d.disk || {}).read); hDiskW = push(hDiskW, (d.disk || {}).write);
        hRx = push(hRx, (d.net || {}).rx); hTx = push(hTx, (d.net || {}).tx);
        hBat = push(hBat, d.battery ? d.battery.percent : 0);
        view.snap = d;
        rebuild();
    }

    Process { id: act; stdout: StdioCollector { onStreamFinished: {
        try { var d = JSON.parse(text); view.error = d.ok === false ? (d.error || "Didn't work") : ""; } catch (e) {}
        view.busyAction = ""; if (view.tab === "services") unitsProc.running = true;
    } } }
    function signalSel(kind) {
        if (view.selPid <= 0 || act.running) return;
        act.command = ["python3", "-I", view.tm, "signal", String(view.selPid), kind];
        act.running = true; menu.visible = false;
    }
    function unitAction(u, action) {
        if (act.running) return;
        view.busyAction = u.unit + ":" + action;
        act.command = ["python3", "-I", view.tm, "unit", u.scope, action, u.unit];
        act.running = true;
    }
    Process { id: unitsProc; command: ["python3", "-I", view.tm, "units"]
        stdout: StdioCollector { onStreamFinished: { try { view.units = JSON.parse(text).units || []; } catch (e) {} } } }
    Timer { interval: 5000; repeat: true; running: view.tab === "services"; triggeredOnStart: true
            onTriggered: if (!unitsProc.running) unitsProc.running = true }

    // ---- process rows: apps (expandable into their processes), background, system
    ListModel { id: procModel }
    function row(o) {
        return { pid: o.pid, name: String(o.name || ""), sub: String(o.sub || ""), icon: String(o.icon || ""),
                 cpu: Number(o.cpu || 0), mem: Number(o.mem || 0), group: o.group, child: !!o.child,
                 count: o.count || 0, open: !!o.open };
    }
    function rebuild() {
        var q = query.trim().toLowerCase();
        function hit(n, extra) { return !q || n.toLowerCase().indexOf(q) >= 0 || (extra || "").toLowerCase().indexOf(q) >= 0; }
        var k = sortKey, dir = sortDesc ? -1 : 1;
        function cmp(a, b) {
            var x = a[k], y = b[k];
            if (k === "name") { x = String(x).toLowerCase(); y = String(y).toLowerCase(); }
            return x < y ? -dir : x > y ? dir : a.pid - b.pid;
        }
        var rows = [];
        var apps = (snap.apps || []).filter(function (a) {
            return hit(a.name, a.window + " " + a.pid) || a.kids.some(function (c) { return hit(c.name, String(c.pid)); });
        }).slice().sort(cmp);
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i], open = !!openApps[a.pid] || (q && !hit(a.name, a.window));
            rows.push(row({ pid: a.pid, name: a.name, sub: a.window, icon: a.icon, cpu: a.cpu, mem: a.mem, group: "apps",
                            count: a.count, open: open }));
            if (open) {
                var kids = a.kids.slice().sort(cmp);
                for (var j = 0; j < kids.length; j++)
                    rows.push(row({ pid: kids[j].pid, name: kids[j].name, icon: kids[j].icon || a.icon, cpu: kids[j].cpu,
                                    mem: kids[j].mem, group: "apps", child: true }));
            }
        }
        // background first, then system: one section each (sorting by usage alone interleaved them)
        var rest = (snap.procs || []).filter(function (p) { return hit(p.name, String(p.pid)); }).slice()
                   .sort(function (a, b) { return a.mine !== b.mine ? (a.mine ? -1 : 1) : cmp(a, b); });
        for (var r = 0; r < rest.length; r++)
            rows.push(row({ pid: rest[r].pid, name: rest[r].name, icon: rest[r].icon, cpu: rest[r].cpu, mem: rest[r].mem,
                            group: rest[r].mine ? "background" : "system" }));
        syncModel(procModel, rows);
    }
    function syncModel(model, rows) {
        for (var j = 0; j < rows.length; j++) {
            if (j < model.count) {
                var cur = model.get(j);
                for (var key in rows[j]) if (cur[key] !== rows[j][key]) model.setProperty(j, key, rows[j][key]);
            } else model.append(rows[j]);
        }
        while (model.count > rows.length) model.remove(model.count - 1);
    }
    function toggleApp(pid) { var o = Object.assign({}, openApps); if (o[pid]) delete o[pid]; else o[pid] = true; openApps = o; rebuild(); }
    onQueryChanged: rebuild()
    onSortKeyChanged: rebuild()
    onSortDescChanged: rebuild()
    function sortBy(k) { if (sortKey === k) sortDesc = !sortDesc; else { sortKey = k; sortDesc = k !== "name" && k !== "pid"; } }

    ListModel { id: unitModel }
    function rebuildUnits() {
        var q = unitQuery.trim().toLowerCase();
        var rows = units.filter(function (u) {
            return !q || u.unit.toLowerCase().indexOf(q) >= 0 || u.desc.toLowerCase().indexOf(q) >= 0;
        }).sort(function (a, b) {
            if (a.scope !== b.scope) return a.scope === "user" ? -1 : 1;
            var ra = a.active === "active" ? 0 : a.active === "failed" ? 1 : 2, rb = b.active === "active" ? 0 : b.active === "failed" ? 1 : 2;
            return ra !== rb ? ra - rb : a.unit.localeCompare(b.unit);
        }).map(function (u) { return { scope: u.scope, unit: u.unit, active: u.active, sub: u.sub, desc: u.desc }; });
        syncModel(unitModel, rows);
    }
    onUnitsChanged: rebuildUnits()
    onUnitQueryChanged: rebuildUnits()

    // ---- performance: what each device shows (all bound to live values, never rebuilt)
    readonly property var gpuNv: snap.gpu || null
    readonly property var memNow: snap.mem || ({})
    readonly property string igpuName: {
        var g = (hw.gpus || []).find(function (x) { return /intel/i.test(x); });
        return g ? "Intel Iris Xe Graphics" : "Integrated GPU";
    }
    readonly property string nvName: gpuNv && gpuNv.name && gpuNv.name !== "NVIDIA GPU" ? gpuNv.name.replace("NVIDIA ", "")
        : ((hw.gpus || []).find(function (x) { return /nvidia/i.test(x); }) || "NVIDIA GPU").replace("NVIDIA ", "")
    function devTitle(k) { return ({ cpu: "CPU", mem: "Memory", igpu: "GPU 0", gpu: "GPU 1", disk: "Disk 0", net: "Wi-Fi", bat: "Battery" })[k] || k; }
    function devPart(k) {
        switch (k) {
        case "cpu": return ((hw.cpu || {}).model || "").replace(/\(R\)|\(TM\)/g, "").replace(/\s+/g, " ").replace("13th Gen ", "");
        case "mem": return hw.ram ? fmtBytes(hw.ram.total) + (hw.ram.type ? " " + hw.ram.type : "") + (hw.ram.speed ? " · " + hw.ram.speed + " MT/s" : "") : "";
        case "igpu": return igpuName;
        case "gpu": return nvName;
        case "disk": { var d = (hw.disks || [])[0]; return d ? (d.model || d.name) + " · " + d.kind : ""; }
        case "net": return hw.net && hw.net.connection ? hw.net.connection : (hw.net && hw.net.type) || "Offline";
        case "bat": return hw.battery ? hw.battery.model : "";
        }
        return "";
    }
    function devValue(k) {
        var s = snap;
        switch (k) {
        case "cpu": return Math.round((s.cpu || {}).total || 0) + "%  " + ((s.mhz || 0) / 1000).toFixed(2) + " GHz";
        case "mem": return fmtBytes(memNow.used || 0) + " / " + fmtBytes(memNow.total || 0) + "  (" + (memNow.total ? Math.round(100 * memNow.used / memNow.total) : 0) + "%)";
        case "igpu": return (s.igpuMHz || 0) + " MHz";
        case "gpu": return !gpuNv ? "Not found" : gpuNv.awake ? Math.round(gpuNv.util || 0) + "%  " + Math.round(gpuNv.temp || 0) + " °C" : "Asleep";
        case "disk": return "R " + fmtRate((s.disk || {}).read || 0) + "  W " + fmtRate((s.disk || {}).write || 0);
        case "net": return "↓ " + fmtRate((s.net || {}).rx || 0) + "  ↑ " + fmtRate((s.net || {}).tx || 0);
        case "bat": return s.battery ? s.battery.percent + "%  " + s.battery.status : "None";
        }
        return "";
    }
    function devHist(k) { return ({ cpu: hCpu, mem: hMem, igpu: hIgpu, gpu: hGpu, disk: hDiskR, net: hRx, bat: hBat })[k] || []; }
    function devHist2(k) { return k === "disk" ? hDiskW : k === "net" ? hTx : []; }
    function devMax(k) { return k === "disk" || k === "net" ? 0 : k === "igpu" ? (hw.igpuMaxMHz || 1500) : 100; }
    // labels per device (static), and their live values
    function statKeys(k) {
        return ({
            cpu: ["Utilization", "Speed", "Max speed", "Cores", "Threads", "Temperature", "Load (1, 5, 15 min)", "Processes", "Up time"],
            mem: ["In use", "Available", "Total", "Type", "Speed", "Rated speed", "Modules", "Form factor", "Maker", "Swap", "Swap used", "Part number"],
            igpu: ["Clock", "Max clock", "Shared memory"],
            gpu: ["Utilization", "Video memory", "Temperature", "Power", "State"],
            disk: ["Read", "Write", "Capacity", "Used on /", "Free on /", "Type"],
            net: ["Download", "Upload", "Network", "Adapter", "IPv4", "Driver"],
            bat: ["Charge", "State", "Draw", "Health", "Cycles", "Chemistry"]
        })[k] || [];
    }
    function stat(k, label) {
        var s = snap, c = s.cpu || {}, g = gpuNv, d = (hw.disks || [])[0], b = s.battery, n = hw.net || {}, r = hw.root || {};
        switch (k + "/" + label) {
        case "cpu/Utilization": return Math.round(c.total || 0) + "%";
        case "cpu/Speed": return ((s.mhz || 0) / 1000).toFixed(2) + " GHz";
        case "cpu/Max speed": return (((hw.cpu || {}).maxMHz || 0) / 1000).toFixed(2) + " GHz";
        case "cpu/Cores": return String((hw.cpu || {}).cores || "—");
        case "cpu/Threads": return String((hw.cpu || {}).threads || s.ncpu || "—");
        case "cpu/Temperature": return c.temp ? Math.round(c.temp) + " °C" : "—";
        case "cpu/Load (1, 5, 15 min)": return (c.load || []).join("  ");
        case "cpu/Processes": return String(s.count || 0);
        case "cpu/Up time": return fmtUptime(s.uptime || 0);
        case "mem/In use": return fmtBytes(memNow.used || 0);
        case "mem/Available": return fmtBytes((memNow.total || 0) - (memNow.used || 0));
        case "mem/Total": return fmtBytes(memNow.total || 0);
        case "mem/Type": return (hw.ram || {}).type || "—";
        case "mem/Speed": return (hw.ram || {}).speed ? hw.ram.speed + " MT/s" : "—";
        case "mem/Rated speed": return (hw.ram || {}).rated ? hw.ram.rated + " MT/s" : "—";
        case "mem/Modules": return (hw.ram || {}).modules ? hw.ram.modules + " × " + fmtBytes(hw.ram.total / hw.ram.modules).replace(".0 ", " ") : "—";
        case "mem/Form factor": return (hw.ram || {}).form === "Row Of Chips" ? "Soldered" : ((hw.ram || {}).form || "—");
        case "mem/Maker": return (hw.ram || {}).maker || "—";
        case "mem/Part number": return (hw.ram || {}).part || "—";
        case "mem/Swap": return fmtBytes(memNow.swapTotal || 0) + (hw.ram && hw.ram.zram ? " (zram)" : "");
        case "mem/Swap used": return fmtBytes(memNow.swapUsed || 0);
        case "igpu/Clock": return (s.igpuMHz || 0) + " MHz";
        case "igpu/Max clock": return (hw.igpuMaxMHz || 0) + " MHz";
        case "igpu/Shared memory": return "System RAM";
        case "gpu/Utilization": return g && g.awake ? Math.round(g.util || 0) + "%" : "—";
        case "gpu/Video memory": return g && g.awake ? fmtBytes(g.memUsed || 0) + " / " + fmtBytes(g.memTotal || 0) : "—";
        case "gpu/Temperature": return g && g.awake ? Math.round(g.temp || 0) + " °C" : "—";
        case "gpu/Power": return g && g.awake ? (g.watts || 0).toFixed(1) + " W" : "—";
        case "gpu/State": return !g ? "Not found" : g.awake ? "Active" : "Asleep (saving power)";
        case "disk/Read": return fmtRate((s.disk || {}).read || 0);
        case "disk/Write": return fmtRate((s.disk || {}).write || 0);
        case "disk/Capacity": return d ? fmtBytes(d.size) : "—";
        case "disk/Used on /": return r.total ? fmtBytes(r.total - r.free) : "—";
        case "disk/Free on /": return r.total ? fmtBytes(r.free) : "—";
        case "disk/Type": return d ? d.kind : "—";
        case "net/Download": return fmtRate((s.net || {}).rx || 0);
        case "net/Upload": return fmtRate((s.net || {}).tx || 0);
        case "net/Network": return n.connection || "—";
        case "net/Adapter": return n.device ? n.device + " · " + (n.type || "") : "—";
        case "net/IPv4": return n.ip || "—";
        case "net/Driver": return n.driver || "—";
        case "bat/Charge": return b ? b.percent + "%" : "—";
        case "bat/State": return b ? b.status : "—";
        case "bat/Draw": return b && b.watts ? b.watts + " W" : "—";
        case "bat/Health": return hw.battery && hw.battery.health ? hw.battery.health + "%" : "—";
        case "bat/Cycles": return hw.battery ? String(hw.battery.cycles) : "—";
        case "bat/Chemistry": return hw.battery ? hw.battery.tech : "—";
        }
        return "—";
    }

    Keys.onPressed: event => {
        if (view.tab === "processes" && event.key === Qt.Key_Delete) { view.signalSel((event.modifiers & Qt.ShiftModifier) ? "kill" : "term"); event.accepted = true; }
        else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
            var order = ["processes", "performance", "services"]; view.tab = order[(order.indexOf(view.tab) + 1) % 3]; event.accepted = true;
        }
    }

    // ------------------------------------------------------------------ header
    Item {
        id: header
        width: parent.width; height: 40
        Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: 2
            Text { text: "Task Manager"; color: view.sys.colFg; font { pixelSize: 16; bold: true; family: view.sys.fontBody } }
            Text { text: (view.hw.machine ? view.hw.machine + "  ·  " : "") + (view.snap.count || 0) + " processes  ·  up " + view.fmtUptime(view.snap.uptime || 0)
                          + (view.error ? "  ·  " + view.error : "")
                   color: view.error ? view.sys.colCrit : view.sys.colMuted; font { pixelSize: 11; family: view.sys.fontBody } }
        }
        Rectangle {
            id: seg
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 330; height: 32; radius: 16; color: Qt.rgba(1, 1, 1, 0.05)
            readonly property var tabs: [{ k: "processes", t: "Processes" }, { k: "performance", t: "Performance" }, { k: "services", t: "Services" }]
            Rectangle {
                y: 3; height: parent.height - 6; radius: height / 2; width: parent.width / 3 - 4
                x: 2 + (view.tab === "processes" ? 0 : view.tab === "performance" ? 1 : 2) * parent.width / 3
                color: Qt.rgba(1, 1, 1, 0.14)
                Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
            }
            Repeater {
                model: seg.tabs
                delegate: Item {
                    required property var modelData
                    required property int index
                    x: index * seg.width / 3; width: seg.width / 3; height: seg.height
                    Text { anchors.centerIn: parent; text: parent.modelData.t
                           color: view.tab === parent.modelData.k || segMa.containsMouse ? view.sys.colFg : view.sys.colMuted
                           Behavior on color { ColorAnimation { duration: 200 } }
                           scale: segMa.pressed ? 0.92 : 1
                           Behavior on scale { NumberAnimation { duration: 140 } }
                           font { pixelSize: 12; bold: true; family: view.sys.fontBody } }
                    MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: view.tab = parent.modelData.k }
                }
            }
        }
    }

    Item {
        id: body
        anchors.top: header.bottom; anchors.topMargin: 14
        anchors.bottom: parent.bottom
        width: parent.width

        // ============================================================ processes
        Item {
            anchors.fill: parent
            opacity: view.tab === "processes" ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Rectangle {
                id: searchBox
                width: Math.min(360, parent.width * 0.4); height: 36; radius: view.rInner
                color: search.activeFocus ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(1, 1, 1, 0.055)
                TextInput {
                    id: search
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter; clip: true; focus: true
                    color: view.sys.colFg; selectionColor: Qt.rgba(1, 1, 1, 0.25)
                    font { pixelSize: 12; family: view.sys.fontFam }
                    onTextChanged: view.query = text
                    Keys.onDownPressed: list.forceActiveFocus()
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !search.text
                           text: "Search by name or PID"; color: view.sys.colMuted; font { pixelSize: 12; family: view.sys.fontFam } }
                }
            }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: searchBox.verticalCenter; spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; visible: view.selPid > 0
                       text: view.selName + "  ·  " + view.selPid; color: view.sys.colMuted
                       font { pixelSize: 11; family: view.sys.fontFam } }
                Rectangle {
                    width: 100; height: 32; radius: view.rInner
                    opacity: view.selPid > 0 ? 1 : 0.35
                    color: endMa.pressed ? Qt.rgba(1, 1, 1, 0.8) : view.sys.colFg
                    Text { anchors.centerIn: parent; text: "End task"; color: view.sys.colBg; font { pixelSize: 12; bold: true; family: view.sys.fontBody } }
                    MouseArea { id: endMa; anchors.fill: parent; enabled: view.selPid > 0; cursorShape: Qt.PointingHandCursor
                                onClicked: view.signalSel("term") }
                }
            }

            // column headers with totals (static model: only their texts update)
            Item {
                id: cols
                anchors.top: searchBox.bottom; anchors.topMargin: 12
                width: parent.width; height: 40
                readonly property real wPid: 80
                readonly property real wCpu: 110
                readonly property real wMem: 130
                function colX(i) { return i === 0 ? 12 : i === 1 ? width - wMem - wCpu - wPid - 16 : i === 2 ? width - wMem - wCpu - 16 : width - wMem - 16; }
                function colW(i) { return i === 0 ? width - wMem - wCpu - wPid - 40 : i === 1 ? wPid : i === 2 ? wCpu : wMem; }
                function total(k) {
                    if (k === "cpu") return Math.round((view.snap.cpu || {}).total || 0) + "%";
                    if (k === "mem") return view.memNow.total ? Math.round(100 * view.memNow.used / view.memNow.total) + "%" : "";
                    return " ";
                }
                Repeater {
                    model: [{ k: "name", t: "Name" }, { k: "pid", t: "PID" }, { k: "cpu", t: "CPU" }, { k: "mem", t: "Memory" }]
                    delegate: Item {
                        required property var modelData
                        required property int index
                        x: cols.colX(index); width: cols.colW(index); height: cols.height
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; width: parent.width
                            Text { width: parent.width; horizontalAlignment: parent.parent.index === 0 ? Text.AlignLeft : Text.AlignRight
                                   text: cols.total(parent.parent.modelData.k); color: view.sys.colFg
                                   font { pixelSize: 13; bold: true; family: view.sys.fontBody } }
                            Text { width: parent.width; horizontalAlignment: parent.parent.index === 0 ? Text.AlignLeft : Text.AlignRight
                                   text: parent.parent.modelData.t + (view.sortKey === parent.parent.modelData.k ? (view.sortDesc ? "  ↓" : "  ↑") : "")
                                   color: view.sortKey === parent.parent.modelData.k ? view.sys.colFg : view.sys.colMuted
                                   font { pixelSize: 11; family: view.sys.fontBody } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.sortBy(parent.modelData.k) }
                    }
                }
            }

            ListView {
                id: list
                anchors.top: cols.bottom; anchors.topMargin: 4; anchors.bottom: parent.bottom
                width: parent.width
                clip: true; boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                model: procModel
                section.property: "group"
                section.delegate: Item {
                    required property string section
                    width: list.width; height: 34
                    Text { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                           text: ({ apps: "Apps", background: "Background processes", system: "System" })[parent.section] || parent.section
                           color: view.sys.colMuted; font { pixelSize: 11; bold: true; family: view.sys.fontBody; letterSpacing: 0.3 } }
                }
                Keys.onUpPressed: { if (currentIndex > 0) currentIndex--; }
                Keys.onDownPressed: { if (currentIndex < count - 1) currentIndex++; }
                Keys.onRightPressed: { var r = procModel.get(currentIndex); if (r && r.count && !r.open) view.toggleApp(r.pid); }
                Keys.onLeftPressed: { var r = procModel.get(currentIndex); if (r && r.count && r.open) view.toggleApp(r.pid); }
                onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex < procModel.count) { view.selPid = procModel.get(currentIndex).pid; view.selName = procModel.get(currentIndex).name; }
                ScrollBar.vertical: ScrollBar {
                    id: nub; policy: ScrollBar.AsNeeded; width: hovered || pressed ? 6 : 3; padding: 0
                    Behavior on width { NumberAnimation { duration: 120 } }
                    background: Item {}
                    contentItem: Rectangle { implicitWidth: 3; radius: width / 2; color: Qt.rgba(1, 1, 1, nub.pressed ? 0.55 : 0.32)
                                             opacity: nub.active || nub.hovered ? 1 : 0
                                             Behavior on opacity { NumberAnimation { duration: 260 } } }
                }
                delegate: Rectangle {
                    id: prow
                    required property int index
                    required property int pid
                    required property string name
                    required property string sub
                    required property string icon
                    required property real cpu
                    required property real mem
                    required property bool child
                    required property int count
                    required property bool open
                    readonly property bool chosen: view.selPid === pid
                    readonly property real indent: child ? 30 : 0
                    width: list.width - 8; height: child ? 30 : (sub ? 42 : 36); radius: view.rInner
                    color: chosen ? Qt.rgba(1, 1, 1, 0.11) : rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // expand arrow for apps that started more than one process
                    Text {
                        x: 4; anchors.verticalCenter: parent.verticalCenter; width: 14
                        visible: prow.count > 1; text: "›"; color: view.sys.colMuted
                        horizontalAlignment: Text.AlignHCenter
                        rotation: prow.open ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: 160 } }
                        font { pixelSize: 15; family: view.sys.fontBody }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: view.toggleApp(prow.pid) }
                    }
                    // the app's icon, or its initial on a soft tile
                    Item {
                        id: ic
                        x: 22 + prow.indent; anchors.verticalCenter: parent.verticalCenter
                        width: prow.child ? 16 : 22; height: width
                        Image {
                            id: icImg; anchors.fill: parent
                            source: view.iconSource(prow.icon)
                            sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true; asynchronous: true
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            anchors.fill: parent; radius: width * 0.3
                            visible: icImg.status !== Image.Ready
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Text { anchors.centerIn: parent; text: prow.name.charAt(0).toUpperCase(); color: view.sys.colMuted
                                   font { pixelSize: parent.width * 0.5; bold: true; family: view.sys.fontBody } }
                        }
                    }
                    Column {
                        anchors.left: ic.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - cols.wMem - cols.wCpu - cols.wPid - 40 - x
                        Text { width: parent.width; elide: Text.ElideRight
                               text: prow.name + (prow.count > 1 ? "  (" + prow.count + ")" : "")
                               color: prow.child ? view.sys.colMuted : view.sys.colFg
                               font { pixelSize: prow.child ? 11 : 12; family: view.sys.fontBody } }
                        Text { visible: prow.sub.length > 0; width: parent.width; elide: Text.ElideRight
                               text: prow.sub; color: view.sys.colMuted; font { pixelSize: 10; family: view.sys.fontBody } }
                    }
                    Text { x: cols.colX(1) - 4; width: cols.wPid; anchors.verticalCenter: parent.verticalCenter
                           horizontalAlignment: Text.AlignRight; text: prow.pid; color: view.sys.colMuted
                           font { pixelSize: 11; family: view.sys.fontFam } }
                    // cells that warm with load, like Windows' heat columns (in white)
                    Rectangle {
                        x: cols.colX(2) - 4 + 14; width: cols.wCpu - 14; height: parent.height - 8
                        anchors.verticalCenter: parent.verticalCenter; radius: view.rInner - 4
                        color: Qt.rgba(1, 1, 1, Math.min(0.28, prow.cpu / 100 * 0.6))
                        Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                               text: prow.cpu.toFixed(1) + "%"; color: prow.cpu > 0.05 ? view.sys.colFg : view.sys.colMuted
                               font { pixelSize: 11; family: view.sys.fontFam } }
                    }
                    Rectangle {
                        x: cols.colX(3) - 4 + 14; width: cols.wMem - 14; height: parent.height - 8
                        anchors.verticalCenter: parent.verticalCenter; radius: view.rInner - 4
                        color: Qt.rgba(1, 1, 1, Math.min(0.22, prow.mem / (view.memNow.total || 1) * 2))
                        Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                               text: view.fmtBytes(prow.mem); color: view.sys.colFg; font { pixelSize: 11; family: view.sys.fontFam } }
                    }
                    MouseArea {
                        id: rowMa; anchors.fill: parent; z: -1; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onDoubleClicked: if (prow.count > 1) view.toggleApp(prow.pid)
                        onClicked: mouse => {
                            list.currentIndex = prow.index; view.selPid = prow.pid; view.selName = prow.name; list.forceActiveFocus();
                            if (mouse.button === Qt.RightButton) {
                                var pt = mapToItem(view, mouse.x, mouse.y);
                                menu.x = Math.min(pt.x, view.width - menu.width - 4); menu.y = Math.min(pt.y, view.height - menu.height - 4);
                                menu.visible = true;
                            }
                        }
                    }
                }
            }
        }

        // ============================================================ performance
        Item {
            id: perf
            anchors.fill: parent
            opacity: view.tab === "performance" ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Flickable {
                id: devFlick
                width: 270; height: parent.height
                contentHeight: devList.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: devList
                    width: parent.width; spacing: 4
                    Repeater {
                        model: ["cpu", "mem", "igpu", "gpu", "disk", "net", "bat"]
                        delegate: Rectangle {
                            id: dev
                            required property string modelData
                            width: devList.width; height: 66; radius: view.rInner
                            color: view.device === modelData ? Qt.rgba(1, 1, 1, 0.1) : devMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Rectangle {
                                x: 10; anchors.verticalCenter: parent.verticalCenter; width: 70; height: 44; radius: 8
                                color: Qt.rgba(0, 0, 0, 0.35)
                                TasksChart { anchors.fill: parent; anchors.margins: 3; grid: false
                                             values: view.devHist(dev.modelData); values2: view.devHist2(dev.modelData); max: view.devMax(dev.modelData) }
                            }
                            Column {
                                x: 92; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 10; spacing: 1
                                Text { text: view.devTitle(dev.modelData); color: view.sys.colFg; font { pixelSize: 13; bold: true; family: view.sys.fontBody } }
                                Text { width: parent.width; elide: Text.ElideRight; text: view.devPart(dev.modelData); color: view.sys.colMuted
                                       font { pixelSize: 10; family: view.sys.fontBody } }
                                Text { width: parent.width; elide: Text.ElideRight; text: view.devValue(dev.modelData); color: view.sys.colFg
                                       font { pixelSize: 11; family: view.sys.fontFam } }
                            }
                            MouseArea { id: devMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: view.device = dev.modelData }
                        }
                    }
                }
            }

            Rectangle {
                id: detail
                anchors.left: devFlick.right; anchors.leftMargin: 14; anchors.right: parent.right
                height: parent.height; radius: view.boxR
                color: Qt.rgba(1, 1, 1, 0.04)
                Column {
                    x: 22; y: 18; width: parent.width - 44; spacing: 14
                    Item {
                        width: parent.width; height: 46
                        Text { id: dTitle; text: view.devTitle(view.device); color: view.sys.colFg; font { pixelSize: 24; bold: true; family: view.sys.fontBody } }
                        Text { anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 4
                               width: parent.width - dTitle.width - 20; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                               text: view.devPart(view.device); color: view.sys.colFg; font { pixelSize: 14; family: view.sys.fontBody } }
                        Text { anchors.bottom: parent.bottom; text: view.devValue(view.device); color: view.sys.colMuted; font { pixelSize: 12; family: view.sys.fontFam } }
                    }
                    Rectangle {
                        width: parent.width; height: view.device === "cpu" ? 220 : 270; radius: view.rInner; color: Qt.rgba(0, 0, 0, 0.35)
                        TasksChart { anchors.fill: parent; anchors.margins: 6
                                     values: view.devHist(view.device); values2: view.devHist2(view.device); max: view.devMax(view.device) }
                        Text { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 10
                               text: view.device === "disk" ? "read · write" : view.device === "net" ? "down · up" : view.device === "igpu" ? "clock" : "60 s"
                               color: view.sys.colMuted; font { pixelSize: 10; family: view.sys.fontBody } }
                        Text { anchors.centerIn: parent; visible: view.device === "gpu" && view.gpuNv && !view.gpuNv.awake
                               text: "The GPU is asleep. It isn't polled, so it can stay that way and save battery."
                               color: view.sys.colMuted; font { pixelSize: 12; family: view.sys.fontBody } }
                    }
                    // every thread, as a row of live bars (a fixed number of them: never rebuilt)
                    Row {
                        visible: view.device === "cpu"; spacing: 4; height: 50
                        Repeater {
                            model: view.snap.ncpu || 0
                            delegate: Rectangle {
                                required property int index
                                readonly property real v: ((view.snap.cpu || {}).cores || [])[index] || 0
                                width: Math.max(8, (detail.width - 44) / Math.max(1, view.snap.ncpu || 1) - 4)
                                height: 50; radius: 4; color: Qt.rgba(1, 1, 1, 0.06)
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; radius: 4
                                            height: Math.max(2, parent.height * parent.v / 100); color: Qt.rgba(1, 1, 1, 0.8)
                                            Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } } }
                            }
                        }
                    }
                    Grid {
                        width: parent.width; columns: 3; rowSpacing: 14; columnSpacing: 20
                        Repeater {
                            model: view.statKeys(view.device)
                            delegate: Column {
                                required property string modelData
                                width: (detail.width - 44 - 40) / 3; spacing: 3
                                Text { text: parent.modelData; color: view.sys.colMuted; font { pixelSize: 11; family: view.sys.fontBody } }
                                Text { width: parent.width; elide: Text.ElideRight; text: view.stat(view.device, parent.modelData)
                                       color: view.sys.colFg; font { pixelSize: 15; bold: true; family: view.sys.fontBody } }
                            }
                        }
                    }
                }
            }
        }

        // ============================================================ services
        Item {
            anchors.fill: parent
            opacity: view.tab === "services" ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Rectangle {
                id: unitSearch
                width: Math.min(360, parent.width * 0.4); height: 36; radius: view.rInner
                color: unitInput.activeFocus ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(1, 1, 1, 0.055)
                TextInput {
                    id: unitInput
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter; clip: true
                    color: view.sys.colFg; font { pixelSize: 12; family: view.sys.fontFam }
                    onTextChanged: view.unitQuery = text
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !unitInput.text
                           text: "Search services"; color: view.sys.colMuted; font { pixelSize: 12; family: view.sys.fontFam } }
                }
            }
            Text { anchors.right: parent.right; anchors.verticalCenter: unitSearch.verticalCenter
                   text: "System services ask for your password"; color: view.sys.colMuted; font { pixelSize: 11; family: view.sys.fontBody } }
            ListView {
                id: unitList
                anchors.top: unitSearch.bottom; anchors.topMargin: 12; anchors.bottom: parent.bottom
                width: parent.width; clip: true; spacing: 2; boundsBehavior: Flickable.StopAtBounds
                model: unitModel
                section.property: "scope"
                section.delegate: Item {
                    required property string section
                    width: unitList.width; height: 32
                    Text { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                           text: parent.section === "user" ? "Your services" : "System services"
                           color: view.sys.colMuted; font { pixelSize: 11; bold: true; family: view.sys.fontBody; letterSpacing: 0.3 } }
                }
                ScrollBar.vertical: ScrollBar {
                    id: nub3; policy: ScrollBar.AsNeeded; width: hovered || pressed ? 6 : 3; padding: 0
                    background: Item {}
                    contentItem: Rectangle { implicitWidth: 3; radius: width / 2; color: Qt.rgba(1, 1, 1, nub3.pressed ? 0.55 : 0.32)
                                             opacity: nub3.active || nub3.hovered ? 1 : 0
                                             Behavior on opacity { NumberAnimation { duration: 260 } } }
                }
                delegate: Rectangle {
                    id: urow
                    required property string scope
                    required property string unit
                    required property string active
                    required property string sub
                    required property string desc
                    readonly property var modelData: ({ scope: scope, unit: unit, active: active, sub: sub, desc: desc })
                    width: unitList.width - 8; height: 44; radius: view.rInner
                    color: uMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                    MouseArea { id: uMa; anchors.fill: parent; hoverEnabled: true }
                    Rectangle { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5
                                color: urow.modelData.active === "active" ? view.sys.colFg
                                     : urow.modelData.active === "failed" ? view.sys.colCrit : Qt.rgba(1, 1, 1, 0.22) }
                    Column {
                        x: 32; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 290
                        Text { width: parent.width; elide: Text.ElideRight; text: urow.modelData.unit.replace(/\.service$/, "")
                               color: view.sys.colFg; font { pixelSize: 12; family: view.sys.fontBody } }
                        Text { width: parent.width; elide: Text.ElideRight; text: urow.modelData.desc
                               color: view.sys.colMuted; font { pixelSize: 10; family: view.sys.fontBody } }
                    }
                    Text { anchors.right: btns.left; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                           text: urow.modelData.sub; color: urow.modelData.active === "failed" ? view.sys.colCrit : view.sys.colMuted
                           font { pixelSize: 11; family: view.sys.fontFam } }
                    Row {
                        id: btns
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        opacity: uMa.containsMouse || hoverBtn ? 1 : 0
                        property bool hoverBtn: false
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Repeater {
                            model: urow.modelData.active === "active" ? ["restart", "stop"] : ["start"]
                            delegate: Rectangle {
                                required property string modelData
                                width: 72; height: 28; radius: view.rInner - 2
                                color: bMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                                Text { anchors.centerIn: parent
                                       text: view.busyAction === urow.modelData.unit + ":" + parent.modelData ? "···"
                                           : parent.modelData.charAt(0).toUpperCase() + parent.modelData.slice(1)
                                       color: view.sys.colFg; font { pixelSize: 11; family: view.sys.fontBody } }
                                MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onContainsMouseChanged: btns.hoverBtn = containsMouse
                                            onClicked: view.unitAction(urow.modelData, parent.modelData) }
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ right-click menu
    MouseArea { anchors.fill: parent; visible: menu.visible; z: 40; onClicked: menu.visible = false }
    Rectangle {
        id: menu
        visible: false; z: 41
        width: 180; height: menuCol.implicitHeight + 12; radius: view.rInner + 2
        color: Qt.rgba(0.08, 0.08, 0.08, 0.98)
        Column {
            id: menuCol; x: 6; y: 6; width: parent.width - 12
            Repeater {
                model: [{ t: "End task", a: "term" }, { t: "Force kill", a: "kill" }, { t: "Copy PID", a: "copy" }]
                delegate: Rectangle {
                    required property var modelData
                    width: menuCol.width; height: 32; radius: view.rInner - 2
                    color: mMa.containsMouse ? (modelData.a === "kill" ? Qt.rgba(0.84, 0.1, 0.13, 0.22) : Qt.rgba(1, 1, 1, 0.08)) : "transparent"
                    Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.t
                           color: parent.modelData.a === "kill" ? view.sys.colCrit : view.sys.colFg
                           font { pixelSize: 12; family: view.sys.fontBody } }
                    MouseArea { id: mMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (parent.modelData.a === "copy") { copyProc.command = ["wl-copy", String(view.selPid)]; copyProc.running = true; menu.visible = false; }
                                    else view.signalSel(parent.modelData.a);
                                } }
                }
            }
        }
    }
    Process { id: copyProc }
}
