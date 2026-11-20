pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-island) - Calculator, an island screen built from the Pk kit.
// Type or click; the result shows live under the expression, = keeps it. Click the result to copy
// it. History (the clock) keeps the last 40 sums in ~/.local/state/panacea-calc.json.
// Keys: digits . + - * / ^ % ( ), Enter or =, Backspace, Delete (clear), Esc (clear, then close),
// Ctrl+C (copy the result). The maths is a small parser of its own: nothing is ever eval'd.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    implicitHeight: col.implicitHeight

    property string expr: ""          // what's typed, with the display signs × ÷ −
    property bool done: false         // = was pressed: the next digit starts over
    property bool showHistory: false
    property var history: []          // [{ e: expression, r: result }], newest first
    property bool copied: false
    readonly property var preview: evaluate(expr)
    readonly property string shown: done ? fmt(evaluate(expr) || 0) : preview === null || !/[+−×÷^%(]/.test(expr.slice(1)) ? "" : fmt(preview)

    focus: true
    Component.onCompleted: forceActiveFocus()

    // ---- the maths -------------------------------------------------------------------------
    // grammar: sum = term (('+'|'-') term)* ; term = unary (('*'|'/'|implicit) unary)* ;
    //          unary = '-' unary | power ; power = atom '%'* ('^' unary)? ;
    //          atom = number | '(' sum ')'      (missing ')' at the end are closed for the preview)
    function evaluate(s) {
        const src = s.replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/\s+/g, "");
        if (src === "") return null;
        const toks = [];
        for (let i = 0; i < src.length;) {
            const c = src[i];
            if (/[0-9.]/.test(c)) {
                let j = i; while (j < src.length && /[0-9.]/.test(src[j])) j++;
                if (src[j] === "e" && /[-+0-9]/.test(src[j + 1] || "")) {          // 1.5e-7 (a result fed back)
                    j++; if (/[-+]/.test(src[j])) j++; while (j < src.length && /[0-9]/.test(src[j])) j++;
                }
                const n = Number(src.slice(i, j)); if (isNaN(n)) return null;
                toks.push({ n: n }); i = j;
            } else if ("+-*/^%()".indexOf(c) >= 0) { toks.push({ o: c }); i++; }
            else return null;
        }
        let p = 0;
        const peek = () => toks[p], isOp = (o) => toks[p] && toks[p].o === o;
        function sum() {
            let v = term(); if (v === null) return null;
            while (isOp("+") || isOp("-")) { const o = toks[p++].o; const r = term(); if (r === null) return null; v = o === "+" ? v + r : v - r; }
            return v;
        }
        function term() {
            let v = unary(); if (v === null) return null;
            for (;;) {
                if (isOp("*") || isOp("/")) { const o = toks[p++].o; const r = unary(); if (r === null) return null; v = o === "*" ? v * r : v / r; }
                else if (peek() && (peek().n !== undefined || peek().o === "(")) { const r = unary(); if (r === null) return null; v *= r; }   // 2(3), (1)(2)
                else return v;
            }
        }
        function unary() {                    // −3^2 = −9, 2^−1 = 0.5
            if (isOp("-")) { p++; const v = unary(); return v === null ? null : -v; }
            if (isOp("+")) { p++; return unary(); }
            return power();
        }
        function power() {
            let b = atom(); if (b === null) return null;
            while (isOp("%")) { p++; b /= 100; }
            if (isOp("^")) { p++; const e = unary(); if (e === null) return null; return Math.pow(b, e); }
            return b;
        }
        function atom() {
            const k = peek(); if (!k) return null;
            if (k.n !== undefined) { p++; return k.n; }
            if (k.o === "(") {
                p++;
                const v = sum(); if (v === null) return null;
                if (isOp(")")) p++; else if (p < toks.length) return null;
                return v;
            }
            return null;
        }
        const v = sum();
        if (v === null || p < toks.length || !isFinite(v)) return null;
        return v;
    }
    function fmt(v) {
        if (v === 0) return "0";
        const a = Math.abs(v);
        if (a >= 1e15 || a < 1e-9) return v.toExponential(8).replace(/\.?0+e/, "e").replace("e+", "e");
        let s = String(Number(v.toPrecision(12)));
        if (s.indexOf("e") >= 0) return s;
        const neg = s[0] === "-"; if (neg) s = s.slice(1);
        const parts = s.split(".");
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return (neg ? "−" : "") + parts.join(".");
    }
    function raw(v) { return String(Number(v.toPrecision(12))).replace("-", "−"); }    // a result to keep typing on

    // ---- input -------------------------------------------------------------------------------
    function press(k) {
        copied = false;
        const last = expr.slice(-1);
        const ops = "+−×÷^";
        if (k === "AC") { expr = ""; done = false; return; }
        if (k === "back") { if (done) { done = false; } expr = expr.slice(0, -1); return; }
        if (k === "=") {
            const v = evaluate(expr); if (v === null || done) return;
            const open = (expr.match(/\(/g) || []).length - (expr.match(/\)/g) || []).length;
            const e = expr + ")".repeat(Math.max(0, open));
            history = [{ e: e, r: fmt(v) }].concat(history).slice(0, 40);
            saveHistory();
            expr = raw(v); done = true; return;
        }
        if (/^[0-9]$/.test(k) || k === ".") {
            if (done) { expr = ""; done = false; }
            if (k === ".") {
                const num = expr.match(/[0-9.]*$/)[0];
                if (num.indexOf(".") >= 0) return;
                if (num === "") k = "0.";
            }
            if (last === ")" || last === "%") k = "×" + k;
            expr += k; return;
        }
        done = false;
        if (ops.indexOf(k) >= 0) {
            if (expr === "" && k !== "−") return;
            if (ops.indexOf(last) >= 0 && last !== "" ) {
                if (k === "−" && last !== "−" && last !== "+") { expr += k; return; }      // 5×−2
                expr = expr.slice(0, -1) + k; return;
            }
            if (last === "(" && k !== "−") return;
            expr += k; return;
        }
        if (k === "%") { if (expr !== "" && /[0-9)]/.test(last)) expr += "%"; return; }
        if (k === "(") { if (/[0-9)%]/.test(last)) expr += "×"; expr += "("; return; }
        if (k === ")") {
            const open = (expr.match(/\(/g) || []).length - (expr.match(/\)/g) || []).length;
            if (open > 0 && /[0-9)%]/.test(last)) expr += ")";
            return;
        }
        if (k === "()") {      // one key: opens, or closes when a bracket is open and a number ends the line
            const open = (expr.match(/\(/g) || []).length - (expr.match(/\)/g) || []).length;
            press(open > 0 && /[0-9)%]/.test(last) ? ")" : "("); return;
        }
    }
    function copyResult() {
        if (view.shown === "") return;
        Quickshell.execDetached(["wl-copy", view.shown.replace(/,/g, "").replace("−", "-")]);
        view.copied = true; copiedTimer.restart();
    }
    Timer { id: copiedTimer; interval: 1400; onTriggered: view.copied = false }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key === Qt.Key_C) { copyResult(); event.accepted = true; return; }
        if (ctrl && event.key === Qt.Key_V) { pasteProc.running = true; event.accepted = true; return; }
        if (ctrl && event.key === Qt.Key_H) { showHistory = !showHistory; event.accepted = true; return; }
        if (ctrl) return;
        const map = { "*": "×", "x": "×", "/": "÷", "-": "−", "+": "+", "^": "^", "%": "%", "(": "(", ")": ")", ",": ".", ".": ".", "=": "=" };
        let k = null;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) k = "=";
        else if (event.key === Qt.Key_Backspace) k = "back";
        else if (event.key === Qt.Key_Delete) k = "AC";
        else if (event.key === Qt.Key_Escape) {
            if (showHistory) showHistory = false; else if (expr !== "") press("AC"); else view.sys.collapse();
            event.accepted = true; return;
        }
        else if (/^[0-9]$/.test(event.text)) k = event.text;
        else if (map[event.text] !== undefined) k = map[event.text];
        if (k !== null) { press(k); flash(k); event.accepted = true; }
    }
    property string lit: ""                   // the key that was just typed lights up
    function flash(k) { lit = k === "(" || k === ")" ? "()" : k; litTimer.restart(); }
    Timer { id: litTimer; interval: 110; onTriggered: view.lit = "" }

    Process {                                 // Ctrl+V: numbers and signs from the clipboard
        id: pasteProc; command: ["wl-paste", "-n"]
        stdout: StdioCollector { onStreamFinished: {
            const s = text.replace(/[*]/g, "×").replace(/\//g, "÷").replace(/-/g, "−").replace(/[, _]/g, "").replace(/[^0-9.+−×÷^%()]/g, "");
            if (s !== "") { if (view.done) { view.expr = ""; view.done = false; } view.expr += s; }
        } }
    }

    // ---- history file ------------------------------------------------------------------------
    FileView {
        id: histFile
        path: Quickshell.env("HOME") + "/.local/state/panacea-calc.json"
        printErrors: false
        onLoaded: { try { const h = JSON.parse(text()); if (Array.isArray(h)) view.history = h; } catch (e) {} }
    }
    function saveHistory() { histFile.setText(JSON.stringify(history)); }

    // ---- the page ----------------------------------------------------------------------------
    readonly property int keyH: 50
    Column {
        id: col
        width: parent.width
        spacing: view.t.s3

        PkHeader {
            sys: view.sys; width: parent.width; title: view.showHistory ? "History" : "Calculator"
            back: view.showHistory; onBackClicked: view.showHistory = false
            PkIconButton { sys: view.sys; icon: "trash"; size: view.t.iMd; visible: view.showHistory && view.history.length > 0
                           onClicked: { view.history = []; view.saveHistory(); } }
            PkIconButton { sys: view.sys; icon: "clock-counter-clockwise"; size: view.t.iMd; selected: view.showHistory
                           visible: !view.showHistory; onClicked: view.showHistory = true }
        }

        // the display: the expression, and the result under it
        Rectangle {
            width: parent.width; height: 112; radius: view.t.rSurface
            color: view.t.surface
            visible: !view.showHistory
            Text {
                id: exprText
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                text: view.done ? (view.history.length ? view.history[0].e + " =" : "") : (view.expr === "" ? "0" : view.expr)
                color: view.done ? view.t.muted : view.expr === "" ? view.t.faint : view.t.fg
                font { family: view.t.font; pixelSize: view.done ? view.t.tEmph : 22 }
                Behavior on font.pixelSize { NumberAnimation { duration: view.t.dBase; easing.type: Easing.OutCubic } }
            }
            Text {
                id: resText
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                horizontalAlignment: Text.AlignRight
                text: view.copied ? "Copied" : view.shown === "" ? " " : (view.done ? "" : "= ") + view.shown
                color: view.copied ? view.t.soft : view.done ? view.t.fg : view.t.muted
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 16
                font { family: view.t.font; pixelSize: view.done ? view.t.tDisplay : 24; weight: view.done ? Font.Medium : Font.Normal }
                Behavior on font.pixelSize { NumberAnimation { duration: view.t.dBase; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent; enabled: view.shown !== ""
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: view.copyResult()
            }
        }

        // the keypad
        Grid {
            id: pad
            visible: !view.showHistory
            width: parent.width; columns: 4; spacing: view.t.gap
            readonly property real keyW: (width - 3 * spacing) / 4
            Repeater {
                model: [
                    { k: "AC", kind: "fn" }, { k: "()", kind: "fn" }, { k: "%", icon: "percent", kind: "fn" }, { k: "÷", icon: "divide", kind: "op" },
                    { k: "7" }, { k: "8" }, { k: "9" }, { k: "×", icon: "x", kind: "op" },
                    { k: "4" }, { k: "5" }, { k: "6" }, { k: "−", icon: "minus", kind: "op" },
                    { k: "1" }, { k: "2" }, { k: "3" }, { k: "+", icon: "plus", kind: "op" },
                    { k: "0" }, { k: "." }, { k: "back", icon: "backspace", kind: "fn" }, { k: "=", icon: "equals", kind: "eq" }
                ]
                delegate: Rectangle {
                    id: key
                    required property var modelData
                    readonly property string kind: modelData.kind || "num"
                    readonly property bool down: ma.pressed || view.lit === modelData.k
                    readonly property bool opNext: kind === "op" && !view.done && view.expr.slice(-1) === modelData.k
                    width: pad.keyW; height: view.keyH; radius: view.t.rControl
                    color: kind === "eq" ? (down ? Qt.darker(view.t.accent, 1.25) : view.t.accent)
                         : kind === "op" ? (opNext ? view.t.on : down ? view.t.pressed : view.t.selected)
                         : down ? view.t.pressed : ma.containsMouse ? view.t.veil(0.11) : kind === "fn" ? view.t.veil(0.05) : view.t.surface
                    scale: down ? 0.96 : 1
                    Behavior on color { ColorAnimation { duration: view.t.dFast } }
                    Behavior on scale { NumberAnimation { duration: view.t.dFast; easing.type: Easing.OutCubic } }
                    PkIcon { sys: view.sys; anchors.centerIn: parent; visible: !!key.modelData.icon; name: key.modelData.icon || "circle"
                             size: view.t.iMd
                             color: key.opNext ? view.t.onInk : key.kind === "fn" ? view.t.soft : view.t.fg }
                    Text {
                        anchors.centerIn: parent; visible: !key.modelData.icon
                        text: key.modelData.k === "()" ? "( )" : key.modelData.k
                        color: key.kind === "fn" ? view.t.soft : view.t.fg
                        font { family: view.t.font; pixelSize: key.kind === "fn" ? view.t.tEmph : 20 }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { view.press(key.modelData.k); view.forceActiveFocus(); } }
                }
            }
        }

        // history: click one to use its result
        Item {
            visible: view.showHistory
            width: parent.width
            height: 112 + view.t.s3 + 5 * view.keyH + 4 * view.t.gap      // the same room as the display + keypad
            PkText { sys: view.sys; role: "sub"; anchors.centerIn: parent; visible: view.history.length === 0; text: "Nothing calculated yet" }
            Flickable {
                id: histList
                anchors.fill: parent; clip: true
                contentHeight: histCol.height; boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: histCol
                    width: parent.width; spacing: 2
                    Repeater {
                        model: view.history
                        delegate: Rectangle {
                            id: hrow
                            required property var modelData
                            width: histCol.width; height: 58; radius: view.t.rControl
                            color: hma.containsMouse ? view.t.hover : "transparent"
                            Column {
                                anchors { left: parent.left; right: parent.right; margins: 12; verticalCenter: parent.verticalCenter }
                                spacing: 3
                                Text { width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                                       text: hrow.modelData.e; color: view.t.muted; font { family: view.t.font; pixelSize: view.t.tLabel } }
                                Text { width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                                       text: "= " + hrow.modelData.r; color: view.t.fg; font { family: view.t.font; pixelSize: 18 } }
                            }
                            MouseArea {
                                id: hma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const r = hrow.modelData.r.replace(/,/g, "");
                                    if (view.done || view.expr === "") view.expr = r;
                                    else view.expr += (/[0-9.)%]$/.test(view.expr) ? "×" : "") + r;
                                    view.done = false; view.showHistory = false; view.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                visible: histList.contentHeight > histList.height && !histList.atYEnd
                anchors.bottom: parent.bottom; width: parent.width; height: 36
                gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: view.t.bg } }
            }
        }
    }
}
