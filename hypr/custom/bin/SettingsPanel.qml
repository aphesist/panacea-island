pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// written by portal-patch.py (panacea-config) - Settings, the frame, built from the Pk kit.
// Replaces Panacea's SettingsView frame (same props: sys, tab; same pages: Set*.qml, which the
// patcher also redraws with the kit). Left: search and the groups. Right: the page title, the
// group's pages as a segmented control, then the page.
Item {
    id: view
    property var sys
    readonly property var t: sys.pk
    property int tab: 0

    implicitWidth: 980
    implicitHeight: 620

    readonly property var sections: [
        { id: "bar",     title: view.sys.tr("Панель и остров"), page: "SetBarIsland.qml",
          sub: view.sys.tr("Как остров стоит на кромке и во что он разворачивается."),
          keys: "notch island pill bar height width cpu gpu load temperature home tabs" },
        { id: "media",   title: view.sys.tr("Медиа"), page: "SetMedia.qml",
          sub: view.sys.tr("Плеер, обложки и то, что видно в свёрнутом острове."),
          keys: "player music cover sound" },
        { id: "clock",   title: view.sys.tr("Часы и дата"), page: "SetClock.qml",
          sub: view.sys.tr("Формат времени, часовой пояс и подпись под ним."),
          keys: "clock time date timezone region" },
        { id: "look",    title: view.sys.tr("Оформление"), page: "SetAppearance.qml",
          sub: view.sys.tr("Виджеты, шрифты и оформление системы."),
          keys: "theme font size sounds audio haptics widgets colour color language" },
        { id: "weather", title: view.sys.tr("Погода"), page: "SetWeather.qml",
          sub: view.sys.tr("Ключ, город и шкала для виджета погоды."),
          keys: "weather temperature city openweather api key celsius fahrenheit" },
        { id: "motion",  title: view.sys.tr("Анимация"), page: "SetMotion.qml",
          sub: view.sys.tr("Насколько быстро оболочка движется — и движется ли вообще."),
          keys: "animation speed bounce mascot character eyes cursor motion" },
        { id: "launch",  title: view.sys.tr("Лаунчер"), page: "SetLauncher.qml",
          sub: view.sys.tr("Поиск приложений и то, что он ищет кроме них."),
          keys: "launcher launchpad grid folders apps search" },
        { id: "notif",   title: view.sys.tr("Уведомления"), page: "SetNotifications.qml",
          sub: view.sys.tr("Сколько карточек висит на экране и как долго."),
          keys: "notifications dnd toast focus bell" },
        { id: "cc",      title: view.sys.tr("Быстрые настройки"), page: "SetControlCenter.qml",
          sub: view.sys.tr("Раскладка быстрых настроек — плитки переставляются мышью."),
          keys: "quick settings tiles layout wifi bluetooth" },
        { id: "lock",    title: view.sys.tr("Экран блокировки"), page: "SetLock.qml",
          sub: view.sys.tr("Экран блокировки: что на нём видно и когда он появляется."),
          keys: "lock screen blur idle fingerprint" },
        { id: "display", title: view.sys.tr("Экран"), page: "SetDisplay.qml",
          sub: view.sys.tr("Разрешение, частота и масштаб подключённых экранов."),
          keys: "display monitor resolution refresh scale layout placement night light temperature schedule" },
        { id: "input",   title: view.sys.tr("Ввод"), page: "SetInput.qml",
          sub: view.sys.tr("Скорость указателя и разгон."),
          keys: "mouse keyboard layouts xkb pointer cursor sensitivity speed accel acceleration raw input touchpad" },
        { id: "claude",  title: "Claude", page: "SetClaude.qml",
          sub: "The island chat's tools: your browser, and asking about anything on screen.",
          keys: "claude ai chat browser zen firefox claudezilla ask selection screenshot region explain shortcut" },
        { id: "vpn",     title: "VPN", page: "SetVpn.qml",
          sub: view.sys.tr("Клиент и профиль для быстрого подключения."),
          keys: "vpn mullvad proxy network client" },
        { id: "startup", title: "Startup apps", page: "StartupView.qml", embed: true,
          sub: "Apps that open when you log in, and the services that start with your session.",
          keys: "startup autostart login boot session apps services open at login" },
        { id: "system",  title: view.sys.tr("Система"), page: "SetSystem.qml",
          sub: view.sys.tr("Из чего собрана машина и чем она сейчас занята."),
          keys: "about system cpu ram temperature processes version update" }
    ]

    readonly property var groups: [
        { id: "island",     title: view.sys.tr("Остров"),       icon: "pill",               pages: ["bar", "media", "clock"] },
        { id: "appearance", title: view.sys.tr("Оформление"),   icon: "palette",            pages: ["look", "weather", "motion"] },
        { id: "controls",   title: view.sys.tr("Управление"),   icon: "sliders-horizontal", pages: ["cc", "launch", "notif"] },
        { id: "devices",    title: view.sys.tr("Устройства"),   icon: "monitor",            pages: ["display", "input"] },
        { id: "startup",    title: "Startup",                   icon: "rocket-launch",      pages: ["startup"] },
        { id: "claude",     title: "Claude",                    icon: "sparkle",            pages: ["claude"] },
        { id: "vpn",        title: "VPN",                       icon: "shield-check",       pages: ["vpn"] },
        { id: "security",   title: view.sys.tr("Безопасность"), icon: "lock-simple",        pages: ["lock"] },
        { id: "system",     title: view.sys.tr("Система"),      icon: "cpu",                pages: ["system"] }
    ]

    function indexOf(id) { for (var i = 0; i < sections.length; i++) if (sections[i].id === id) return i; return -1; }
    function groupForPage(pageId) {
        for (var i = 0; i < groups.length; i++) if (groups[i].pages.indexOf(pageId) >= 0) return groups[i];
        return groups[0];
    }
    function pagesForGroup(group) { return group.pages.map(id => indexOf(id)).filter(i => i >= 0); }
    property string query: ""
    function matches(s) {
        if (!view.query.length) return true;
        var q = view.query.toLowerCase();
        return s.title.toLowerCase().indexOf(q) >= 0 || s.keys.toLowerCase().indexOf(q) >= 0 || s.sub.toLowerCase().indexOf(q) >= 0;
    }
    function groupMatches(g) {
        if (!view.query.length || g.title.toLowerCase().indexOf(view.query.toLowerCase()) >= 0) return true;
        return pagesForGroup(g).some(i => view.matches(sections[i]));
    }
    function goGroup(g) {
        var pages = pagesForGroup(g);
        for (var i = 0; i < pages.length; i++) if (view.matches(sections[pages[i]])) { view.tab = pages[i]; return; }
        if (pages.length) view.tab = pages[0];
    }
    function goToSection(id) {
        if (!id) return;
        var i = indexOf(id);
        if (i >= 0) view.tab = i;
        view.sys.settingsSection = "";
    }

    readonly property var section: sections[Math.max(0, Math.min(sections.length - 1, tab))]
    readonly property var activeGroup: groupForPage(section.id)
    readonly property var groupPages: pagesForGroup(activeGroup)

    Component.onCompleted: view.goToSection(view.sys.settingsSection)
    Connections {
        target: view.sys
        function onSettingsSectionChanged() { view.goToSection(view.sys.settingsSection); }
    }
    onTabChanged: { scroll.contentY = 0; pageLoader.reload(); }

    RowLayout {
        anchors.fill: parent
        spacing: 24

        // ---- the groups
        ColumnLayout {
            Layout.preferredWidth: 220
            Layout.maximumWidth: 220
            Layout.fillHeight: true
            spacing: 12

            PkSearch {
                id: search
                sys: view.sys
                Layout.fillWidth: true
                placeholder: "Search settings"
                onTextChanged: view.query = text
                onAccepted: { for (var i = 0; i < view.sections.length; i++) if (view.matches(view.sections[i])) { view.tab = i; break; } }
            }

            ListView {
                id: nav
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: view.groups
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: item
                    required property var modelData
                    readonly property bool active: view.activeGroup.id === modelData.id
                    readonly property bool shown: view.groupMatches(modelData)
                    width: nav.width
                    height: shown ? 40 : 0
                    visible: shown
                    radius: height / 2
                    color: active ? view.t.selected : itemMa.containsMouse ? view.t.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: view.t.dFast } }
                    PkIcon {
                        sys: view.sys; x: 14; anchors.verticalCenter: parent.verticalCenter
                        name: item.modelData.icon; size: view.t.iSm; filled: item.active
                        color: item.active ? view.t.fg : view.t.muted
                    }
                    Text {
                        x: 44; width: parent.width - x - 12; anchors.verticalCenter: parent.verticalCenter
                        text: item.modelData.title; elide: Text.ElideRight
                        color: item.active ? view.t.fg : itemMa.containsMouse ? view.t.soft : view.t.muted
                        font { family: view.t.font; pixelSize: view.t.tBody; weight: item.active ? Font.DemiBold : Font.Normal }
                    }
                    MouseArea { id: itemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: view.goGroup(item.modelData) }
                }
            }
        }

        // ---- the page
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 12
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: view.section.title; color: view.t.fg; elide: Text.ElideRight
                    font { family: view.t.font; pixelSize: view.t.tTitle + 4; weight: Font.Bold }
                }
                Text {
                    Layout.fillWidth: true
                    text: view.section.sub; color: view.t.muted; wrapMode: Text.WordWrap
                    font { family: view.t.font; pixelSize: view.t.tLabel }
                }
            }

            PkSegmented {
                sys: view.sys
                visible: view.groupPages.length > 1
                options: view.groupPages.map(i => ({ id: String(i), text: view.sections[i].title }))
                value: String(view.tab)
                onPicked: id => view.tab = Number(id)
            }

            Flickable {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: pageCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 3000
                ScrollBar.vertical: SetScroll { sys: view.sys }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        var d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        scroll.contentY = Math.max(0, Math.min(Math.max(0, scroll.contentHeight - scroll.height), scroll.contentY - d));
                    }
                }
                ColumnLayout {
                    id: pageCol
                    width: scroll.width - 14
                    spacing: 12
                    Loader {
                        id: pageLoader
                        Layout.fillWidth: true
                        function reload() {
                            if (view.section.embed) setSource(view.section.page, { sys: view.sys, embedded: true });
                            else setSource(view.section.page, { sys: view.sys });
                        }
                        Component.onCompleted: reload()
                    }
                    Item { Layout.preferredHeight: 12 }
                }
            }
        }
    }
}
