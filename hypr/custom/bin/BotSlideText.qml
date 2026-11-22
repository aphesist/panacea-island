import QtQuick

// A line of text that changes without a jump. A new `key` (another bot) slides: the old line
// leaves towards -dir as the new one comes in from +dir. The same key (a state word, a new last
// message) cross-fades in place. A change during a change waits for it (only the latest is kept).
// Each line keeps its own colour while it fades.
Item {
    id: st
    property var sys
    readonly property var t: sys.pk
    property var clock: sys ? sys.clock : null
    property string text: ""
    property string key: ""
    property color color: t.fg
    property int weight: Font.Normal
    property int px: t.tBody
    property int dir: 1
    property int align: Text.AlignHCenter
    implicitHeight: a.implicitHeight

    property string _old: ""
    property string _cur: ""
    property color _oldCol: color
    property color _curCol: color
    property string _key: ""
    property real _p: 1                  // 0..1 through the change
    property string _mode: "fade"
    property int _dir: 1
    property bool _queued: false
    readonly property real _dur: _mode === "slide" ? 0.34 : 0.24

    function _c(c) { return Qt.rgba(c.r, c.g, c.b, c.a); }
    function _start() {
        _queued = false;
        if (text === _cur && Qt.colorEqual(color, _curCol)) return;
        _mode = key !== _key ? "slide" : "fade"; _dir = dir;
        _old = _cur; _oldCol = _c(_curCol);
        _cur = text; _curCol = _c(color); _key = key;
        _p = t.still ? 1 : 0;
    }
    function _change() { if (_p < 1) _queued = true; else _start(); }
    onTextChanged: Qt.callLater(_change)
    onColorChanged: Qt.callLater(_change)
    onKeyChanged: Qt.callLater(_change)
    Component.onCompleted: { _cur = text; _curCol = _c(color); _key = key; }

    BotTick { clock: st.clock; active: st._p < 1
              onTick: function (dt) { st._p = Math.min(1, st._p + dt / st._dur); if (st._p >= 1 && st._queued) st._start(); } }
    function _e(x) { var q = Math.max(0, Math.min(1, x)); return q * q * q * (q * (q * 6 - 15) + 10); }

    Text { id: a; width: st.width; horizontalAlignment: st.align; elide: Text.ElideRight; maximumLineCount: 1
           text: st._cur; color: st._curCol; font { family: st.t.font; pixelSize: st.px; weight: st.weight }
           opacity: st._mode === "slide" ? st._e((st._p - 0.15) / 0.85) : st._e(st._p)
           x: st._mode === "slide" ? 26 * st._dir * (1 - st._e(st._p)) : 0 }
    Text { width: st.width; horizontalAlignment: st.align; elide: Text.ElideRight; maximumLineCount: 1
           visible: st._p < 1
           text: st._old; color: st._oldCol; font { family: st.t.font; pixelSize: st.px; weight: st.weight }
           opacity: st._mode === "slide" ? 1 - st._e(st._p / 0.6) : 1 - st._e(st._p)
           x: st._mode === "slide" ? -26 * st._dir * st._e(st._p) : 0 }
}
