import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// written by portal-patch.py (panacea-config) - the island's activity glow.
//
// A thin light along the island's exact outline while something works: white for
// the system (VPN connecting), Claude's orange while it thinks, an agent's own
// colours for anything that asks (`panacea-glow`, or `qs ipc call pill glow <id>
// <colours>`). The line sits on the edge itself, half inside and half out, and
// follows every curve, the two flares included. On an island attached to the top
// edge it fades out towards both ends, where the island meets the screen (a
// vertical gradient on every stroke); a detached island gets a closed loop.
//
//   standard   one stroke end to end, eased (detached: an even, endless orbit)
//   pingpong   there and back again
//   symmetric  fades in at the bottom centre and sends a stroke up each side
//   converge   a stroke from each end, meeting at the bottom centre
//   breathing  the whole outline brightens and dims
//   wave       a long soft band flowing along a faintly lit edge
Item {
    id: glow
    property bool active: false
    property var colors: ["#ffffff"]          // head first; 1 to 3 of them
    property string style: "standard"
    property int lap: 1800                    // ms per run
    property real intensity: 0.7              // 0..1
    property bool still: false                // reduce motion: a steady lit edge
    property bool paused: false               // tests: hold t where it is
    // the island, in the parent's coordinates
    property real cx: 0
    property real cy: 0
    property real cw: 0
    property real ch: 0
    property real rTL: 0
    property real rTR: 0
    property real rBL: 0
    property real rBR: 0
    property bool attached: true              // grows from the top edge, with flares
    property real flare: 0

    readonly property real pad: 24
    x: cx - pad; y: cy - pad
    width: cw + 2 * pad; height: ch + 2 * pad

    // the colours ease into new ones while lit (a page that turns out to be another site,
    // Claude taking over from an agent...); while hidden they just jump
    readonly property color t0: colors.length ? colors[0] : "white"
    readonly property color t1: colors.length > 1 ? colors[1] : t0
    readonly property color t2: colors.length > 2 ? colors[2] : t1
    property color c0: t0
    property color c1: t1
    property color c2: t2
    Behavior on c0 { enabled: glow.visible; ColorAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    Behavior on c1 { enabled: glow.visible; ColorAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    Behavior on c2 { enabled: glow.visible; ColorAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    function a(c, alpha) { return Qt.rgba(c.r, c.g, c.b, Math.max(0, Math.min(1, alpha))); }

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    // in briskly, out slowly (it settles rather than blinks off)
    Behavior on opacity { NumberAnimation { duration: glow.active ? 320 : 700; easing.type: glow.active ? Easing.OutCubic : Easing.InOutSine } }

    // ---- the outline (item coordinates)
    readonly property real ex0: pad
    readonly property real ey0: pad
    readonly property real ex1: pad + cw
    readonly property real ey1: pad + ch
    function rr(r) { return Math.max(0, Math.min(r, ch / 2, cw / 2)); }
    readonly property real tl: rr(rTL)
    readonly property real tr: rr(rTR)
    readonly property real bl: rr(rBL)
    readonly property real br: rr(rBR)
    readonly property real f: attached ? Math.max(0, flare) : 0
    readonly property bool closed: !attached
    readonly property real q: Math.PI / 2
    readonly property real len: closed
        ? 2 * cw + 2 * ch - (2 - q) * (tl + tr + bl + br)
        : 2 * q * f + 2 * (ch - f) + cw - (2 - q) * (bl + br)
    readonly property string d: closed
        ? "M " + (ex0 + tl) + " " + ey0 + " L " + (ex1 - tr) + " " + ey0
          + " A " + tr + " " + tr + " 0 0 1 " + ex1 + " " + (ey0 + tr)
          + " L " + ex1 + " " + (ey1 - br) + " A " + br + " " + br + " 0 0 1 " + (ex1 - br) + " " + ey1
          + " L " + (ex0 + bl) + " " + ey1 + " A " + bl + " " + bl + " 0 0 1 " + ex0 + " " + (ey1 - bl)
          + " L " + ex0 + " " + (ey0 + tl) + " A " + tl + " " + tl + " 0 0 1 " + (ex0 + tl) + " " + ey0 + " Z"
        : "M " + (ex0 - f) + " " + ey0
          + " A " + f + " " + f + " 0 0 1 " + ex0 + " " + (ey0 + f)
          + " L " + ex0 + " " + (ey1 - bl) + " A " + bl + " " + bl + " 0 0 0 " + (ex0 + bl) + " " + ey1
          + " L " + (ex1 - br) + " " + ey1 + " A " + br + " " + br + " 0 0 0 " + ex1 + " " + (ey1 - br)
          + " L " + ex1 + " " + (ey0 + f) + " A " + f + " " + f + " 0 0 1 " + (ex1 + f) + " " + ey0
    // landmarks along the path: the bottom centre, and (closed) the top centre
    readonly property real topLen: Math.max(0, cw - tl - tr)
    readonly property real bottomMid: closed
        ? topLen + q * tr + Math.max(0, ch - tr - br) + q * br + Math.max(0, cw - br - bl) / 2
        : len / 2
    readonly property real topMid: closed ? topLen / 2 : 0

    // the fade towards the screen edge: transparent at the top, full by `fadeTo`
    readonly property real fadeTo: ey0 + Math.max(12, Math.min(ch * 0.6, 80))

    // ---- the clock: t runs 0..1 once per cycle; each style maps it to its strokes
    readonly property string kind: ["standard", "pingpong", "symmetric", "converge", "breathing", "wave"]
                                   .indexOf(style) >= 0 ? style : "standard"
    readonly property real cycle: {
        var l = Math.max(400, lap);
        if (kind === "pingpong") return 2 * l;
        if (kind === "breathing") return 1.8 * l;
        if (kind === "wave") return 1.5 * l;
        if (closed && kind === "standard") return 1.2 * l;          // an orbit: no breather
        return 1.15 * l;                                            // a run, then a short breath
    }
    property real t: 0
    NumberAnimation on t {
        running: glow.visible && !glow.still && !glow.paused
        from: 0; to: 1; duration: glow.cycle; loops: Animation.Infinite
    }
    function ease(u) { return (1 - Math.cos(Math.PI * Math.max(0, Math.min(1, u)))) / 2; }
    function smooth(x) { x = Math.max(0, Math.min(1, x)); return x * x * (3 - 2 * x); }
    readonly property real seg: Math.max(60, Math.min(360, len * 0.24))
    readonly property real u: kind === "pingpong" ? (t < 0.5 ? 2 * t : 2 * t - 1)
                              : (closed && kind === "standard") || kind === "breathing" || kind === "wave" ? t
                              : Math.min(1, t * 1.15)
    readonly property real speed: Math.sin(Math.PI * u)                            // 0 at the ends, 1 mid-run
    readonly property real springLen: seg * (0.4 + 0.6 * speed)                    // long when fast
    readonly property real leanRun: 0.35 + 0.65 * speed                            // glow at the front when fast

    // the strokes of the current style: head position, direction, length, how lit,
    // lean (where the bright part sits: 1 at the head, 0 in the middle, so it glides
    // across instead of jumping when a stroke turns round), and (for strokes born at
    // a point) where they start, so they grow out of it
    readonly property var comets: {
        var p = ease(u), L = springLen, n = len;
        if (still || kind === "breathing") return [];
        if (kind === "standard") {
            if (closed) return [{ h: t * n, d: 1, l: seg, a: 1, lean: 1 }];
            return [{ h: p * (n + L), d: 1, l: L, a: 1, lean: leanRun }];
        }
        if (kind === "pingpong") {
            var fwd = t < 0.5;
            // the lean follows the speed all the way to 0 at each turn: the stroke gathers,
            // its glow drifts to the middle, then out to the new front
            if (closed) return [{ h: fwd ? p * n : (1 - p) * n, d: fwd ? 1 : -1, l: L, a: 1, lean: speed }];
            return fwd ? [{ h: L + p * (n - L), d: 1, l: L, a: 1, lean: speed }]
                       : [{ h: n - L - p * (n - L), d: -1, l: L, a: 1, lean: speed }];
        }
        if (kind === "symmetric") {
            var o = bottomMid, reach = closed ? n / 2 : n / 2 + L;
            var al = smooth(u / 0.18) * (closed ? smooth((1 - u) / 0.22) : 1);
            return [{ h: o + p * reach, d: 1, l: L, a: al, o: o, lean: leanRun }, { h: o - p * reach, d: -1, l: L, a: al, o: o, lean: leanRun }];
        }
        if (kind === "converge") {
            var s0 = closed ? topMid : 0, s1 = closed ? topMid + n : n, half = closed ? n / 2 : n / 2;
            var ac = smooth(u / 0.15) * smooth((1 - u) / 0.28);
            return [{ h: s0 + p * half, d: 1, l: L, a: ac, lean: leanRun }, { h: s1 - p * half, d: -1, l: L, a: ac, lean: leanRun }];
        }
        // wave: a long soft band, even pace
        var W = Math.max(120, n * 0.45);
        return [{ h: closed ? t * n : t * (n + W), d: 1, l: W, a: 0.75, soft: true, lean: 0.45 }];
    }
    // the lit edge: breathing lights all of it, wave keeps it faintly lit; the stroke
    // styles have none, so the island stays pure black outside the moving stroke
    readonly property real baseAlpha: still ? 0.55
        : kind === "breathing" ? 0.1 + 0.8 * (0.5 - 0.5 * Math.cos(2 * Math.PI * t))
        : kind === "wave" ? 0.2 : 0

    // a lit stretch [lo, hi] along the path: the whole stroke (frac 1), or a shorter
    // brighter part of it placed by the lean; as a dash pattern for a stroke of width w
    function span(c, frac) {
        var lo, hi;
        if (c.d > 0) { hi = c.h; lo = hi - c.l; if (c.o !== undefined && lo < c.o) lo = c.o; }
        else { lo = c.h; hi = lo + c.l; if (c.o !== undefined && hi > c.o) hi = c.o; }
        hi = Math.max(lo, hi);
        if (frac < 1) {
            var whole = hi - lo, part = whole * frac;
            var mid = (lo + hi) / 2 + c.d * (c.lean === undefined ? 1 : c.lean) * (whole - part) / 2;
            lo = mid - part / 2; hi = mid + part / 2;
        }
        if (!closed) { lo = Math.max(0, lo); hi = Math.min(len, hi); }      // an open path has ends: clip to them
        return [lo, Math.max(lo, hi)];
    }
    function mix(x, y, k) { return Qt.rgba(x.r + (y.r - x.r) * k, x.g + (y.g - x.g) * k, x.b + (y.b - x.b) * k, 1); }
    function shown(c) { var s = span(c, 1); return s[1] - s[0] > 0.5; }
    // one dash per period: the period is the loop's length (closed, so a stroke wraps
    // around) or far longer than the path (open, so it never repeats back at the start).
    // The offset is kept positive: the pattern shifted so its dash begins at lo.
    function period(c, frac) { var s = span(c, frac); return closed ? len : 3 * len + (s[1] - s[0]); }
    function dash(c, frac, w) {
        var s = span(c, frac), l = Math.max(0.01, s[1] - s[0]);
        return [l / w, Math.max(0.01, (period(c, frac) - l) / w)];
    }
    function off(c, frac, w) {
        var lo = span(c, frac)[0], per = period(c, frac);
        lo = ((lo % per) + per) % per;
        return (per - lo) / w;
    }

    // ---- drawing. Every stroke uses the same vertical gradient: transparent at the
    // screen edge, full colour from `fadeTo` down (a detached island: full everywhere).

    // the lit edge (breathing, wave, reduce motion): a soft halo, then a crisp line
    Item {
        anchors.fill: parent
        visible: glow.baseAlpha > 0.001 && (glow.kind === "breathing" || glow.still)
        layer.enabled: visible && glow.visible
        layer.effect: MultiEffect { blurEnabled: true; blur: 0.5; blurMax: 12 }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"; strokeWidth: 4
                strokeColor: "transparent"
                strokeGradient: LinearGradient {
                    x1: 0; y1: glow.closed ? -2 : glow.ey0; x2: 0; y2: glow.closed ? -1 : glow.fadeTo
                    GradientStop { position: 0; color: glow.a(glow.c1, glow.closed ? (glow.baseAlpha * 0.6 * glow.intensity) : 0) }
                    GradientStop { position: 1; color: glow.a(glow.c1, glow.baseAlpha * 0.6 * glow.intensity) }
                }
                PathSvg { path: glow.d }
            }
        }
    }
    Shape {
        anchors.fill: parent
        visible: glow.baseAlpha > 0.001
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeWidth: glow.kind === "breathing" || glow.still ? 1.4 : 1
            strokeColor: "transparent"
            strokeGradient: LinearGradient {
                    x1: 0; y1: glow.closed ? -2 : glow.ey0; x2: 0; y2: glow.closed ? -1 : glow.fadeTo
                    GradientStop { position: 0; color: glow.a(glow.kind === "breathing" ? Qt.lighter(glow.c0, 1.1) : glow.c1, glow.closed ? (glow.baseAlpha * (0.45 + 0.55 * glow.intensity)) : 0) }
                    GradientStop { position: 1; color: glow.a(glow.kind === "breathing" ? Qt.lighter(glow.c0, 1.1) : glow.c1, glow.baseAlpha * (0.45 + 0.55 * glow.intensity)) }
                }
            PathSvg { path: glow.d }
        }
    }

    Repeater {
        model: glow.comets.length
        delegate: Item {
            id: comet
            required property int index
            readonly property var c: glow.comets[index] || ({ h: 0, d: 1, l: 1, a: 0, lean: 1 })
            readonly property real fadeTop: glow.closed ? -2 : glow.ey0          // the fade towards the screen edge
            readonly property real fadeBottom: glow.closed ? -1 : glow.fadeTo
            readonly property real k0: glow.closed ? 1 : 0
            anchors.fill: parent
            opacity: glow.shown(c) ? c.a : 0
            // the glow around the bright part: a wide faint bloom and a tighter halo, blurred
            Item {
                anchors.fill: parent
                layer.enabled: glow.visible
                layer.effect: MultiEffect { blurEnabled: true; blur: 0.6; blurMax: 16 }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"; strokeWidth: 7; capStyle: ShapePath.RoundCap
                        strokeColor: "transparent"
                        strokeGradient: LinearGradient {
                            x1: 0; y1: comet.fadeTop; x2: 0; y2: comet.fadeBottom
                            GradientStop { position: 0; color: glow.a(glow.c2, comet.k0 * 0.28 * glow.intensity) }
                            GradientStop { position: 1; color: glow.a(glow.c2, 0.28 * glow.intensity) }
                        }
                        strokeStyle: ShapePath.DashLine
                        dashPattern: glow.dash(comet.c, 0.85, 7); dashOffset: glow.off(comet.c, 0.85, 7)
                        PathSvg { path: glow.d }
                    }
                    ShapePath {
                        fillColor: "transparent"; strokeWidth: 3.5; capStyle: ShapePath.RoundCap
                        strokeColor: "transparent"
                        strokeGradient: LinearGradient {
                            x1: 0; y1: comet.fadeTop; x2: 0; y2: comet.fadeBottom
                            GradientStop { position: 0; color: glow.a(glow.c1, comet.k0 * (comet.c.soft ? 0.45 : 0.8) * glow.intensity) }
                            GradientStop { position: 1; color: glow.a(glow.c1, (comet.c.soft ? 0.45 : 0.8) * glow.intensity) }
                        }
                        strokeStyle: ShapePath.DashLine
                        dashPattern: glow.dash(comet.c, 0.4, 3.5); dashOffset: glow.off(comet.c, 0.4, 3.5)
                        PathSvg { path: glow.d }
                    }
                }
            }
            // the line: five graded layers, from a dim tail in the last colour to a bright core
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"; strokeWidth: 1; capStyle: ShapePath.RoundCap
                    strokeColor: "transparent"
                    strokeGradient: LinearGradient {
                        x1: 0; y1: comet.fadeTop; x2: 0; y2: comet.fadeBottom
                        GradientStop { position: 0; color: glow.a(glow.c2, comet.k0 * (0.2 + 0.25 * glow.intensity)) }
                        GradientStop { position: 1; color: glow.a(glow.c2, 0.2 + 0.25 * glow.intensity) }
                    }
                    strokeStyle: ShapePath.DashLine
                    dashPattern: glow.dash(comet.c, 1, 1); dashOffset: glow.off(comet.c, 1, 1)
                    PathSvg { path: glow.d }
                }
                ShapePath {
                    fillColor: "transparent"; strokeWidth: 1.1; capStyle: ShapePath.RoundCap
                    strokeColor: "transparent"
                    strokeGradient: LinearGradient {
                        x1: 0; y1: comet.fadeTop; x2: 0; y2: comet.fadeBottom
                        GradientStop { position: 0; color: glow.a(glow.mix(glow.c2, glow.c1, 0.5), comet.k0 * (0.32 + 0.3 * glow.intensity)) }
                        GradientStop { position: 1; color: glow.a(glow.mix(glow.c2, glow.c1, 0.5), 0.32 + 0.3 * glow.intensity) }
                    }
                    strokeStyle: ShapePath.DashLine
                    dashPattern: glow.dash(comet.c, 0.72, 1.1); dashOffset: glow.off(comet.c, 0.72, 1.1)
                    PathSvg { path: glow.d }
                }
                ShapePath {
                    fillColor: "transparent"; strokeWidth: 1.2; capStyle: ShapePath.RoundCap
                    strokeColor: "transparent"
                    strokeGradient: LinearGradient {
                        x1: 0; y1: comet.fadeTop; x2: 0; y2: comet.fadeBottom
                        GradientStop { position: 0; color: glow.a(glow.c1, comet.k0 * (0.48 + 0.4 * glow.intensity)) }
                        GradientStop { position: 1; color: glow.a(glow.c1, 0.48 + 0.4 * glow.intensity) }
                    }
                    strokeStyle: ShapePath.DashLine
                    dashPattern: glow.dash(comet.c, 0.48, 1.2); dashOffset: glow.off(comet.c, 0.48, 1.2)
                    PathSvg { path: glow.d }
                }
                ShapePath {
                    fillColor: "transparent"; strokeWidth: 1.35; capStyle: ShapePath.RoundCap
                    strokeColor: "transparent"
                    strokeGradient: LinearGradient {
                        x1: 0; y1: comet.fadeTop; x2: 0; y2: comet.fadeBottom
                        GradientStop { position: 0; color: glow.a(glow.mix(glow.c1, glow.c0, 0.6), comet.k0 * (comet.c.soft ? 0.55 : 0.8 + 0.2 * glow.intensity)) }
                        GradientStop { position: 1; color: glow.a(glow.mix(glow.c1, glow.c0, 0.6), comet.c.soft ? 0.55 : 0.8 + 0.2 * glow.intensity) }
                    }
                    strokeStyle: ShapePath.DashLine
                    dashPattern: glow.dash(comet.c, 0.27, 1.35); dashOffset: glow.off(comet.c, 0.27, 1.35)
                    PathSvg { path: glow.d }
                }
                ShapePath {
                    fillColor: "transparent"; strokeWidth: 1.6; capStyle: ShapePath.RoundCap
                    strokeColor: "transparent"
                    strokeGradient: LinearGradient {
                        x1: 0; y1: comet.fadeTop; x2: 0; y2: comet.fadeBottom
                        GradientStop { position: 0; color: glow.a(Qt.lighter(glow.c0, 1.25), comet.k0 * (comet.c.soft ? 0.5 : 1)) }
                        GradientStop { position: 1; color: glow.a(Qt.lighter(glow.c0, 1.25), comet.c.soft ? 0.5 : 1) }
                    }
                    strokeStyle: ShapePath.DashLine
                    dashPattern: glow.dash(comet.c, 0.12, 1.6); dashOffset: glow.off(comet.c, 0.12, 1.6)
                    PathSvg { path: glow.d }
                }
            }
        }
    }
}
