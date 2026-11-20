pragma ComponentBehavior: Bound
import QtQuick

// written by portal-patch.py (panacea-config) - Notifications, an island screen built from the
// Pk kit (replaces Panacea's NotificationsView). Opened by the bell, top right. Every card is a
// PkNotifCard, the same card the island shows when one arrives.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    readonly property int count: sys.notifications ? sys.notifications.count : 0
    implicitHeight: col.implicitHeight

    focus: true
    Component.onCompleted: forceActiveFocus()
    function goBack() { view.sys.page = "main"; return true; }
    Keys.onEscapePressed: view.goBack()

    Column {
        id: col
        width: parent.width
        spacing: view.t.groupGap

        PkHeader {
            id: head
            sys: view.sys; width: parent.width
            title: "Notifications"
            sub: view.count === 0 ? (view.sys.dnd ? "Focus is on" : "Nothing new")
                 : (view.count === 1 ? "1 notification" : view.count + " notifications") + (view.sys.dnd ? "  ·  Focus is on" : "")
            PkIconButton { sys: view.sys; icon: "moon"; size: view.t.iMd; selected: view.sys.dnd
                           onClicked: view.sys.toggleDnd() }
            PkButton { sys: view.sys; small: true; kind: "secondary"; text: "Clear all"; visible: view.count > 0
                       anchors.verticalCenter: parent.verticalCenter; onClicked: view.sys.clearNotifications() }
        }

        ListView {
            id: list
            width: parent.width
            visible: view.count > 0
            height: Math.min(contentHeight, (view.sys.pageMaxH || 545) - head.height - view.t.groupGap)
            clip: true
            spacing: view.t.gap
            model: view.sys.notifications
            boundsBehavior: Flickable.StopAtBounds
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: view.t.dBase } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: view.t.dFast } }
            displaced: Transition { NumberAnimation { property: "y"; duration: view.t.dBase; easing.type: Easing.OutCubic } }
            delegate: PkNotifCard {
                required property int index
                required property int nId
                required property string nSummary
                required property string nBody
                required property string nApp
                required property string nImage
                required property bool nUrgent
                required property string nTime
                sys: view.sys
                width: list.width
                app: nApp; summary: nSummary; body: nBody; image: nImage; urgent: nUrgent; time: nTime
                onClicked: view.sys.activateNotification(nId)
                onClosed: view.sys.forgetNotification(index)
            }
        }

        // nothing here
        Item {
            width: parent.width; height: 150
            visible: view.count === 0
            Column {
                anchors.centerIn: parent; spacing: 10
                PkIcon { sys: view.sys; anchors.horizontalCenter: parent.horizontalCenter
                         name: view.sys.dnd ? "bell-slash" : "bell"; size: view.t.iXl; color: view.t.faint }
                PkText { sys: view.sys; role: "sub"; anchors.horizontalCenter: parent.horizontalCenter
                         text: view.sys.dnd ? "Focus is on: new ones wait quietly here" : "You're all caught up" }
            }
        }
    }
}
