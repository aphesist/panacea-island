import QtQuick
import QtQuick.Effects

// Panacea kit - an image with rounded corners (album art, thumbnails): the picture is masked by
// a rounded rectangle, the way Panacea's own media card does it. Shows `placeholder` (a grey
// surface) until the image is ready.
Item {
    id: ri
    property var sys
    readonly property var t: sys.pk
    property alias source: img.source
    property alias status: img.status
    property real radius: t.rSmall
    property size sourceSize: Qt.size(160, 160)
    Rectangle { anchors.fill: parent; radius: ri.radius; color: ri.t.surface }
    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; smooth: true
        sourceSize: ri.sourceSize
        visible: false
        layer.enabled: true
    }
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: ri.radius; color: "#ffffff" }
    }
    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        visible: img.status === Image.Ready
    }
}
