pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// panacea-local (panacea-island): the password manager, drawn with the kit. Replaces Panacea's
// VaultView (same `sys` API: vaultUnlocked / vaultEntries [{id,label,login,pw,at,url}] /
// vaultError / vaultBusy, unlockVault, lockVault, touchVault, vaultAdd / vaultUpdate /
// vaultRemove, vaultCopy, browserScan / browserImport / browserImportAll / browserFound...).
// The data is Proton Pass: scripts/vault.sh hands over to scripts/custom/vault-proton.py.
//
// Locked: the user password. Open: a search pill and the logins; a login opens its card
// (username, password with reveal, website, last change), copy buttons, edit, remove.
// The vault locks itself after 15 minutes without use; any movement here keeps it open.
FocusScope {
    id: view
    property var sys
    readonly property var t: sys.pk
    readonly property int maxH: sys.pageMaxH || 545

    implicitHeight: col.implicitHeight

    Component.onCompleted: view.forceActiveFocus()
    FocusGrabber { target: !view.sys.vaultUnlocked ? pwField.input
                         : view.mode === "edit" || view.mode === "new" ? fLabel.input
                         : view.mode === "" ? search.input : null }

    // any movement keeps the open vault alive
    MouseArea {
        anchors.fill: parent; z: -1
        acceptedButtons: Qt.NoButton; hoverEnabled: true
        onPositionChanged: view.sys.touchVault()
    }

    property string query: ""
    property string openId: ""        // the login whose card is open
    property string mode: ""          // "" list | "card" | "edit" | "new"
    property bool reveal: false       // the open card shows its password
    property bool confirmRemove: false

    readonly property var current: {
        if (view.openId === "") return null;
        var a = view.sys.vaultEntries;
        for (var i = 0; i < a.length; i++) if (String(a[i].id) === view.openId) return a[i];
        return null;
    }
    onCurrentChanged: if (view.mode !== "new" && view.mode !== "" && !view.current) view.closeCard()

    readonly property var shown: {
        var q = view.query.trim().toLowerCase();
        var a = view.sys.vaultEntries.slice();
        a.sort(function (x, y) { return String(x.label).toLowerCase().localeCompare(String(y.label).toLowerCase()); });
        if (q.length === 0) return a;
        return a.filter(function (e) {
            return String(e.label).toLowerCase().indexOf(q) >= 0
                || String(e.login).toLowerCase().indexOf(q) >= 0
                || String(e.url || "").toLowerCase().indexOf(q) >= 0;
        });
    }

    function host(u) {
        var s = String(u || "").replace(/^[a-z]+:\/\//i, "").replace(/^www\./i, "");
        return s.split(/[\/?#]/)[0];
    }
    function openCard(id) { view.openId = String(id); view.mode = "card"; view.reveal = false; view.confirmRemove = false; view.sys.touchVault(); }
    function closeCard() { view.openId = ""; view.mode = ""; view.reveal = false; view.confirmRemove = false; }
    function startNew() { view.openId = ""; view.mode = "new"; fLabel.text = ""; fLogin.text = ""; fPw.text = ""; view.reveal = false; }
    function startEdit() {
        if (!view.current) return;
        fLabel.text = String(view.current.label); fLogin.text = String(view.current.login); fPw.text = String(view.current.pw);
        view.reveal = false; view.mode = "edit";
    }
    function saveForm() {
        if (view.mode === "new") {
            view.sys.vaultAdd(fLabel.text.length ? fLabel.text : view.sys.tr("Новая запись"), fLogin.text, fPw.text);
            view.closeCard();
        } else if (view.mode === "edit" && view.current) {
            view.sys.vaultUpdate(String(view.current.id), fLabel.text, fLogin.text, fPw.text);
            view.mode = "card";
        }
    }
    function goBack() {
        if (view.mode === "edit") { view.mode = "card"; return true; }
        if (view.mode !== "") { view.closeCard(); return true; }
        view.sys.page = "main"; return true;
    }
    Keys.onEscapePressed: view.goBack()
    // FocusGrabber acts once: later moves (unlocked, a form opened, back to the list) are ours
    onModeChanged: Qt.callLater(function () {
        if (view.mode === "edit" || view.mode === "new") fLabel.focusIn();
        else if (view.mode === "") search.input.forceActiveFocus();
        else view.forceActiveFocus();
    })
    Connections {
        target: view.sys
        function onVaultUnlockedChanged() { if (view.sys.vaultUnlocked) Qt.callLater(function () { search.input.forceActiveFocus(); }); }
    }

    Column {
        id: col
        width: parent.width
        spacing: view.t.groupGap

        // ================================================================ locked
        Column {
            visible: !view.sys.vaultUnlocked
            width: parent.width
            spacing: view.t.s4
            Item { width: 1; height: view.t.s2 }
            PkIcon { sys: view.sys; anchors.horizontalCenter: parent.horizontalCenter; name: "lock"; filled: true
                     size: 44; color: view.t.fg }
            Column {
                width: parent.width; spacing: view.t.s1
                PkText { sys: view.sys; role: "title"; width: parent.width; horizontalAlignment: Text.AlignHCenter
                         text: view.sys.tr("Пароли") }
                PkText { sys: view.sys; role: "sub"; width: parent.width; horizontalAlignment: Text.AlignHCenter
                         text: "Proton Pass · " + view.sys.tr("Введите пароль пользователя") }
            }
            Row {
                width: parent.width; spacing: view.t.s2
                PkField {
                    id: pwField
                    sys: view.sys; width: parent.width - unlockBtn.width - parent.spacing
                    password: true; placeholder: view.sys.tr("Пароль")
                    enabled: !view.sys.vaultBusy
                    onAccepted: { view.sys.unlockVault(text); text = ""; }
                }
                PkButton {
                    id: unlockBtn
                    sys: view.sys; kind: "primary"; anchors.verticalCenter: parent.verticalCenter
                    text: view.sys.vaultBusy ? view.sys.tr("Проверка…") : "Unlock"
                    enabled: !view.sys.vaultBusy && pwField.text.length > 0
                    onClicked: { view.sys.unlockVault(pwField.text); pwField.text = ""; }
                }
            }
            Row {
                visible: view.sys.vaultError.length > 0
                width: parent.width; spacing: view.t.s2
                PkIcon { sys: view.sys; name: "warning-circle"; size: view.t.iXs; color: view.t.accentText }
                PkText { sys: view.sys; role: "label"; width: parent.width - 24; wrapMode: Text.WordWrap
                         color: view.t.accentText; text: view.sys.vaultError }
            }
            PkText { sys: view.sys; role: "caption"; width: parent.width; wrapMode: Text.WordWrap; color: view.t.faint
                     horizontalAlignment: Text.AlignHCenter
                     text: view.sys.tr("Хранилище шифруется этим же паролем и закрывается само через 15 минут простоя.") }
        }

        // ============================================================ the list
        Column {
            id: listPage
            visible: view.sys.vaultUnlocked && view.mode === ""
            width: parent.width
            spacing: view.t.s3

            PkHeader {
                id: listHead
                sys: view.sys; width: parent.width
                title: view.sys.tr("Пароли")
                sub: view.sys.vaultEntries.length + " " + view.sys.tr("записей") + " · Proton Pass"
                PkIconButton { sys: view.sys; icon: view.sys.browserScanning ? "spinner-gap" : "browsers"
                               enabled: !view.sys.browserScanning; onClicked: view.sys.browserScan()
                               RotationAnimator on rotation { running: view.sys.browserScanning; loops: Animation.Infinite
                                                              from: 0; to: 360; duration: 1400 } }
                PkIconButton { sys: view.sys; icon: "plus"; onClicked: view.startNew() }
                PkIconButton { sys: view.sys; icon: "lock"
                               onClicked: { view.sys.lockVault(); view.sys.page = "main"; } }
            }

            PkSearch {
                id: search
                sys: view.sys; width: parent.width
                placeholder: view.sys.tr("Поиск")
                onTextChanged: { view.query = text; view.sys.touchVault(); }
                onAccepted: if (view.shown.length === 1) view.openCard(view.shown[0].id)
            }

            // found in the browsers: nothing moves by itself, each one is added by hand (or all)
            PkSection {
                id: foundSec
                visible: view.sys.browserScanning || view.sys.browserScanned
                sys: view.sys; width: parent.width
                title: view.sys.browserScanning ? view.sys.tr("Ищем в браузерах…")
                     : view.sys.browserError.length ? view.sys.browserError
                     : view.sys.browserFound.length ? view.sys.tr("Найдено в браузерах") + " · " + view.sys.browserFound.length
                     : view.sys.tr("В браузерах ничего нового")
                ListView {
                    visible: view.sys.browserFound.length > 0
                    width: parent.width
                    height: Math.min(contentHeight, 3 * view.t.rowH2)
                    clip: true; interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    model: view.sys.browserFound
                    delegate: PkRow {
                        id: fr
                        required property var modelData
                        sys: view.sys; width: ListView.view.width
                        icon: "globe"
                        title: view.host(fr.modelData.url) || String(fr.modelData.url || "")
                        sub: String(fr.modelData.login || "") + "  ·  " + String(fr.modelData.browser || "")
                        PkIconButton { sys: view.sys; icon: "plus"; size: view.t.iSm; onClicked: view.sys.browserImport(fr.modelData) }
                    }
                }
                PkRow {
                    visible: view.sys.browserFound.length > 1
                    sys: view.sys; title: view.sys.tr("Добавить все")
                    PkButton { sys: view.sys; small: true; kind: "secondary"; text: "+ " + view.sys.browserFound.length
                               onClicked: view.sys.browserImportAll() }
                }
            }

            // the logins
            Rectangle {
                visible: view.shown.length > 0
                width: parent.width
                height: list.height + 12
                radius: view.t.rSurface
                color: view.t.surface
                ListView {
                    id: list
                    x: 6; y: 6; width: parent.width - 12
                    readonly property real room: view.maxH - listHead.height - search.height - 2 * listPage.spacing
                                                 - (foundSec.visible ? foundSec.height + listPage.spacing : 0) - 12 - 8
                    height: Math.max(view.t.rowH2, Math.min(contentHeight, room))
                    clip: true; interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    model: view.shown
                    ScrollBar.vertical: ScrollBar {
                        policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        contentItem: Rectangle { implicitWidth: 3; radius: 1.5; color: view.t.track }
                    }
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: list.width; height: view.t.rowH2 + 4
                        radius: view.t.rControl
                        color: rowMa.containsMouse ? view.t.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: view.t.dFast } }
                        MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: if (containsMouse) view.sys.touchVault()
                                    onClicked: view.openCard(row.modelData.id) }
                        // a monogram tile: the site's first letter (stands in for a favicon)
                        Rectangle {
                            id: mono
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34; radius: view.t.rSmall
                            color: view.t.selected
                            PkText { sys: view.sys; role: "emph"; anchors.centerIn: parent
                                     text: (String(row.modelData.label || view.host(row.modelData.url) || "?").trim().charAt(0) || "?").toUpperCase() }
                        }
                        Column {
                            x: mono.x + mono.width + 12; width: parent.width - x - copyBtn.width - 14
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            PkText { sys: view.sys; role: "emph"; width: parent.width; elide: Text.ElideRight
                                     text: String(row.modelData.label || view.host(row.modelData.url) || "—") }
                            PkText { sys: view.sys; role: "sub"; width: parent.width; elide: Text.ElideRight
                                     text: [String(row.modelData.login || ""), view.host(row.modelData.url)]
                                               .filter(function (s) { return s.length; }).join("  ·  ") }
                        }
                        PkIconButton {
                            id: copyBtn
                            property bool done: false
                            sys: view.sys; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            icon: done ? "check" : "copy"; size: view.t.iSm; selected: done
                            onClicked: { view.sys.vaultCopy(String(row.modelData.pw)); done = true; copyDone.restart(); }
                            Timer { id: copyDone; interval: 1200; onTriggered: copyBtn.done = false }
                        }
                    }
                }
            }

            Column {
                visible: view.shown.length === 0
                width: parent.width; spacing: view.t.s2
                Item { width: 1; height: view.t.s4 }
                PkIcon { sys: view.sys; anchors.horizontalCenter: parent.horizontalCenter
                         name: view.query.length ? "magnifying-glass" : "key"; size: 30; color: view.t.faint }
                PkText { sys: view.sys; role: "sub"; width: parent.width; horizontalAlignment: Text.AlignHCenter
                         text: view.query.length ? view.sys.tr("Ничего не найдено") : view.sys.tr("Пока ни одного пароля") }
            }
        }

        // ============================================================ a login's card
        Column {
            visible: view.sys.vaultUnlocked && view.mode === "card" && view.current !== null
            width: parent.width
            spacing: view.t.groupGap

            PkHeader {
                sys: view.sys; width: parent.width; back: true
                title: view.current ? String(view.current.label || view.host(view.current.url) || "—") : ""
                sub: view.current ? (view.host(view.current.url) || "Proton Pass") : ""
                onBackClicked: view.closeCard()
                PkIconButton { sys: view.sys; icon: "pencil-simple"; onClicked: view.startEdit() }
            }

            PkSection {
                sys: view.sys; width: parent.width
                PkRow {
                    sys: view.sys; icon: "user"; title: view.sys.tr("Логин")
                    sub: view.current && String(view.current.login).length ? String(view.current.login) : "—"
                    PkIconButton { id: cpUser; property bool done: false; sys: view.sys; size: view.t.iSm
                                   visible: !!view.current && String(view.current.login).length > 0
                                   icon: done ? "check" : "copy"; selected: done
                                   onClicked: { view.sys.vaultCopy(String(view.current.login)); done = true; cpUserT.restart(); }
                                   Timer { id: cpUserT; interval: 1200; onTriggered: cpUser.done = false } }
                }
                PkRow {
                    sys: view.sys; icon: "password"; title: view.sys.tr("Пароль")
                    sub: !view.current ? "" : view.reveal ? String(view.current.pw)
                                             : "•".repeat(Math.min(16, Math.max(8, String(view.current.pw).length)))
                    PkIconButton { sys: view.sys; size: view.t.iSm; icon: view.reveal ? "eye-slash" : "eye"
                                   onClicked: { view.reveal = !view.reveal; view.sys.touchVault(); } }
                    PkIconButton { id: cpPw; property bool done: false; sys: view.sys; size: view.t.iSm
                                   icon: done ? "check" : "copy"; selected: done
                                   onClicked: { view.sys.vaultCopy(String(view.current.pw)); done = true; cpPwT.restart(); }
                                   Timer { id: cpPwT; interval: 1200; onTriggered: cpPw.done = false } }
                }
                PkRow {
                    visible: !!view.current && String(view.current.url || "").length > 0
                    sys: view.sys; icon: "globe"; title: "Website"
                    sub: view.current ? String(view.current.url || "") : ""
                    PkIconButton { sys: view.sys; size: view.t.iSm; icon: "arrow-square-out"
                                   onClicked: {
                                       var u = String(view.current.url);
                                       Qt.openUrlExternally(/^[a-z]+:\/\//i.test(u) ? u : "https://" + u);
                                   } }
                }
                PkRow {
                    visible: !!view.current && String(view.current.at || "").length > 0
                    sys: view.sys; icon: "clock"; title: "Changed"
                    value: view.current ? String(view.current.at || "") : ""
                }
            }

            PkText { sys: view.sys; role: "caption"; width: parent.width; wrapMode: Text.WordWrap; color: view.t.faint
                     text: "Copied passwords are cleared from the clipboard after a minute." }

            PkSection {
                sys: view.sys; width: parent.width
                note: view.confirmRemove ? "Click again to remove. It stays in Proton Pass (delete it there)." : ""
                PkRow {
                    sys: view.sys; icon: "trash"; interactive: true; danger: view.confirmRemove
                    title: view.confirmRemove ? "Remove from the list?" : "Remove from the list"
                    onClicked: {
                        if (!view.confirmRemove) { view.confirmRemove = true; removeReset.restart(); return; }
                        view.sys.vaultRemove(String(view.current.id)); view.closeCard();
                    }
                    Timer { id: removeReset; interval: 4000; onTriggered: view.confirmRemove = false }
                }
            }
        }

        // ============================================================ edit / new
        Column {
            visible: view.sys.vaultUnlocked && (view.mode === "edit" || view.mode === "new")
            width: parent.width
            spacing: view.t.groupGap

            PkHeader {
                sys: view.sys; width: parent.width; back: true
                title: view.mode === "new" ? view.sys.tr("Новая запись") : "Edit"
                sub: view.mode === "new" ? "Saved to Proton Pass · Personal"
                                         : (view.current ? String(view.current.label || "") : "")
                onBackClicked: view.goBack()
            }

            Column {
                width: parent.width; spacing: view.t.s2
                PkText { sys: view.sys; role: "caption"; text: view.sys.tr("Название") }
                PkField { id: fLabel; sys: view.sys; width: parent.width; placeholder: view.sys.tr("Откуда пароль")
                          onAccepted: fLogin.focusIn(); onTextChanged: view.sys.touchVault() }
                Item { width: 1; height: view.t.s1 }
                PkText { sys: view.sys; role: "caption"; text: view.sys.tr("Логин") }
                PkField { id: fLogin; sys: view.sys; width: parent.width; placeholder: view.sys.tr("Логин (необязательно)")
                          onAccepted: fPw.focusIn(); onTextChanged: view.sys.touchVault() }
                Item { width: 1; height: view.t.s1 }
                PkText { sys: view.sys; role: "caption"; text: view.sys.tr("Пароль") }
                Row {
                    width: parent.width; spacing: view.t.s2
                    PkField { id: fPw; sys: view.sys; width: parent.width - eyeBtn.width - parent.spacing
                              password: !view.reveal; placeholder: view.sys.tr("Пароль")
                              onAccepted: view.saveForm(); onTextChanged: view.sys.touchVault() }
                    PkIconButton { id: eyeBtn; sys: view.sys; anchors.verticalCenter: parent.verticalCenter
                                   icon: view.reveal ? "eye-slash" : "eye"; onClicked: view.reveal = !view.reveal }
                }
            }

            Row {
                anchors.right: parent.right; spacing: view.t.s2
                PkButton { sys: view.sys; kind: "secondary"; text: view.sys.tr("Отмена"); onClicked: view.goBack() }
                PkButton { sys: view.sys; kind: "primary"; text: view.sys.tr("Сохранить")
                           enabled: fPw.text.length > 0 || view.mode === "edit"; onClicked: view.saveForm() }
            }
        }
    }
}
