import QtQuick
import QtQuick.Layouts

// A level ring (battery, signal): track, a white arc that grows in when `active` turns on,
// red when `low`; the percentage inside. Used by the island's status toasts.
Item {
    property var sys
    readonly property var t: sys.pk
    id: ring
    property real level: 0        // 0..1
    property bool low: false
    property bool active: false
    property real fill: 0
    implicitWidth: 28; implicitHeight: 28
    onActiveChanged: if (active) { anim.stop(); fill = 0; anim.from = 0; anim.to = level; anim.start(); }
    onLevelChanged: if (active) { anim.stop(); anim.from = fill; anim.to = level; anim.start(); }
    onFillChanged: cv.requestPaint()
    NumberAnimation { id: anim; target: ring; property: "fill"; duration: ring.sys.noMotion ? 0 : 900; easing.type: Easing.OutCubic }
    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            var w = 3, r = (Math.min(width, height) - w) / 2, cx = width / 2, cy = height / 2;
            ctx.lineWidth = w; ctx.lineCap = "round";
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.strokeStyle = ring.t.track; ctx.stroke();
            if (ring.fill > 0) {
                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * ring.fill);
                ctx.strokeStyle = ring.low ? ring.t.accent : ring.t.on; ctx.stroke();
            }
        }
    }
    Text {
        anchors.centerIn: parent
        text: String(Math.round(ring.level * 100))
        color: ring.low ? ring.t.accentText : ring.t.fg
        font { family: ring.t.font; pixelSize: 9; weight: Font.DemiBold }
    }
}
