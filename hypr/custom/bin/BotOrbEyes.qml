import QtQuick
import QtQuick.Shapes

// One layer of a BotOrb's eyes: up to six groups (two sets cross-fading) (each with its own opacity, orb2 fades eyes at
// the rim), squashed around the eyes' centre for a blink and slid by (dx, dy) during a morph.
Shape {
    id: ey
    property var eyes: []            // [[alpha, "M..Z.."], ...]
    property var lay: ({ a: 1, sy: 1, dx: 0, dy: 0, ec: [0, 0] })
    property color ink: "#141418"
    preferredRendererType: Shape.CurveRenderer
    visible: eyes.length > 0
    transform: [
        Scale { origin.x: ey.lay.ec[0]; origin.y: ey.lay.ec[1]; yScale: ey.lay.sy },
        Translate { x: ey.lay.dx; y: ey.lay.dy }
    ]
    ShapePath { strokeWidth: -1; strokeColor: "transparent"
        fillColor: Qt.rgba(ey.ink.r, ey.ink.g, ey.ink.b, ey.eyes.length > 0 ? ey.eyes[0][0] * ey.lay.a : 0)
        PathSvg { path: ey.eyes.length > 0 ? ey.eyes[0][1] : "" } }
    ShapePath { strokeWidth: -1; strokeColor: "transparent"
        fillColor: Qt.rgba(ey.ink.r, ey.ink.g, ey.ink.b, ey.eyes.length > 1 ? ey.eyes[1][0] * ey.lay.a : 0)
        PathSvg { path: ey.eyes.length > 1 ? ey.eyes[1][1] : "" } }
    ShapePath { strokeWidth: -1; strokeColor: "transparent"
        fillColor: Qt.rgba(ey.ink.r, ey.ink.g, ey.ink.b, ey.eyes.length > 2 ? ey.eyes[2][0] * ey.lay.a : 0)
        PathSvg { path: ey.eyes.length > 2 ? ey.eyes[2][1] : "" } }
    ShapePath { strokeWidth: -1; strokeColor: "transparent"
        fillColor: Qt.rgba(ey.ink.r, ey.ink.g, ey.ink.b, ey.eyes.length > 3 ? ey.eyes[3][0] * ey.lay.a : 0)
        PathSvg { path: ey.eyes.length > 3 ? ey.eyes[3][1] : "" } }
    ShapePath { strokeWidth: -1; strokeColor: "transparent"
        fillColor: Qt.rgba(ey.ink.r, ey.ink.g, ey.ink.b, ey.eyes.length > 4 ? ey.eyes[4][0] * ey.lay.a : 0)
        PathSvg { path: ey.eyes.length > 4 ? ey.eyes[4][1] : "" } }
    ShapePath { strokeWidth: -1; strokeColor: "transparent"
        fillColor: Qt.rgba(ey.ink.r, ey.ink.g, ey.ink.b, ey.eyes.length > 5 ? ey.eyes[5][0] * ey.lay.a : 0)
        PathSvg { path: ey.eyes.length > 5 ? ey.eyes[5][1] : "" } }
}
