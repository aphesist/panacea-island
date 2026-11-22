import QtQuick
import QtQuick.Shapes

// written by portal-patch.py (panacea-island) - boopis's own "bots" glyph (a round face, two eyes),
// redrawn from boopis apps/desktop/ui/src/components/icons.ts (20 grid: circle r 6.75, eyes
// M8 8.6v2.4 M12 8.6v2.4, round caps). boopis: Apache License 2.0, (c) aphesist.
// Stroke weighted to sit with the kit's Phosphor Bold icons.
Item {
    id: g
    property real size: 17
    property color color: "white"
    width: size; height: size
    readonly property real u: size / 20 * 1.12          // boopis draws 18 px on its 20 grid; Phosphor Bold fills more
    readonly property real sw: Math.max(1.4, size / 10.5)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: g.color; strokeWidth: g.sw; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: g.size / 2; centerY: g.size / 2; radiusX: 6.75 * g.u; radiusY: 6.75 * g.u; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: g.color; strokeWidth: g.sw; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: g.size / 2 - 2 * g.u; startY: g.size / 2 - 1.4 * g.u
            PathLine { x: g.size / 2 - 2 * g.u; y: g.size / 2 + 1.0 * g.u }
            PathMove { x: g.size / 2 + 2 * g.u; y: g.size / 2 - 1.4 * g.u }
            PathLine { x: g.size / 2 + 2 * g.u; y: g.size / 2 + 1.0 * g.u }
        }
    }
}
