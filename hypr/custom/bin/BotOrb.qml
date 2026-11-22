import QtQuick
import QtQuick.Shapes

// A boopis bot's face: orb2's look and motion (aphesist/orb2), played from recorded vector frames
// (OrbStore). Shape and colour are the bot's; the eyes follow its state (`reaction`, boopis's one
// state map: idle listening thinking working compute speaking needs done error sleeping).
//
//   BotOrb { store: sys.orbs; botId: bot.id; shape: bot.shape; color: bot.color; reaction: bot.reaction }
//
// Smoothness rules (every frame continuous with the one before):
// - Frames are interpolated: the recording is 30 fps (60 for the spin); bodies always lerp point
//   to point, eyes lerp whenever two frames have the same structure.
// - A state change starts from what is on screen, never from a clip's first frame: the body morphs
//   from the current pose (a quintic ease, at rest at both ends), the eyes cross-fade if they are alike or blink
//   (squash to a capsule and open as the new eyes, orb2's own heavy blink) if not, sliding to the
//   new gaze. Into a state from idle and back to idle use orb2's recorded morphs; the loop after
//   them starts at its best-matching frame.
// - A change that arrives during a morph waits for it (only the latest is kept).
// - A new `botId` plays the 360 degree turntable spin: while the face is at the back the silhouette
//   morphs into the next bot's and the colour blends. A second bot change early in a spin retargets
//   it; later, the next spin follows from the rest pose the spin ends on (spins start and end there).
// - `live: false` holds the current frame (a collapsed island: no loop ticking, so no wakeups);
//   transitions and spins still play.
Item {
    id: orb
    property var store
    property string botId: ""
    property string shape: "circle"
    property color color: "#4fc9a8"
    property color eyeColor: "#141418"
    property string reaction: "idle"
    property bool live: true
    // aliveness by size: big orbs (stage, chat, cards) loop and have orb2's quiet life (breathing,
    // blinks, slow look-arounds, small tilts; fully active only while working); small ones (tab,
    // header, pill) hold still apart from their state's face and colour, and change bot without a spin.
    property int alive: -1                         // -1 by size, 0 static, 1 alive
    property real lifeScale: 1                     // 0: the life eases out (the flying hero)
    property bool still: false                     // Reduce motion
    readonly property bool small: alive === 0 || (alive < 0 && size < 44)
    readonly property bool _loop: live && !small
    property real size: 64
    property real speed: 1
    property int dir: 1
    property bool manualClock: false              // tests: step(dt) drives it instead of the frame clock
    property var clock: null                       // or a shared clock (BotTick): clock.manual + clock.tick(dt)
    Connections { target: orb.clock && orb.clock.manual ? orb.clock : null; function onTick(dt) { orb._tick(dt * orb.speed); } }
    signal cycled()                                // a bot-change spin finished

    width: size; height: size

    readonly property var _kn: ["idle", "listening", "thinking", "working", "compute", "speaking",
                                "needs", "done", "error", "sleeping"]
    function _r(r) { return _kn.indexOf(r) >= 0 ? r : "idle"; }
    function _clipOf(d, n) { return d && d.clips ? d.clips[n] : null; }

    // ---- what plays ---------------------------------------------------------------------------
    property var _data: null
    property string _shapeShown: ""
    property string _bot: ""
    property var _src: null                        // {clip, t}: the stream
    property string _shown: "idle"                 // the state the face is in or heading to
    property var _blend: null                      // {snap, t, T, mode: "fade"|"blink"}
    property string _pending: ""                   // a state change waiting for the morph to end
    property var _spin: null                       // {a, b, ca, cb, shape, reaction, t, d}
    property var _nextSpin: null                   // a bot change waiting for the spin to end
    property color _col: color
    property color _base: color                    // the colour drawn when nothing is changing
    property var _colFade: null                    // {from, t}: the same bot's colour changing
    property var _last: null                       // the frame on screen: {b, g, ec}
    property var _vel: null                        // its velocity per second: {b, ec} (blends carry it)
    property real _dt: 1 / 60

    function _load() {
        if (!store) return;
        _data = store.get(shape); _shapeShown = shape; _bot = botId; _col = color; _base = color;
        _shown = _r(reaction);
        _src = { clip: _shown, t: 0 };
        _blend = null; _pending = ""; _spin = null; _nextSpin = null; _colFade = null; _vel = null;
        _render();
    }
    // instantBot: a bot change is a new identity, never animated (the Bots tab's flying orb, the
    // chats' orbs): shape, colour and state are the new bot's from the very next frame
    property bool instantBot: false
    // be the bot the inputs say, now (no deferred sync, no morph): call before taking over a frame
    function jump() { if (store && (_data === null || botId !== _bot || shape !== _shapeShown || !Qt.colorEqual(color, _base))) _load(); }
    // inputs change one by one when the parent switches bots: settle once, after all of them
    function _sync() {
        if (!store) return;
        if (_data === null) { _load(); return; }
        if (botId !== _bot) { if (instantBot) { _load(); return; } _bot = botId; if (small) _swapBot(); else _requestSpin(); return; }
        if (_spin) {
            if (_spin.t < 0.3) { _spin.shape = shape; _spin.b = store.get(shape); _spin.cb = _copy(color); }
            return;
        }
        if (shape !== _shapeShown) {                // the same bot's new look: a blended change
            var snap = _snapshot();
            _data = store.get(shape); _shapeShown = shape;
            _src = { clip: _shown, t: 0 };
            _startBlend(snap, _frameNow(), 0.34);
        }
        if (!Qt.colorEqual(color, _base)) { _colFade = { from: _copy(_col), t: 0 }; _base = color; }
    }
    Component.onCompleted: { _reseed(); _load(); }
    // deferred with child timers, not Qt.callLater: they die with the orb (a card's orb can go
    // before a queued call runs)
    Timer { id: syncLater; interval: 0; onTriggered: orb._sync() }
    Timer { id: reactLater; interval: 0; onTriggered: orb._react() }
    onStoreChanged: syncLater.restart()
    onBotIdChanged: { if (instantBot) jumpLater.restart(); syncLater.restart(); _reseed(); }
    // instant: once this round of input changes (botId, shape, colour) is done, before the next frame
    Timer { id: jumpLater; interval: 0; onTriggered: orb.jump() }
    onShapeChanged: syncLater.restart()
    onColorChanged: syncLater.restart()
    onReactionChanged: reactLater.restart()

    // ---- state changes ------------------------------------------------------------------------
    function _react() {
        if (!_data) return;
        var to = _r(reaction);
        if (_spin) { _spin.reaction = to; return; }
        if (_blend) { _pending = to; return; }       // wait for the morph on screen to end
        _pending = "";
        if (to === _shown) return;
        var from = _shown, snap = _snapshot();
        _shown = to;
        if (from === "idle" && _clipOf(_data, to + ">in")) _src = { clip: to + ">in", t: 0 };
        else if (to === "idle" && _clipOf(_data, from + ">out")) _src = { clip: from + ">out", t: 0 };
        else _src = { clip: to, t: _bestStart(to, snap) / _fps(to) };
        _startBlend(snap, _frameNow(), 0.34);
    }

    property bool debug: false
    property real _clock: 0
    function _dbg(m) { if (debug) console.log("orbev", Math.round(_clock * 60), botId, m, _spin ? "spin.t=" + _spin.t.toFixed(3) : ""); }
    function _requestSpin() {
        _dbg("requestSpin shape=" + shape + " color=" + color);
        if (_spin) {
            if (_spin.t < 0.3) { _spin.shape = shape; _spin.b = store.get(shape); _spin.cb = _copy(color); _spin.reaction = _r(reaction); }
            else _nextSpin = true;
            return;
        }
        _beginSpin();
    }
    // a small orb changes bot in place: one blend into the new face and colour
    function _swapBot() {
        var snap = _snapshot();
        _data = store.get(shape); _shapeShown = shape;
        _shown = _r(reaction); _src = { clip: _shown, t: 0 };
        _colFade = { from: _copy(_col), t: 0 }; _base = color;
        _startBlend(snap, _frameNow(), 0.22);
    }
    // working: now and then a turn on the spot, like orb2 live
    function _selfSpin() {
        var snap = _snapshot();
        _spin = { a: _data, b: _data, ca: _copy(_base), cb: _copy(_base), shape: _shapeShown,
                  reaction: _shown, t: 0, d: 1, self: true };
        _pending = ""; _blend = null;
        _startBlend(snap, _frameNow(), 0.16);
    }
    function _beginSpin() {
        var snap = _snapshot();
        _spin = { a: _data, b: store.get(shape), ca: _copy(_col), cb: _copy(color), shape: shape,
                  reaction: _r(reaction), t: 0, d: dir < 0 ? -1 : 1 };
        _pending = ""; _blend = null;
        _startBlend(snap, _frameNow(), 0.16);       // from the face on screen into the spin's rest pose
    }

    // ---- the clock ----------------------------------------------------------------------------
    function step(dt) { _tick(dt); }
    FrameAnimation {
        running: !orb.manualClock && !(orb.clock && orb.clock.manual) && orb.visible && orb._data !== null
                 && (orb._loop || orb._spin !== null || orb._blend !== null || orb._colFade !== null
                     || (orb._src !== null && orb._src.clip.indexOf(">") > 0))
        onTriggered: orb._tick(Math.min(frameTime, 0.05) * orb.speed)
    }

    // the spin's moving part: orb2 stops the turn at speed and the recording holds still after it
    function _spinEnd(c) {
        if (c._end !== undefined) return c._end;
        var last = c.f[c.f.length - 1], end = c.f.length - 1;
        for (var i = c.f.length - 1; i > 0; i--) {
            var d = 0, fr = c.f[i];
            for (var k = 0; k < fr.b.length; k++) d += Math.abs(fr.b[k] - last.b[k]);
            if (d > 0.02 || fr.e.length !== last.e.length || (fr.e.length && fr.e[0][1] !== last.e[0][1])) { end = Math.min(c.f.length - 1, i + 1); break; }
        }
        c._end = end;
        return end;
    }
    // spin time: full speed at the start, easing to rest at the end (f(0)=0, f(1)=1, f'(1)=0)
    function _spinU(t) { return t + t * t - t * t * t; }
    function _fps(clip) { var c = _clipOf(_data, clip); return c ? c.fps : 30; }

    function _tick(dt) {
        if (!_data) return;
        _clock += dt; if (dt > 0) _dt = dt;
        if (_colFade) { _colFade.t += dt / 0.3; if (_colFade.t >= 1) _colFade = null; }
        if (_spin) {
            var sc = _clipOf(_spin.a, "spin");
            _spin.t += dt / (sc ? (_spinEnd(sc) + 1) / sc.fps * 1.12 : 0.8);   // the eased end takes a little longer
            if (_spin.t >= 1) { _endSpin(); return; }
        } else if (_src) {
            var c = _clipOf(_data, _src.clip);
            if (c && _idleHold > 0 && _src.clip === "idle") _idleHold -= dt;     // big idle: blinks spaced out
            else if (c) {
                _src.t += dt;
                var len = c.f.length / c.fps * (c.loop ? 1 : 1.12);   // one-shot morphs get the eased end
                if (_src.t >= len) {
                    if (c.loop) { _src.t -= len * Math.floor(_src.t / len); _dbg("wrap " + _src.clip);
                                  if (_src.clip === "idle" && !small && !still) _idleHold = 1.6 + 2.6 * _rand(); }   // frames lerp across the seam
                    else _afterClip();
                }
            }
        }
        _lifeTick(dt);
        if (_blend) {
            _blend.t += dt;
            if (_blend.t >= _blend.T) {
                _blend = null;
                if (_pending !== "" && !_spin) reactLater.restart();
            }
        }
        _render();
    }

    // an in/out morph ended: carry on in the loop it leads to, at its best-matching frame
    function _afterClip() {
        var c = _clipOf(_data, _src.clip), last = c.f[c.f.length - 1];
        var to = _src.clip.indexOf(">out") > 0 ? "idle" : _src.clip.split(">")[0];
        var snap = _snapshot();
        _src = { clip: to, t: _bestStart(to, _unpack(last)) / _fps(to) };
        var tgt = _frameNow();
        _startBlend(snap, tgt, 0.16 + Math.min(0.24, _dist(snap, tgt) * 0.04));
    }

    function _endSpin() {
        _dbg("endSpin to " + _spin.shape + " next=" + !!_nextSpin);
        var s = _spin, snap = _snapshot();
        _spin = null;
        _data = s.b; _shapeShown = s.shape; _col = s.cb; _base = s.cb;
        if (_nextSpin) { _nextSpin = null; _beginSpin(); _render(); return; }
        _shown = s.reaction;
        if (s.reaction !== "idle" && _clipOf(_data, s.reaction + ">in")) _src = { clip: s.reaction + ">in", t: 0 };
        else _src = { clip: s.reaction, t: _bestStart(s.reaction, snap) / _fps(s.reaction) };
        _startBlend(snap, _frameNow(), 0.12);
        if (!s.self) cycled();
        if (_r(reaction) !== _shown) _pending = _r(reaction);
        _render();
    }

    // ---- frames -------------------------------------------------------------------------------
    // a frame's eyes as numbers: [{a, subs: [[x, y, x, y, ...], ...]}], kept on the frame
    function _eyeNums(f) {
        if (f._en) return f._en;
        var groups = [];
        for (var g = 0; g < f.e.length; g++) {
            var subs = f.e[g][1].split("Z").filter(function (s) { return s.length > 0; }).map(function (s) {
                return s.replace(/[ML]/g, " ").trim().split(/\s+/).map(Number);
            });
            groups.push({ a: f.e[g][0], subs: subs });
        }
        f._en = groups;
        return groups;
    }
    function _eyeD(subs) {
        var d = "";
        for (var i = 0; i < subs.length; i++) {
            var s = subs[i];
            for (var k = 0; k < s.length; k += 2) d += (k ? "L" : "M") + s[k].toFixed(3) + " " + s[k + 1].toFixed(3);
            d += "Z";
        }
        return d;
    }
    function _sameShape(ga, gb) {
        if (!ga || !gb || ga.length !== gb.length) return false;
        for (var g = 0; g < ga.length; g++) {
            if (ga[g].subs.length !== gb[g].subs.length) return false;
            for (var i = 0; i < ga[g].subs.length; i++) if (ga[g].subs[i].length !== gb[g].subs[i].length) return false;
        }
        return true;
    }
    function _ec(groups) {
        var x = 0, y = 0, n = 0;
        for (var g = 0; g < groups.length; g++) for (var i = 0; i < groups[g].subs.length; i++) {
            var s = groups[g].subs[i];
            for (var k = 0; k < s.length; k += 2) { x += s[k]; y += s[k + 1]; n++; }
        }
        return n ? [x / n, y / n] : [0, -0.1];
    }
    function _unpack(f) { var en = _eyeNums(f); return { b: f.b, g: en, ec: _ec(en) }; }

    // two recorded frames mixed: body always, eyes when alike (else the nearer one)
    function _mixFrames(fa, fb, w) {
        var b = new Array(fa.b.length);
        for (var k = 0; k < fa.b.length; k++) b[k] = fa.b[k] + (fb.b[k] - fa.b[k]) * w;
        var ga = _eyeNums(fa), gb = _eyeNums(fb), g;
        if (_sameShape(ga, gb)) {
            g = ga.map(function (grp, gi) {
                return { a: grp.a + (gb[gi].a - grp.a) * w, subs: grp.subs.map(function (s, si) {
                    var t = gb[gi].subs[si], o = new Array(s.length);
                    for (var j = 0; j < s.length; j++) o[j] = s[j] + (t[j] - s[j]) * w;
                    return o; }) };
            });
        } else g = w < 0.5 ? ga : gb;
        return { b: b, g: g, ec: _ec(g) };
    }
    // the stream's frame now (before any blend)
    function _frameNow() {
        if (_spin) {
            var sa = _clipOf(_spin.a, "spin"), sb = _clipOf(_spin.b, "spin");
            var n = _spinEnd(sa) + 1, u = _spinU(_spin.t);
            var x = Math.min(n - 1.0001, Math.max(0, u * (n - 1)));
            if (_spin.d < 0) x = (n - 1) - x;                         // backwards: the same turn, reversed
            var i = Math.floor(x), w = x - i;
            var fa = _streamAt(sa, x, n, false);
            var fb = _streamAt(sb, Math.min(x, sb.f.length - 1.0001), sb.f.length, false);
            var m = _smooth(0.3, 0.7, u);                             // the morph happens round the back
            var b = new Array(fa.b.length);
            for (var k = 0; k < fa.b.length; k++) b[k] = fa.b[k] + (fb.b[k] - fa.b[k]) * m;
            var al = _smooth(0.42, 0.58, u);                          // the two bots' eyes cross-fade
            if (al <= 0) return { b: b, g: fa.g, ec: fa.ec };
            if (al >= 1) return { b: b, g: fb.g, ec: fb.ec };
            return _eyeUnion(b, fa.g, fb.g, al);
        }
        var c = _clipOf(_data, _src ? _src.clip : "idle") || _clipOf(_data, "idle");
        var len = c.f.length, p = (_src ? _src.t : 0) * c.fps;
        if (!c.loop) p = _spinU(Math.min(1, (_src ? _src.t : 0) / (len / c.fps * 1.12))) * (len - 1);   // settle, don't stop dead
        return _streamAt(c, p, len, !!c.loop);
    }
    // a clip at fractional frame p. Eyes whose drawing changes structure between two recorded
    // frames (orb2 swaps eye styles, the rim clips them) can't be lerped: cross-fade old and new
    // over _eyeX frames round the change instead of switching in one frame.
    readonly property real _eyeX: 1.5
    function _streamAt(c, p, n, loop) {
        var j = Math.floor(p), wt = p - j, a = Math.min(j, n - 1);
        var nxt = loop ? (a + 1) % n : Math.min(a + 1, n - 1);
        var fr = _mixFrames(c.f[a], c.f[nxt], wt);
        for (var q = Math.floor(p - _eyeX); q <= Math.ceil(p + _eyeX); q++) {
            var q0 = loop ? ((q % n) + n) % n : q, q1 = loop ? (q0 + 1) % n : q + 1;
            if (q0 < 0 || q1 >= n) continue;
            var g0 = _eyeNums(c.f[q0]), g1 = _eyeNums(c.f[q1]);
            if (_sameShape(g0, g1)) continue;
            var al = _smooth5((p - (q + 0.5 - _eyeX)) / (2 * _eyeX));
            if (al <= 0 || al >= 1) continue;
            return _eyeUnion(fr.b, _sameShape(fr.g, g0) ? fr.g : g0, _sameShape(fr.g, g1) ? fr.g : g1, al);
        }
        return fr;
    }
    function _eyeUnion(b, go, gn, al) {
        var g = go.map(function (x) { return { a: x.a * (1 - al), subs: x.subs }; })
                  .concat(gn.map(function (x) { return { a: x.a * al, subs: x.subs }; })).slice(0, 6);
        var eo = _ec(go), en = _ec(gn);
        return { b: b, g: g, ec: go.length && gn.length ? [eo[0] + (en[0] - eo[0]) * al, eo[1] + (en[1] - eo[1]) * al] : (go.length ? eo : en) };
    }
    // the loop frame that best continues `f`: same eye structure, nearest body and gaze
    function _bestStart(clip, f) {
        var c = _clipOf(_data, clip);
        if (!c || !f) return 0;
        var best = 1e9, bi = 0;
        for (var i = 0; i < c.f.length; i++) {
            var fr = c.f[i], d = 0;
            for (var k = 0; k < fr.b.length; k += 4) d += Math.abs(fr.b[k] - f.b[k]) + Math.abs(fr.b[k + 1] - f.b[k + 1]);
            var en = _eyeNums(fr), e = _ec(en);
            d += 6 * (Math.abs(e[0] - f.ec[0]) + Math.abs(e[1] - f.ec[1])) + (_sameShape(en, f.g) ? 0 : 2);
            if (d < best) { best = d; bi = i; }
        }
        return bi;
    }
    // the frame on screen, with its velocity: a blend's source keeps moving and eases to a stop
    // (tau 70 ms) instead of freezing, so a change never kinks the motion
    function _snapshot() {
        if (!_last) return null;
        var v = _vel && _vel.b.length === _last.b.length ? _vel : { b: new Array(_last.b.length).fill(0), ec: [0, 0] };
        return { b: _last.b.slice(), g: _last.g, ec: _last.ec.slice(), v: v.b.slice(), vec: v.ec.slice() };
    }
    readonly property real _tau: 0.07
    function _carry(t) { return _tau * (1 - Math.exp(-t / _tau)); }
    function _dist(a, b) {
        var d = 0; for (var k = 0; k < a.b.length; k++) d += Math.abs(a.b[k] - b.b[k]);
        return d + 6 * (Math.abs(a.ec[0] - b.ec[0]) + Math.abs(a.ec[1] - b.ec[1]));
    }
    function _startBlend(snap, target, T) {
        if (!snap) return;
        _dbg("blend T=" + T + " into " + (_spin ? "spin" : _src.clip));
        var alike = _sameShape(snap.g, target.g)
                    && Math.abs(snap.ec[0] - target.ec[0]) + Math.abs(snap.ec[1] - target.ec[1]) < 0.25;
        _blend = { snap: snap, t: 0, T: T, mode: alike ? "fade" : "blink" };
        if (alike) _blend.T = Math.min(T, 0.2);
    }

    // orb2's curves
    function _smooth5(x) { var t = Math.max(0, Math.min(1, x)); return t * t * t * (t * (t * 6 - 15) + 10); }
    function _easeMorph(x) { var t = Math.max(0, Math.min(1, x)); return 0.45 * _smooth5(t) + 0.55 * (1 - Math.pow(1 - t, 3.4)); }
    function _smooth(e0, e1, x) { var t = Math.max(0, Math.min(1, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t); }
    // a colour read from a property is a live reference in Qt 6: keep copies, not references
    function _copy(c) { return Qt.rgba(c.r, c.g, c.b, c.a); }
    function _mix(a, b, w) { return Qt.rgba(a.r + (b.r - a.r) * w, a.g + (b.g - a.g) * w, a.b + (b.b - a.b) * w, a.a + (b.a - a.a) * w); }

    // ---- compose what is drawn ---------------------------------------------------------------
    function _render() {
        var cur = _frameNow();
        var shown = { b: cur.b, g: cur.g, ec: cur.ec };
        var layA = { g: [], a: 0, sy: 1, dx: 0, dy: 0, ec: cur.ec }, layB = { g: cur.g, a: 1, sy: 1, dx: 0, dy: 0, ec: cur.ec };
        if (_blend) {
            var s = _blend.snap, e = _smooth5(_blend.t / _blend.T), cw = _carry(_blend.t);
            var b = new Array(cur.b.length);
            for (var k = 0; k < cur.b.length; k++) { var sk = s.b[k] + s.v[k] * cw; b[k] = sk + (cur.b[k] - sk) * e; }
            shown.b = b;
            var sx = s.ec[0] + s.vec[0] * cw, sy = s.ec[1] + s.vec[1] * cw;
            var px = sx + (cur.ec[0] - sx) * e, py = sy + (cur.ec[1] - sy) * e;
            layA = { g: s.g, ec: s.ec, dx: px - s.ec[0], dy: py - s.ec[1], sy: 1, a: 0 };
            layB = { g: cur.g, ec: cur.ec, dx: px - cur.ec[0], dy: py - cur.ec[1], sy: 1, a: 0 };
            if (_blend.mode === "fade") { layA.a = 1 - e; layB.a = e; }
            else {
                // a heavy blink: the old eyes close to a capsule, the new ones open from it
                var u = _blend.t / _blend.T;
                layA.sy = 1 - 0.86 * _smooth5(u / 0.5);
                layB.sy = 0.14 + 0.86 * _smooth5((u - 0.5) / 0.5);
                layA.a = 1 - _smooth(0.44, 0.56, u);
                layB.a = _smooth(0.44, 0.56, u);
            }
            shown.g = e < 0.5 ? s.g : cur.g;
            shown.ec = [px, py];
        }
        if (_last && _last.b.length === shown.b.length && _dt > 0) {
            var vb = new Array(shown.b.length);
            for (var q = 0; q < shown.b.length; q++) vb[q] = (shown.b[q] - _last.b[q]) / _dt;
            _vel = { b: vb, ec: [(shown.ec[0] - _last.ec[0]) / _dt, (shown.ec[1] - _last.ec[1]) / _dt] };
        }
        if (_life.gx !== 0 || _life.gy !== 0) {
            layA = Object.assign({}, layA, { dx: layA.dx + _life.gx, dy: layA.dy + _life.gy });
            layB = Object.assign({}, layB, { dx: layB.dx + _life.gx, dy: layB.dy + _life.gy });
        }
        _last = shown;
        var pts = new Array(shown.b.length / 2);
        for (var j = 0; j < shown.b.length; j += 2) pts[j / 2] = Qt.point(shown.b[j], shown.b[j + 1]);
        _body = pts;
        _layA = layA; _layB = layB;
        _eA = layA.a > 0.003 ? layA.g.map(function (x) { return [x.a, orb._eyeD(x.subs)]; }) : [];
        _eB = layB.a > 0.003 ? layB.g.map(function (x) { return [x.a, orb._eyeD(x.subs)]; }) : [];
        _col = _spin ? _mix(_spin.ca, _spin.cb, _smooth(0.3, 0.7, _spinU(_spin.t)))
             : _colFade ? _mix(_colFade.from, _base, _smooth5(_colFade.t)) : _base;
    }
    // ---- life ----------------------------------------------------------------------------------
    property real _idleHold: 0
    property real _lifeT: 0
    property real _amp: 0
    property real _nextSelfSpin: 6
    property var _life: ({ tilt: 0, breath: 1, bob: 0, gx: 0, gy: 0 })
    property var _g: ({ x: 0, y: 0, vx: 0, vy: 0, tx: 0, ty: 0, next: 1 })
    property var _bias: null                       // adopted life: {tilt, breath, bob, t}
    property int _seed: 0
    function _reseed() { var h = 2166136261; for (var i = 0; i < botId.length; i++) { h ^= botId.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; } _seed = h; }
    function _rand() {                             // mulberry32: the same life for the same bot, every run
        _seed = (_seed + 0x6D2B79F5) >>> 0; var t = _seed;
        t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    }
    readonly property var _moodAmp: ({ idle: 1, sleeping: 0.35, working: 2.2, compute: 2.2, thinking: 1.4, speaking: 1.2,
                                       listening: 0.7, needs: 1.3, done: 1.1, error: 0.6 })
    function _lifeTick(dt) {
        if (small && _amp === 0 && !_bias) return;
        _lifeT += dt;
        var target = (small || still) ? 0 : (_moodAmp[_shown] || 1) * lifeScale;
        _amp += (target - _amp) * Math.min(1, dt * 2.2);
        if (Math.abs(_amp) < 0.0005 && target === 0) _amp = 0;
        var a = _amp, t = _lifeT, w = Math.max(0, Math.min(1.2, a - 1));        // w: the working part
        var tilt = a * (1.5 * Math.sin(6.2832 * t / 7.3 + 1.1) + 0.8 * Math.sin(6.2832 * t / 3.1 + 2.3));
        var breath = 1 + 0.011 * Math.min(a, 1.3) * Math.sin(6.2832 * t / 4.4);
        var bob = -0.028 * w * Math.sin(6.2832 * t * 0.85);
        // look-arounds: a new spot every few seconds, reached on a critically damped spring
        var g = _g;
        if (t >= g.next) {
            var r = (0.035 + 0.03 * w) * Math.min(a, 1.6), ang = 6.2832 * _rand();
            g.tx = r * Math.cos(ang) * _rand(); g.ty = r * Math.sin(ang) * _rand() - (_shown === "thinking" ? 0.03 * a : 0);
            if (_rand() < 0.3) { g.tx = 0; g.ty = 0; }                          // back to you
            g.next = t + (w > 0 ? 1.2 + 1.6 * _rand() : 2.8 + 4 * _rand());
        }
        var om = w > 0 ? 11 : 7, n = Math.max(1, Math.ceil(dt / 0.004)), h = dt / n;
        for (var i = 0; i < n; i++) {
            g.vx += (om * om * (g.tx - g.x) - 2 * om * g.vx) * h; g.x += g.vx * h;
            g.vy += (om * om * (g.ty - g.y) - 2 * om * g.vy) * h; g.y += g.vy * h;
        }
        if (_bias) {                                                            // an adopted pose eases into this one
            _bias.t += dt; var k = 1 - _smooth5(_bias.t / 0.6);
            tilt += _bias.tilt * k; breath += _bias.breath * k; bob += _bias.bob * k;
            if (_bias.t >= 0.6) _bias = null;
        }
        _life = { tilt: tilt, breath: breath, bob: bob, gx: g.x, gy: g.y };
        if (!small && !still && w > 0.5 && !_spin && !_blend && t > _nextSelfSpin) {
            _nextSelfSpin = t + 9 + 6 * _rand();
            _selfSpin();
        } else if (w <= 0.5 && _nextSelfSpin < t + 3) _nextSelfSpin = t + 4 + 4 * _rand();
    }
    // hand-offs between two orbs of the same bot (the flying hero of the Bots tab)
    function frameSnapshot() { return _snapshot(); }
    function adoptFrame(snap) { if (snap && _data && _last) _startBlend(snap, _frameNow(), 0.22); }
    function lifeSnapshot() { return { amp: _amp, tilt: _life.tilt, breath: _life.breath, bob: _life.bob, g: Object.assign({}, _g) }; }
    function adoptLife(l) {
        if (!l) return;
        _tick(0);
        _amp = l.amp;
        _bias = { tilt: l.tilt - _life.tilt, breath: l.breath - _life.breath, bob: l.bob - _life.bob, t: 0 };
        _g = Object.assign({}, _g, { x: l.g.x, y: l.g.y, vx: l.g.vx, vy: l.g.vy });
    }
    function resetLife() { _amp = 0; _bias = null; _g = Object.assign({}, _g, { x: 0, y: 0, vx: 0, vy: 0, tx: 0, ty: 0 }); }

    property var _body: []
    property var _layA: ({ a: 0, sy: 1, dx: 0, dy: 0, ec: [0, 0] })
    property var _layB: ({ a: 1, sy: 1, dx: 0, dy: 0, ec: [0, 0] })
    property var _eA: []
    property var _eB: []

    // ---- drawing: orb units around the centre (size = the body, about 2 units, plus a little room)
    Item {
        x: orb.width / 2; y: orb.height / 2
        transform: Scale { xScale: orb.size / 2.2; yScale: orb.size / 2.2 }
        Item {
            transform: [
                Rotation { angle: orb._life.tilt },
                Scale { xScale: orb._life.breath; yScale: orb._life.breath },
                Translate { y: orb._life.bob }
            ]
            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath { fillColor: orb._col; strokeWidth: -1; strokeColor: "transparent"; PathPolyline { path: orb._body } }
            }
            BotOrbEyes { eyes: orb._eA; lay: orb._layA; ink: orb.eyeColor }
            BotOrbEyes { eyes: orb._eB; lay: orb._layB; ink: orb.eyeColor }
        }
    }
}
