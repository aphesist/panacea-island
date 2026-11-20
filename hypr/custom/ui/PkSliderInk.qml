import QtQuick

// Panacea kit - what sits on a PkVSlider in one ink: the value at the top, the icon at the
// bottom. The slider draws it twice (white on the track, black inside the fill).
Item {
    id: ink
    property Item slider
    property color color: "white"
    property color subColor: "white"
    width: slider.width; height: slider.height
    PkText {
        sys: ink.slider.sys; role: "caption"; visible: ink.slider.showValue
        anchors.horizontalCenter: parent.horizontalCenter; y: 14
        text: Math.round(ink.slider.value * 100) + "%"
        color: ink.subColor
    }
    PkIcon {
        sys: ink.slider.sys; anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 16
        name: ink.slider.icon; filled: true; size: ink.slider.t.iMd + 2
        color: ink.color
    }
}
