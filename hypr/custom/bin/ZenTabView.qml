pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

// written by portal-patch.py (panacea-config) - the island's Zen tab: open Zen, a new window
// or a private one, the search; your pinned tabs and recent tabs (click to switch, x to
// close), reopen the last closed tab. Data from panacea-dock.uc.js
// ($XDG_RUNTIME_DIR/panacea-zen-tabs.json); clicks go back through panacea-zen-cmd.
// Zen's web notifications land in the island's own notifications. Plain code, no AI.
FocusScope {
    id: view
    property var sys
    implicitHeight: col.implicitHeight
    focus: true

    readonly property var info: sys.zenTabs || ({})
    readonly property var pinned: (info.pinned || []).slice(0, 12)
    readonly property var recent: (info.recent || []).slice(0, 5)
    readonly property bool running: !!sys.zenRunning
    readonly property real boxR: 16

    function goBack() { return false; }
    function iconUrl(it) { return it && it.icon ? "file://" + it.icon : ""; }

    Keys.onEscapePressed: sys.collapse()

    // ---------------------------------------------------------------- actions
    component Action: Rectangle {
        id: act
        property string label
        property int glyph: 0
        property bool logo: false
        signal activated()
        Layout.fillWidth: true
        Layout.preferredHeight: 60
        radius: view.boxR
        color: actMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
        Behavior on color { ColorAnimation { duration: 140 } }
        Column {
            anchors.centerIn: parent
            spacing: 6
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 20; height: 20
                Image {
                    anchors.fill: parent
                    visible: act.logo
                    source: act.logo ? Qt.resolvedUrl("zen-logo.svg") : ""
                    sourceSize: Qt.size(64, 64)
                    smooth: true; mipmap: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: !act.logo
                    text: act.glyph ? String.fromCodePoint(act.glyph) : ""
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: 18 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: act.label
                color: actMa.containsMouse ? view.sys.colFg : view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: 11; bold: true }
            }
        }
        MouseArea {
            id: actMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.activated()
        }
    }

    component SectionLabel: Text {
        color: view.sys.colMuted
        font { family: view.sys.fontFam; pixelSize: 11; bold: true }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Action { label: view.running ? "Open Zen" : "Start Zen"; logo: true; onActivated: view.sys.zenOpenApp() }
            Action { label: "New window"; glyph: 0xF0415; onActivated: view.sys.zenLaunch(["--new-window"]) }
            Action { label: "Private"; glyph: 0xF05E9; onActivated: view.sys.zenLaunch(["--private-window"]) }
            Action { label: "Search"; glyph: 0xF0349; onActivated: view.sys.zenOpenSearch(false) }
        }

        // ------------------------------------------------------------ pinned
        SectionLabel {
            Layout.topMargin: 6
            Layout.leftMargin: 4
            visible: view.pinned.length > 0
            text: "Pinned"
        }
        Flow {
            id: pinFlow
            Layout.fillWidth: true
            visible: view.pinned.length > 0
            spacing: 8
            readonly property real tileW: (width - spacing * 5) / 6
            Repeater {
                model: view.pinned
                delegate: Rectangle {
                    id: pin
                    required property var modelData
                    width: pinFlow.tileW
                    height: 62
                    radius: view.boxR - 2
                    color: pinMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
                         : pin.modelData.selected ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Image {
                        id: pinIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 11
                        width: 20; height: 20
                        sourceSize: Qt.size(40, 40)
                        smooth: true
                        source: view.iconUrl(pin.modelData)
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: pinIcon
                        visible: !pinIcon.visible
                        text: String.fromCodePoint(0xF059F)
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: 17 }
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                        text: (pin.modelData.host || "").replace(/^www\./, "") || pin.modelData.title
                        color: pin.modelData.selected ? view.sys.colFg : view.sys.colMuted
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font { family: view.sys.fontFam; pixelSize: 9 }
                    }
                    MouseArea {
                        id: pinMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.sys.zenCmd("select", pin.modelData.key)
                    }
                }
            }
        }

        // ------------------------------------------------------------ recent
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.leftMargin: 4
            visible: view.recent.length > 0 || (view.info.closed || 0) > 0
            SectionLabel { text: "Recent tabs"; Layout.fillWidth: true }
            Rectangle {
                visible: (view.info.closed || 0) > 0
                Layout.preferredHeight: 22
                Layout.preferredWidth: reopenText.implicitWidth + 18
                radius: 11
                color: reopenMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                Text {
                    id: reopenText
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF0B53) + "  Reopen closed"
                    color: reopenMa.containsMouse ? view.sys.colFg : view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: 10 }
                }
                MouseArea {
                    id: reopenMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.zenCmd("undoClose", "")
                }
            }
        }
        Column {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
                model: view.recent
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: parent.width
                    height: 44
                    radius: view.boxR - 2
                    color: rowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 12
                        Item {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            Image {
                                id: rowIcon
                                anchors.centerIn: parent
                                width: 16; height: 16
                                sourceSize: Qt.size(32, 32)
                                smooth: true
                                source: view.iconUrl(row.modelData)
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !rowIcon.visible
                                text: String.fromCodePoint(0xF04E9)
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 15 }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title || row.modelData.url
                                color: view.sys.colFg
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font { family: view.sys.fontFam; pixelSize: 13; bold: !!row.modelData.selected }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (row.modelData.selected ? "Current tab · " : "") + (row.modelData.host || row.modelData.url || "")
                                color: view.sys.colMuted
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                font { family: view.sys.fontFam; pixelSize: 10 }
                            }
                        }
                        Rectangle {
                            // close the tab
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            radius: 13
                            opacity: rowMa.containsMouse || closeMa.containsMouse ? 1 : 0
                            color: closeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF0156)
                                color: closeMa.containsMouse ? view.sys.colFg : view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: 13 }
                            }
                            MouseArea {
                                id: closeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: view.sys.zenCmd("close", row.modelData.key)
                            }
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => view.sys.zenCmd(mouse.button === Qt.MiddleButton ? "close" : "select", row.modelData.key)
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 4
            visible: !view.running || (view.pinned.length === 0 && view.recent.length === 0)
            horizontalAlignment: Text.AlignHCenter
            text: view.running ? "No tabs to show yet" : "Zen isn't running"
            color: view.sys.colMuted
            font { family: view.sys.fontFam; pixelSize: 12 }
        }
    }
}
