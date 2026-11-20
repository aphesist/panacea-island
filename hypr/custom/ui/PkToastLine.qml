import QtQuick
import QtQuick.Layouts

// A collapsed-island status line: a bare icon, a caption over a name, then trailing
// children (a PkRing). `bad` turns icon and caption red (lost, low).
RowLayout {
    property var sys
    readonly property var t: sys.pk
    id: line
    property string icon: ""
    property bool iconFilled: true
    property bool bad: false
    property string caption: ""
    property string name: ""
    default property alias trailing: tail.data
    anchors.centerIn: parent
    spacing: line.t.s3
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: line.t.dFast } }
    PkIcon { sys: line.sys; Layout.alignment: Qt.AlignVCenter; name: line.icon; filled: line.iconFilled
             size: line.t.iLg; color: line.bad ? line.t.accentText : line.t.fg }
    Column {
        Layout.alignment: Qt.AlignVCenter
        spacing: 1
        Text { text: line.caption; color: line.bad ? line.t.accentText : line.t.muted
               font { family: line.t.font; pixelSize: line.t.tCaption; weight: Font.DemiBold } }
        Text { width: Math.min(implicitWidth, 220); text: line.name; elide: Text.ElideRight; color: line.t.fg
               font { family: line.t.font; pixelSize: line.t.tEmph; weight: Font.DemiBold } }
    }
    Item { id: tail; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: line.t.s5 + line.t.s4
           implicitWidth: childrenRect.width; implicitHeight: childrenRect.height
           visible: children.length > 0 }
}
