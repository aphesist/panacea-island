import QtQuick
import Quickshell
import Quickshell.Io

// A voice wave, ChatGPT-style: a row of rounded bars that scrolls right to left, one new bar
// per tick from the microphone's loudness above the room's noise floor
// (scripts/custom/mic-level.py, run only while listening). Silence is a dotted baseline.
// `listening` feeds it live; `busy` (transcribing) turns it into a soft travelling ripple.
// The bars take the icons' grey (`muted`) and fade out at both ends. Fills whatever size it gets.
Item {
    id: vw
    property var sys
    readonly property var t: sys.pk
    property bool listening: false
    property bool busy: false
    property color color: t.muted
    property real barW: 3
    property real gap: 3
    property int tickMs: 55
    property real fade: Math.min(56, width * 0.18)     // px over which each end fades out
    readonly property int count: Math.max(6, Math.floor((width + vw.gap) / (vw.barW + vw.gap)))

    property var hist: []          // 0..1, newest last
    property real peak: 0          // loudest reading since the last tick
    property real phase: 0

    Process {
        running: vw.listening
        command: ["python3", "-I", Quickshell.env("HOME") + "/.config/panacea/scripts/custom/mic-level.py"]
        stdout: SplitParser {
            onRead: data => { var v = parseFloat(data); if (v > vw.peak) vw.peak = v; }
        }
    }

    Timer {
        interval: vw.tickMs; repeat: true
        running: vw.visible && (vw.listening || vw.busy || vw.hist.some(function (v) { return v > 0.02; }))
        onTriggered: {
            var h = vw.hist.slice();
            h.push(vw.listening ? vw.peak : 0);
            vw.peak = 0;
            while (h.length > vw.count) h.shift();
            vw.hist = h;
            vw.phase += 0.35;
            cv.requestPaint();
        }
    }
    onCountChanged: cv.requestPaint()
    onBusyChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var H = height, W = width, bw = vw.barW, step = bw + vw.gap, n = vw.count;
            var x0 = (W - (n * step - vw.gap)) / 2;           // centred; newest at the right
            ctx.fillStyle = vw.color;
            for (var i = 0; i < n; i++) {
                var k = vw.hist.length - n + i;
                var v = k >= 0 ? vw.hist[k] : 0;
                if (vw.busy)
                    v = Math.max(v, 0.16 + 0.12 * Math.sin(vw.phase - i * 0.45));
                var h = Math.max(bw, Math.min(H, v * H));
                var x = x0 + i * step, y = (H - h) / 2, r = bw / 2;
                // both ends fade out (smoothstep over `fade` px); silence dots are fainter still
                var e = Math.min(1, Math.min(x + bw / 2, W - x - bw / 2) / Math.max(1, vw.fade));
                e = e * e * (3 - 2 * e);
                ctx.globalAlpha = e * (v > 0.02 ? 1 : 0.55);
                ctx.beginPath();
                ctx.moveTo(x + r, y);
                ctx.arcTo(x + bw, y, x + bw, y + h, r);
                ctx.arcTo(x + bw, y + h, x, y + h, r);
                ctx.arcTo(x, y + h, x, y, r);
                ctx.arcTo(x, y, x + bw, y, r);
                ctx.closePath();
                ctx.fill();
            }
        }
    }
}
