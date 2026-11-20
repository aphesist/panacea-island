pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// written by portal-patch.py (panacea-config) - Screen, an island screen built from the Pk kit:
// screenshots (area / window / screen, with a delay), text from the screen, a colour picker,
// recording, the last screenshots and picked colours. The work is scripts/custom/screen.py.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    implicitHeight: col.implicitHeight

    property string delay: "0"
    property var colors: []
    readonly property string shotsDir: Quickshell.env("HOME") + "/Pictures/Screenshots"

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: view.sys.collapse()

    function run(mode) {
        Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/panacea/scripts/custom/screen.py", mode,
                                 mode === "text" || mode === "color" ? "0" : view.delay]);
        view.sys.collapse();
    }

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/panacea-colors.json"
        printErrors: false; watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { view.colors = JSON.parse(text()) || []; } catch (e) {} }
    }
    FolderListModel {
        id: shots
        folder: "file://" + view.shotsDir
        nameFilters: ["*.png", "*.jpg"]
        showDirs: false
        sortField: FolderListModel.Time
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.groupGap

        PkHeader {
            sys: view.sys; width: parent.width; title: "Screen"
            PkIconButton { sys: view.sys; icon: "folder-open"; size: view.t.iMd
                           onClicked: { Quickshell.execDetached(["xdg-open", view.shotsDir]); view.sys.collapse(); } }
        }

        // screenshot: what to take
        Column {
            width: parent.width; spacing: view.t.s2
            Row {
                width: parent.width; spacing: view.t.gap
                Repeater {
                    model: [{ m: "area", icon: "selection", label: "Area" },
                            { m: "window", icon: "app-window", label: "Window" },
                            { m: "screen", icon: "monitor", label: "Screen" }]
                    delegate: PkCard {
                        id: cap
                        required property var modelData
                        sys: view.sys; interactive: true
                        width: (col.width - 2 * view.t.gap) / 3; height: 92
                        onClicked: view.run(cap.modelData.m)
                        PkIcon { sys: view.sys; anchors.horizontalCenter: parent.horizontalCenter; y: 20
                                 name: cap.modelData.icon; size: view.t.iXl; filled: cap.hovered; color: view.t.fg }
                        PkText { sys: view.sys; role: "label"; anchors.horizontalCenter: parent.horizontalCenter
                                 anchors.bottom: parent.bottom; anchors.bottomMargin: 16; text: cap.modelData.label }
                    }
                }
            }
            Item {
                width: parent.width; height: 34
                PkText { sys: view.sys; role: "sub"; x: 6; anchors.verticalCenter: parent.verticalCenter
                         text: "Saved to Pictures/Screenshots and copied" }
                PkSegmented {
                    sys: view.sys; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    options: [{ id: "0", text: "Now" }, { id: "3", text: "3 s" }, { id: "10", text: "10 s" }]
                    value: view.delay
                    onPicked: id => view.delay = id
                }
            }
        }

        PkSection {
            sys: view.sys; width: parent.width
            PkRow { sys: view.sys; icon: "text-t"; title: "Text from the screen"; sub: "Draw a box around it; the text is copied"
                    interactive: true; onClicked: view.run("text") }
            PkRow { sys: view.sys; icon: "eyedropper"; title: "Pick a colour"; sub: "Click any pixel; its hex code is copied"
                    interactive: true; onClicked: view.run("color") }
            PkRow { sys: view.sys; icon: "record"; title: "Record the screen"; caret: true
                    sub: view.sys.recActive ? "Recording  ·  " + view.sys.recTimeText : "Screen, window or area, with sound"
                    onClicked: view.sys.togglePage("record") }
        }

        // picked colours: a click copies one again
        Column {
            width: parent.width; spacing: view.t.s2
            visible: view.colors.length > 0
            PkText { sys: view.sys; role: "caption"; x: 6; text: "Colours" }
            Row {
                spacing: view.t.s2
                Repeater {
                    model: view.colors
                    delegate: Rectangle {
                        id: sw
                        required property string modelData
                        width: swText.implicitWidth + 40; height: 30; radius: 15
                        color: swMa.containsMouse ? view.t.selected : view.t.surface
                        Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 9; color: sw.modelData }
                        PkText { id: swText; sys: view.sys; role: "label"; x: 30; anchors.verticalCenter: parent.verticalCenter; text: sw.modelData }
                        MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: view.sys.copyText(sw.modelData) }
                    }
                }
            }
        }

        // the last screenshots: a click opens one
        Column {
            width: parent.width; spacing: view.t.s2
            visible: shots.count > 0
            PkText { sys: view.sys; role: "caption"; x: 6; text: "Recent" }
            Row {
                spacing: view.t.gap
                Repeater {
                    model: Math.min(4, shots.count)
                    delegate: Rectangle {
                        id: th
                        required property int index
                        readonly property string path: shots.get(index, "filePath")
                        width: (col.width - 3 * view.t.gap) / 4; height: width * 0.625
                        radius: view.t.rSmall; color: "transparent"
                        PkRoundImage { sys: view.sys; anchors.fill: parent; radius: view.t.rSmall
                                       source: th.path ? "file://" + th.path : ""; sourceSize: Qt.size(240, 150) }
                        Rectangle { anchors.fill: parent; radius: parent.radius; color: thMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent" }
                        MouseArea { id: thMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { Quickshell.execDetached(["xdg-open", th.path]); view.sys.collapse(); } }
                    }
                }
            }
        }
    }
}
