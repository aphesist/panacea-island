import QtQuick

// panacea-local: the polkit password card, drawn with the kit (replaces Panacea's AuthView,
// same behaviour as auth-patch.py's version): a bare lock, "Password needed" and one plain
// line (polkit's own wording behind Details), a PkField, the kit's Cancel / Unlock buttons.
// Enter submits, Esc cancels; after a wrong password polkit asks again and the field gets
// its focus back. Fingerprint prompts (fprintd) show as a quiet line, errors in red.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk

    readonly property var flow: sys.authFlow
    property bool showDetails: false
    readonly property string raw: flow ? String(flow.message || "") : ""
    readonly property string action: flow ? String(flow.actionId || "") : ""
    readonly property string supp: flow ? String(flow.supplementaryMessage || "") : ""
    readonly property bool failed: !!(flow && flow.failed)
    readonly property bool fingerMsg: /finger|swipe|touch|dedo/i.test(view.supp)
    readonly property string plain: {
        // pkexec: "Authentication is needed to run `/usr/bin/bash /path/script.sh' as the super user"
        var m = /run [`'"]([^`'"]+)[`'"]/.exec(view.raw);
        if (m || view.action === "org.freedesktop.policykit.exec") {
            var words = m ? m[1].trim().split(/\s+/) : [];
            var name = words.length ? words[0].split("/").pop() : "";
            if (["bash", "sh", "zsh", "fish", "python", "python3", "env", "perl"].indexOf(name) >= 0 && words.length > 1)
                name = words[words[1].charAt(0) === "-" && words.length > 2 ? 2 : 1].split("/").pop();
            return name ? "Enter your password to run " + name + " as administrator."
                        : "Enter your password to run a command as administrator.";
        }
        var a = view.action;
        if (/systemd1/.test(a)) return "Enter your password to manage a system service.";
        if (/NetworkManager|nm-/.test(a)) return "Enter your password to change network settings.";
        if (/packagekit|pacman|pamac|flatpak/i.test(a)) return "Enter your password to install or remove software.";
        if (/login1/.test(a)) return "Enter your password to change power or session settings.";
        if (/udisks/i.test(a)) return "Enter your password to manage a disk.";
        if (/fprint/i.test(a)) return "Enter your password to change fingerprint settings.";
        if (/bluez|bluetooth/i.test(a)) return "Enter your password to change Bluetooth settings.";
        if (/timedate1|hostname1|locale1/.test(a)) return "Enter your password to change system settings.";
        return "Enter your password to allow this change.";
    }

    implicitHeight: col.implicitHeight

    focus: true
    Component.onCompleted: view.forceActiveFocus()
    FocusGrabber { target: pw.input }

    Keys.onEscapePressed: view.cancel()

    // After a wrong password polkit asks again, but the field is disabled while it checks and
    // loses focus: give it back on every request.
    Connections {
        target: view.flow
        ignoreUnknownSignals: true
        function onIsResponseRequiredChanged() {
            if (view.flow && view.flow.isResponseRequired) refocus.restart();
        }
    }
    Timer { id: refocus; interval: 30; onTriggered: { pw.input.forceActiveFocus(); pw.input.selectAll(); } }

    function submit() {
        if (!view.flow) return;
        view.flow.submit(pw.text);
        pw.text = "";
    }
    function cancel() {
        if (view.flow) view.flow.cancelAuthenticationRequest();
        view.sys.collapse();
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.s4

        // a bare lock, the title and one plain line; polkit's wording behind Details
        Row {
            width: parent.width
            spacing: view.t.s3
            PkIcon { id: lockIcon; sys: view.sys; name: "lock-simple"; filled: true; size: view.t.iXl
                     color: view.failed ? view.t.accentText : view.t.fg }
            Column {
                width: parent.width - lockIcon.width - parent.spacing
                spacing: view.t.s1
                PkText { sys: view.sys; role: "emph"; text: "Password needed"; width: parent.width }
                Text {
                    width: parent.width
                    text: view.plain
                    color: view.t.soft
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    font { family: view.t.font; pixelSize: view.t.tLabel }
                }
                Text {
                    visible: view.raw.length > 0
                    text: view.showDetails ? "Hide details" : "Details"
                    color: detMa.containsMouse ? view.t.fg : view.t.muted
                    font { family: view.t.font; pixelSize: view.t.tCaption; weight: Font.DemiBold }
                    Behavior on color { ColorAnimation { duration: view.t.dFast } }
                    MouseArea { id: detMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: view.showDetails = !view.showDetails }
                }
                Rectangle {
                    visible: view.showDetails
                    width: parent.width
                    height: detText.implicitHeight + 2 * view.t.s2
                    radius: view.t.rSmall
                    color: view.t.scrim
                    Text {
                        id: detText
                        x: view.t.s2 + 2; y: view.t.s2; width: parent.width - 2 * x
                        text: view.raw + (view.action ? "\n" + view.action : "")
                        color: view.t.muted
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        font { family: view.t.font; pixelSize: view.t.tCaption }
                    }
                }
            }
        }

        // the password
        PkField {
            id: pw
            sys: view.sys
            width: parent.width
            implicitHeight: 42
            // responseVisible: the answer may be shown (not a secret)
            password: !(view.flow && view.flow.responseVisible)
            placeholder: view.flow && view.flow.inputPrompt && !/^password:?\s*$/i.test(String(view.flow.inputPrompt))
                         ? String(view.flow.inputPrompt) : "Password"
            input.enabled: view.flow ? view.flow.isResponseRequired : false
            onAccepted: view.submit()
        }

        // a wrong password (red), or what polkit / fprintd says (quiet, with a fingerprint)
        Row {
            visible: view.failed || view.supp.length > 0
            width: parent.width
            spacing: view.t.s2
            readonly property bool bad: view.failed && !view.fingerMsg
            PkIcon { id: msgIcon; sys: view.sys; size: view.t.iSm; anchors.verticalCenter: parent.verticalCenter
                     name: parent.bad ? "warning" : view.fingerMsg ? "fingerprint" : "info"
                     color: parent.bad ? view.t.accentText : view.t.muted }
            Text {
                width: parent.width - msgIcon.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: view.supp.length > 0 ? view.supp : "Wrong password, try again"
                color: parent.bad ? view.t.accentText : view.t.soft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font { family: view.t.font; pixelSize: view.t.tLabel }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: view.t.s2
            PkButton { sys: view.sys; kind: "secondary"; text: "Cancel"; implicitWidth: 92; onClicked: view.cancel() }
            PkButton { sys: view.sys; kind: "primary"; text: "Unlock"; icon: "lock-simple-open"; implicitWidth: 104
                       enabled: view.flow ? view.flow.isResponseRequired : false
                       onClicked: view.submit() }
        }
    }
}
