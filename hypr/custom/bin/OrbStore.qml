import QtQuick
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-island) - frames of the boopis bot faces (orb2), recorded as
// vectors by tools/orb-frames (record.py, then smooth.py): one JSON per body shape,
// {shape, fps, clips: {spin, idle, listening, ..., "<r>>in", "<r>>out"}}, a frame =
// {b: [x0, y0, ... 80 body points from the top], e: [[alpha, "M..Z.."], ...]} in orb units.
// Colour is not in the data: one shape's frames serve every bot of that shape. install.sh unpacks
// them into ~/.local/share/panacea-island/orbs. Each shape loads on first use and is kept.
// The shell has one instance (sys.orbs).
Item {
    id: store
    visible: false
    property string dir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/panacea-island/orbs/"
    property var _cache: ({})
    property int version: 0                    // bumps when a shape arrives: bindings re-read
    readonly property var shapes: ["circle", "squircle", "soft", "wide", "tall", "bean", "drop", "ghost",
                                   "triangle", "hexagon", "diamond", "cloud", "clover", "flower", "star"]
    property bool missing: false               // no frames installed (the orbs draw nothing)

    Component { id: reader; FileView { blockLoading: true; printErrors: false } }

    function get(shape) {
        var s = shapes.indexOf(shape) >= 0 ? shape : "circle";
        if (_cache[s] !== undefined) return _cache[s];
        var fv = reader.createObject(store, { path: dir + s + ".json" });
        var d = null;
        try { d = JSON.parse(fv.text()); } catch (e) { missing = true; console.warn("orbs: no frames for", s, "in", dir); }
        fv.destroy();
        _cache[s] = d;
        version++;
        return d;
    }
}
