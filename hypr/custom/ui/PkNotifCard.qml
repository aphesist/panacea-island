import QtQuick

// Panacea kit - a notification: the app's icon in a small tile, "App · 14:02" (a red dot when
// urgent), the title, up to three lines of text. A click opens it; the x (on hover) forgets it.
Rectangle {
    id: nc
    property var sys
    readonly property var t: sys.pk
    property string app: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    property string time: ""
    property bool urgent: false
    property int lines: 3
    signal clicked()
    signal closed()

    implicitHeight: Math.max(64, textCol.implicitHeight + 28)
    radius: t.rSurface
    color: ma.containsMouse ? t.veil(0.1) : t.surface
    Behavior on color { ColorAnimation { duration: nc.t.dFast } }

    MouseArea {
        id: ma; anchors.fill: parent; z: 2; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nc.clicked()
        // inside the card's hover area, so pointing at it keeps it shown
        PkIconButton {
            sys: nc.sys
            anchors.right: parent.right; anchors.rightMargin: 8; y: 8
            icon: "x"; size: 13
            opacity: ma.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: nc.t.dFast } }
            onClicked: nc.closed()
        }
    }

    Rectangle {
        id: tile
        x: 14; y: 14; width: 36; height: 36; radius: nc.t.rSmall
        color: nc.t.veil(0.08)
        Image {
            id: img
            anchors.fill: parent; anchors.margins: 6
            source: nc.image
            visible: nc.image !== "" && status === Image.Ready
            fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true
            sourceSize: Qt.size(64, 64)
        }
        PkIcon { sys: nc.sys; anchors.centerIn: parent; visible: !img.visible
                 name: nc.urgent ? "warning-circle" : "bell"; filled: true; size: 18
                 color: nc.urgent ? nc.t.accentText : nc.t.soft }
    }

    Column {
        id: textCol
        x: 62; y: 13; width: parent.width - x - 40
        spacing: 3
        Row {
            spacing: 6
            Rectangle { visible: nc.urgent; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: nc.t.accent }
            PkText { sys: nc.sys; role: "caption"; text: [nc.app, nc.time].filter(x => x).join("  ·  ") }
        }
        PkText { sys: nc.sys; role: "emph"; width: parent.width; text: nc.summary; visible: text !== "" }
        Text {
            width: parent.width
            visible: nc.body !== ""
            text: nc.body
            color: nc.t.soft
            wrapMode: Text.Wrap
            maximumLineCount: nc.lines
            elide: Text.ElideRight
            textFormat: Text.StyledText      // the spec allows <b>, <i>, <a> in the body
            linkColor: nc.t.fg
            font { family: nc.t.font; pixelSize: nc.t.tLabel }
            lineHeight: 1.1
        }
    }
}
