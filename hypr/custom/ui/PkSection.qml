import QtQuick

// Panacea kit - a group: a caption, then one card holding rows (PkRow) or anything else,
// inset 6 so the rows' corners run parallel to the card's. note: a quiet line under it.
Column {
    id: sc
    property var sys
    readonly property var t: sys.pk
    property string title: ""
    property string note: ""
    default property alias content: inner.data
    spacing: 8
    PkText { sys: sc.sys; role: "caption"; visible: sc.title !== ""; x: 6; text: sc.title }
    Rectangle {
        width: sc.width; height: inner.implicitHeight + 12
        radius: sc.t.rSurface; color: sc.t.surface
        Column { id: inner; x: 6; y: 6; width: parent.width - 12 }
    }
    PkText { sys: sc.sys; role: "sub"; visible: sc.note !== ""; x: 6; width: sc.width - 12; text: sc.note; wrapMode: Text.Wrap }
}
