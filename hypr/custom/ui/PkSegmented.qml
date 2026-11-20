import QtQuick

// Panacea kit - a segmented control: one pill slides (and stretches) to the chosen option.
// options: ["All", "Errors"] or [{ id, text }]; value: the chosen id (or text).
Rectangle {
    id: sg
    property var sys
    readonly property var t: sys.pk
    property var options: []
    property string value: ""
    signal picked(string id)
    function idOf(o) { return typeof o === "string" ? o : (o.id || o.text); }
    function textOf(o) { return typeof o === "string" ? o : (o.text || o.id); }
    implicitHeight: 32; implicitWidth: segRow.implicitWidth + 6
    radius: height / 2
    color: t.surface
    property Item active: null
    Rectangle {
        visible: sg.active !== null
        y: 3; height: sg.height - 6; radius: height / 2
        x: sg.active ? segRow.x + sg.active.x : 3
        width: sg.active ? sg.active.width : 0
        color: sg.t.selected
        Behavior on x { NumberAnimation { duration: sg.t.dSlow; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: sg.t.dSlow; easing.type: Easing.OutCubic } }
    }
    Row {
        id: segRow
        x: 3; anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: sg.options
            delegate: Item {
                id: opt
                required property var modelData
                readonly property bool on: sg.idOf(modelData) === sg.value
                width: lbl.implicitWidth + 24; height: sg.height - 6
                onOnChanged: if (on) sg.active = opt
                Component.onCompleted: if (on) sg.active = opt
                PkText { id: lbl; sys: sg.sys; role: "label"; anchors.centerIn: parent; text: sg.textOf(opt.modelData)
                         color: opt.on ? sg.t.fg : optMa.containsMouse ? sg.t.soft : sg.t.muted }
                MouseArea { id: optMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: sg.picked(sg.idOf(opt.modelData)) }
            }
        }
    }
}
