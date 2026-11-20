import QtQuick

// written by portal-patch.py (panacea-config) - a live history chart for the task manager.
// values: newest last. values2: an optional second, dimmer series (network upload).
// max: fixed top (100 for percentages) or 0 to scale to the data.
Canvas {
    id: chart
    property var values: []
    property var values2: []
    property real max: 100
    property color tint: "white"
    property bool grid: true
    property int points: 60
    readonly property real ceiling: {
        if (max > 0) return max;
        var m = 1;
        for (var i = 0; i < values.length; i++) m = Math.max(m, values[i]);
        for (var j = 0; j < values2.length; j++) m = Math.max(m, values2[j]);
        return m * 1.15;
    }
    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    renderStrategy: Canvas.Cooperative

    function series(ctx, vals, fillA, lineA) {
        if (!vals || vals.length < 2) return;
        var n = vals.length, step = width / (points - 1), x0 = width - (n - 1) * step;
        ctx.beginPath();
        for (var i = 0; i < n; i++) {
            var x = x0 + i * step, y = height - Math.min(1, vals[i] / ceiling) * (height - 2) - 1;
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        ctx.lineWidth = 1.5; ctx.lineJoin = "round";
        ctx.strokeStyle = Qt.rgba(tint.r, tint.g, tint.b, lineA);
        ctx.stroke();
        if (fillA > 0) {
            ctx.lineTo(width, height); ctx.lineTo(x0, height); ctx.closePath();
            var g = ctx.createLinearGradient(0, 0, 0, height);
            g.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, fillA));
            g.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0));
            ctx.fillStyle = g; ctx.fill();
        }
    }
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (grid) {
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.05); ctx.lineWidth = 1;
            for (var k = 1; k < 4; k++) {
                var y = Math.round(height * k / 4) + 0.5;
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
            }
        }
        series(ctx, values2, 0, 0.4);
        series(ctx, values, 0.18, 0.95);
    }
}
