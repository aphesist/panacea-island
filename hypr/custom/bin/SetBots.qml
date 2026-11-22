import QtQuick
import QtQuick.Layouts
import Quickshell

// written by portal-patch.py (panacea-island): Settings > Bots. The island's Bots tab, the
// collapsed pill and the cards (BotsPage.qml, BotsIsland.qml), fed by BotsLink.qml, which runs
// scripts/custom/boopis-bridge.mjs. Everything lives in settings.json and applies at once.
ColumnLayout {
    id: page
    property var sys
    readonly property var bl: page.sys.bots
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
            label: "Bots on the island"
            sub: "Your boopis bots: talk to one, answer what they ask, watch the team room."
            on: page.sys.cfg.botsEnabled
            onToggled: value => page.set("botsEnabled", value)
        }
        Note {
            visible: page.sys.cfg.botsEnabled
            text: page.bl.up ? "Connected to boopis: " + page.bl.bots.length + (page.bl.bots.length === 1 ? " bot" : " bots")
                               + (page.bl.rooms.length ? ", " + page.bl.rooms.length + (page.bl.rooms.length === 1 ? " team room." : " team rooms.") : ".")
                : page.bl.why === "nohome" ? "boopis isn't set up on this computer yet."
                : page.bl.why === "error" ? "boopis answered, but the island couldn't read it. It retries on its own."
                : "boopis isn't running. The island finds it as soon as it opens."
        }
        Note {
            visible: page.sys.cfg.botsEnabled && page.sys.orbs.missing
            text: "The bot faces aren't installed (~/.local/share/panacea-island/orbs). Run panacea-island's install.sh again."
        }
        SetButton {
            sys: page.sys
            visible: page.sys.cfg.botsEnabled && !page.bl.up
            text: "Open boopis"
            onClicked: Quickshell.execDetached(["gtk-launch", "boopis"])
        }
    }

    // ------------------------------------------------------------- the tab and the pill
    SetCard {
        sys: page.sys
        visible: page.sys.cfg.botsEnabled
        SetSelect {
            sys: page.sys
            label: "Bots tab"
            value: page.sys.cfg.botsTab || "open"
            options: [{ id: "open", text: "While boopis runs" }, { id: "always", text: "Always" }, { id: "off", text: "Never" }]
            onPicked: id => page.set("botsTab", id)
        }
        SetSelect {
            sys: page.sys
            label: "Collapsed island"
            value: page.sys.cfg.botsPill || "busy"
            options: [{ id: "busy", text: "While a bot works" }, { id: "needs", text: "Only when one needs you" }, { id: "off", text: "Never" }]
            onPicked: id => page.set("botsPill", id)
        }
        Note {
            text: "The collapsed island shows the bot that matters most, and the busy ones as small orbs. Keys for any shortcut: qs -p ~/.config/panacea ipc call pill bots (also botsNext, botsPrev, botsSay <text>, botsApprove once|session|deny)."
        }
    }

    // ------------------------------------------------------------- cards
    SetCard {
        sys: page.sys
        visible: page.sys.cfg.botsEnabled
        SetToggle {
            sys: page.sys
            label: "Reply cards"
            sub: "When a bot finishes a reply, the island grows and holds it for a moment. Reply works in place."
            on: page.sys.cfg.botsCards
            onToggled: value => page.set("botsCards", value)
        }
        SetToggle {
            sys: page.sys
            label: "Approvals on the island"
            sub: "When a bot asks before it acts, answer from the island: Allow once, This session or Deny."
            on: page.sys.cfg.botsApprovals
            onToggled: value => page.set("botsApprovals", value)
        }
    }

    // ------------------------------------------------------------- what needs boopis
    SetCard {
        sys: page.sys
        visible: page.sys.cfg.botsEnabled
        SetLabel { sys: page.sys; text: "What works today" }
        Note {
            text: "Live: the roster with each bot's look and model, the team rooms and their thread, writing to a room. "
                + "Chats you start here: a bot's replies, its tool steps, and its approvals, with their state on the orb and the pill."
        }
        SetLabel { sys: page.sys; text: "Waits on boopis" }
        Note {
            text: "What a bot does in the boopis window, in a cron run or in a room turn doesn't reach the island yet (needs a presence feed from boopis), "
                + "and approvals asked there can't be answered here (needs an approvals inbox). Chats started here don't show in boopis's own list either. "
                + "These are asked of boopis (ASKS in the island's plan); the island picks them up when they land."
        }
    }
}
