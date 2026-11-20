import QtQuick

// panacea-local (panacea-island): "Save password?", drawn with the kit. Replaces Panacea's
// VaultSaveView (same `sys` API: vaultPrompt {pw, label}, vaultUnlocked, vaultBusy, vaultError,
// unlockVault, vaultAdd, dismissVaultPrompt, collapse). The island offers it when something
// that looks like a password lands on the clipboard; saved logins go to Proton Pass.
FocusScope {
    id: view
    property var sys
    readonly property var t: sys.pk
    readonly property var prompt: sys.vaultPrompt

    implicitHeight: col.implicitHeight

    Component.onCompleted: view.forceActiveFocus()
    FocusGrabber { target: view.sys.vaultUnlocked ? name.input : pw.input }

    Keys.onEscapePressed: view.sys.dismissVaultPrompt()

    function save() {
        if (!view.prompt) return;
        view.sys.vaultAdd(name.text.length ? name.text : view.sys.tr("Без названия"),
                          login.text, view.prompt.pw);
        view.sys.vaultPrompt = null;
        view.sys.collapse();
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.s4

        Row {
            width: parent.width; spacing: view.t.s3
            PkIcon { sys: view.sys; name: "key"; filled: true; size: view.t.iXl; color: view.t.fg
                     anchors.verticalCenter: parent.verticalCenter }
            Column {
                width: parent.width - view.t.iXl - parent.spacing; spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                PkText { sys: view.sys; role: "emph"; width: parent.width; text: view.sys.tr("Сохранить пароль?") }
                PkText { sys: view.sys; role: "sub"; width: parent.width; elide: Text.ElideRight
                         text: view.sys.vaultUnlocked ? view.sys.tr("Он попадёт в менеджер паролей") + " · Proton Pass"
                                                      : view.sys.tr("Сначала откройте хранилище своим паролем") }
            }
        }

        // the vault is locked: ask for the user password first
        PkField {
            id: pw
            visible: !view.sys.vaultUnlocked
            sys: view.sys; width: parent.width
            password: true; placeholder: view.sys.tr("Пароль пользователя")
            enabled: !view.sys.vaultBusy
            onAccepted: { view.sys.unlockVault(text); text = ""; }
        }
        Row {
            visible: !view.sys.vaultUnlocked && view.sys.vaultError.length > 0
            width: parent.width; spacing: view.t.s2
            PkIcon { sys: view.sys; name: "warning-circle"; size: view.t.iXs; color: view.t.accentText }
            PkText { sys: view.sys; role: "label"; width: parent.width - 24; wrapMode: Text.WordWrap
                     color: view.t.accentText; text: view.sys.vaultError }
        }

        // open: where it's from, the login, and the password (dots only: eyes nearby)
        Rectangle {
            visible: view.sys.vaultUnlocked
            width: parent.width; height: fields.implicitHeight + 2 * view.t.s2
            radius: view.t.rSurface; color: view.t.surface
            Column {
                id: fields
                x: view.t.s2; y: view.t.s2; width: parent.width - 2 * view.t.s2; spacing: view.t.s1
                PkField { id: name; sys: view.sys; width: parent.width; color: "transparent"
                          placeholder: view.sys.tr("Откуда пароль")
                          text: view.prompt ? String(view.prompt.label || "") : ""
                          onAccepted: view.save() }
                PkField { id: login; sys: view.sys; width: parent.width; color: "transparent"
                          placeholder: view.sys.tr("Логин (необязательно)"); onAccepted: view.save() }
                PkRow { sys: view.sys; icon: "password"; title: view.sys.tr("Пароль")
                        value: view.prompt ? "•".repeat(Math.min(16, String(view.prompt.pw).length)) : "" }
            }
        }

        Row {
            anchors.right: parent.right; spacing: view.t.s2
            PkButton { sys: view.sys; kind: "secondary"; text: view.sys.tr("Не сохранять")
                       onClicked: view.sys.dismissVaultPrompt() }
            PkButton { sys: view.sys; kind: "primary"; text: view.sys.tr("Сохранить")
                       enabled: view.sys.vaultUnlocked; onClicked: view.save() }
        }
    }
}
