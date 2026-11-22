import QtQuick
import QtQuick.Layouts
import Quickshell

// written by portal-patch.py (panacea-island): Settings > Discord. The island's Discord tab and
// the corner overlay (DiscordView.qml, DiscordOverlay.qml), both fed by DiscordVoice.qml.
// Everything lives in settings.json and applies at once.
ColumnLayout {
    id: page
    property var sys
    readonly property var dc: page.sys.discord
    spacing: 12

    component Note: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: page.sys.colMuted
        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 2 }
    }
    function set(key, v) { page.sys.cfg[key] = v; page.sys.saveCfg(); }

    // ------------------------------------------------------------- on / off, the link
    SetCard {
        sys: page.sys
        SetToggle {
            sys: page.sys
            label: "Discord on the island"
            sub: "Mute, deafen and everyone's volume from the island while you're in a call (Vesktop)."
            on: page.sys.cfg.discordEnabled
            onToggled: value => page.set("discordEnabled", value)
        }
        Note {
            visible: page.sys.cfg.discordEnabled
            text: page.dc.inCall ? "Connected: in " + page.dc.channel + (page.dc.guild ? " (" + page.dc.guild + ")" : "") + "."
                : page.dc.up ? "Connected. Not in a call right now."
                : page.dc.why === "restart" ? "Discord was started before the island could reach it. Restart it once (this leaves any call)."
                : page.dc.why === "noflag" ? "Island controls need one line in ~/.config/vesktop-flags.conf: --remote-debugging-port=9223 (a local-only DevTools port). Then restart Discord."
                : "Discord isn't running. The island finds it as soon as it opens."
        }
        SetButton {
            sys: page.sys
            visible: page.sys.cfg.discordEnabled && page.dc.why === "restart"
            text: "Restart Discord"
            onClicked: Quickshell.execDetached(["sh", "-c", "pkill -x vesktop; sleep 2; gtk-launch vesktop"])
        }
    }

    // ------------------------------------------------------------- the tab
    SetCard {
        sys: page.sys
        visible: page.sys.cfg.discordEnabled
        SetSelect {
            sys: page.sys
            label: "Discord tab"
            value: page.sys.cfg.discordTab || "call"
            options: [{ id: "call", text: "In a call" }, { id: "open", text: "While open" }, { id: "off", text: "Never" }]
            onPicked: id => page.set("discordTab", id)
        }
        Note {
            text: "A tab beside Home, Claude and Zen. Keys for any shortcut: qs -p ~/.config/panacea ipc call pill discordMute (also discordDeafen, discordLeave, discord)."
        }
    }

    // ------------------------------------------------------------- the overlay
    SetCard {
        sys: page.sys
        visible: page.sys.cfg.discordEnabled
        SetToggle {
            sys: page.sys
            label: "Voice overlay"
            sub: "Everyone in the call in the screen's top-right corner, with a ring while they talk. Clicks pass through it."
            on: page.sys.cfg.discordOverlay
            onToggled: value => page.set("discordOverlay", value)
        }
        SetSelect {
            sys: page.sys
            visible: page.sys.cfg.discordOverlay
            label: "Layout"
            value: page.sys.cfg.discordOverlayLayout || "row"
            options: [{ id: "row", text: "Pictures in a row" }, { id: "list", text: "List with names" }]
            onPicked: id => page.set("discordOverlayLayout", id)
        }
        SetSelect {
            sys: page.sys
            visible: page.sys.cfg.discordOverlay
            label: "Who"
            value: page.sys.cfg.discordOverlayMode || "all"
            options: [{ id: "all", text: "Everyone" }, { id: "speaking", text: "Who's talking" }]
            onPicked: id => page.set("discordOverlayMode", id)
        }
        SetSlider {
            sys: page.sys
            visible: page.sys.cfg.discordOverlay
            label: "Picture size"
            from: 20; to: 56; step: 2; suffix: "px"
            value: page.sys.cfg.discordOverlaySize
            onMoved: value => page.set("discordOverlaySize", Math.round(value))
        }
        SetSelect {
            sys: page.sys
            label: "Talking ring"
            value: page.sys.cfg.discordRing || "green"
            options: [{ id: "green", text: "Discord green" }, { id: "white", text: "White" }]
            onPicked: id => page.set("discordRing", id)
        }
        SetToggle {
            sys: page.sys
            visible: page.sys.cfg.discordOverlay
            label: "Show yourself"
            sub: "Your own picture in the overlay too."
            on: page.sys.cfg.discordOverlaySelf
            onToggled: value => page.set("discordOverlaySelf", value)
        }
        SetToggle {
            sys: page.sys
            visible: page.sys.cfg.discordOverlay
            label: "Dim who's quiet"
            sub: "Pictures fade back while someone isn't talking (easier on the OLED)."
            on: page.sys.cfg.discordOverlayDim
            onToggled: value => page.set("discordOverlayDim", value)
        }
        SetToggle {
            sys: page.sys
            visible: page.sys.cfg.discordOverlay
            label: "Over fullscreen apps"
            sub: "Keep the overlay on top of games and fullscreen video."
            on: page.sys.cfg.discordOverlayFull
            onToggled: value => page.set("discordOverlayFull", value)
        }
    }
}
