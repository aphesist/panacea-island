pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// panacea-config settings kit: written by portal-patch.py over Panacea's own file (the original
// is kept as <name>.pristine). Same API as the original, drawn with the Pk kit (ui/DESIGN.md).
// One of many: a pill showing the choice; a click unfolds the list (searchable if asked).
ColumnLayout {
    id: pick
    property var sys
    readonly property var t: sys.pk
    property string label: ""
    property var options: []
    property string value: ""
    property bool open: false
    property bool searchable: false
    property string query: ""
    property int visibleRows: 7
    signal picked(string id)

    function idOf(o)   { return (o && o.id !== undefined) ? o.id : o; }
    function textOf(o) { return (o && o.text !== undefined) ? o.text : o; }
    function textFor(id) {
        for (var i = 0; i < pick.options.length; i++)
            if (idOf(pick.options[i]) === id) return textOf(pick.options[i]);
        return id;
    }
    readonly property var filteredOptions: {
        if (!pick.searchable || !pick.query.length) return pick.options;
        var q = pick.query.toLowerCase();
        return pick.options.filter(o => String(pick.textOf(o)).toLowerCase().indexOf(q) >= 0
                                        || String(pick.idOf(o)).toLowerCase().indexOf(q) >= 0);
    }
    onOpenChanged: if (!open) { query = ""; searchField.clear(); } else if (searchable) searchField.forceActiveFocus()

    Layout.fillWidth: true
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 16
        Text {
            Layout.fillWidth: true
            text: pick.label; color: pick.t.fg; elide: Text.ElideRight
            font { family: pick.t.font; pixelSize: pick.t.tBody }
        }
        Rectangle {
            Layout.preferredWidth: Math.min(260, Math.max(140, curText.implicitWidth + 48))
            Layout.preferredHeight: 32
            radius: height / 2
            color: headMa.containsMouse || pick.open ? pick.t.veil(0.15) : pick.t.veil(0.08)
            Behavior on color { ColorAnimation { duration: pick.t.dFast } }
            Text {
                id: curText
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.right: chev.left; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: pick.textFor(pick.value); color: pick.t.fg; elide: Text.ElideRight
                font { family: pick.t.font; pixelSize: pick.t.tLabel; weight: Font.DemiBold }
            }
            PkIcon {
                id: chev
                sys: pick.sys
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "caret-down"; size: 12; color: pick.t.muted
                rotation: pick.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: pick.t.dBase; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: headMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pick.open = !pick.open
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: pick.open
            ? Math.min(pick.visibleRows, Math.max(1, pick.filteredOptions.length)) * 34 + 12
              + (pick.searchable ? 42 : 0) : 0
        clip: true
        visible: Layout.preferredHeight > 0
        radius: pick.t.rControl
        color: pick.t.veil(0.05)
        Behavior on Layout.preferredHeight { NumberAnimation { duration: pick.t.dBase; easing.type: Easing.OutCubic } }

        Rectangle {
            visible: pick.searchable
            x: 6; y: 6; width: parent.width - 12; height: 34; radius: 17
            color: pick.t.veil(0.07)
            PkIcon { sys: pick.sys; x: 12; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; size: 14; color: pick.t.muted }
            TextField {
                id: searchField
                x: 32; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                placeholderText: pick.sys.tr("Поиск языка или кода")
                onTextEdited: pick.query = text
                color: pick.t.fg
                placeholderTextColor: pick.t.muted
                background: null
                font { family: pick.t.font; pixelSize: pick.t.tLabel }
            }
        }
        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 6
            anchors.topMargin: pick.searchable ? 46 : 6
            clip: true
            model: pick.filteredOptions
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: -1
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property string oid: pick.idOf(opt.modelData)
                readonly property bool chosen: pick.value === opt.oid
                width: list.width; height: 34
                radius: pick.t.rSmall
                color: optMa.containsMouse ? pick.t.hover : "transparent"
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.right: tick.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: pick.textOf(opt.modelData)
                    color: opt.chosen ? pick.t.fg : pick.t.soft
                    elide: Text.ElideRight
                    font { family: pick.t.font; pixelSize: pick.t.tLabel; weight: opt.chosen ? Font.DemiBold : Font.Normal }
                }
                PkIcon { id: tick; sys: pick.sys; visible: opt.chosen; anchors.right: parent.right; anchors.rightMargin: 12
                         anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 14; color: pick.t.fg }
                MouseArea {
                    id: optMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { pick.picked(opt.oid); pick.open = false; }
                }
            }
        }
    }
}
