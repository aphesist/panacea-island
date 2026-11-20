import QtQuick
import QtCore

// Panacea kit (panacea-config: hypr/custom/ui) - the design tokens. The shell holds one
// instance as `sys.pk`; every Pk component and every page reads from it. See DESIGN.md.
QtObject {
    id: t
    property var sys

    // ---- radii: concentric with the island's corner
    readonly property real rIsland: sys && sys.cfg.islandRadius > 0 ? sys.cfg.islandRadius : 26
    readonly property real rSurface: Math.max(14, rIsland - 6)      // cards, tiles, groups (20)
    readonly property real rControl: Math.max(8, rSurface - 6)      // rows and fields inside a card (14)
    readonly property real rSmall: Math.max(6, rControl - 4)        // art, code boxes, small insets (10)
    function concentric(outer, inset) { return Math.max(6, outer - inset); }

    // ---- colour: black, white, greys, one red
    readonly property color fg: "#ffffff"
    readonly property color bg: "#000000"
    readonly property color on: "#f4f4f4"                  // a tile that's on, the main action, a switch that's on
    readonly property color onInk: "#0a0a0a"               // what sits on `on`
    readonly property color onSub: Qt.rgba(0, 0, 0, 0.5)
    readonly property color muted: Qt.rgba(1, 1, 1, 0.45)  // subtitles, captions, quiet icons
    readonly property color soft: Qt.rgba(1, 1, 1, 0.7)    // secondary text that still reads
    readonly property color faint: Qt.rgba(1, 1, 1, 0.28)  // placeholders, disabled
    readonly property color track: Qt.rgba(1, 1, 1, 0.16)  // empty part of sliders, switches, bars
    readonly property color dotOff: Qt.rgba(1, 1, 1, 0.14)
    readonly property color accent: "#d71921"              // the one red: dots, recording, errors, destructive
    readonly property color accentText: "#ff7a7f"          // red that reads as text on black
    function veil(a) { return Qt.rgba(1, 1, 1, a); }
    readonly property color surface: veil(0.075)           // a card
    readonly property color surfaceLow: veil(0.045)        // a large work area (editor)
    readonly property color hover: veil(0.06)              // a row or bare control under the pointer
    readonly property color selected: veil(0.12)           // the selected tab / nav item / segment
    readonly property color pressed: veil(0.16)
    readonly property color raised: "#1d1d1d"              // something floating over a card (find bar, menu)
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.55)  // code and log text sunk into a card

    // ---- spacing and layout
    readonly property int s1: 4
    readonly property int s2: 8
    readonly property int s3: 12
    readonly property int s4: 16
    readonly property int s5: 20
    readonly property int pad: 15              // the island's inset for pages
    readonly property int gap: 8               // between cards in a grid
    readonly property int groupGap: 16         // between groups
    readonly property int rowH: 44
    readonly property int rowH2: 52            // a row with a subtitle

    // ---- type: the theme's font; weight carries hierarchy, not size jumps
    readonly property string font: sys ? sys.fontFam : "JetBrainsMono Nerd Font"
    readonly property int tCaption: 11
    readonly property int tLabel: 12
    readonly property int tBody: 13
    readonly property int tEmph: 14
    readonly property int tTitle: 20
    readonly property int tDisplay: 42

    // ---- icons: Phosphor (Bold when off, Fill when on); names from phosphoricons.com
    // loaded from the files, not looked up by name: a shell started before the fonts were
    // installed never sees them in its font list (Qt reads it once, at start)
    readonly property string fontDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/fonts/phosphor/"
    readonly property FontLoader boldFont: FontLoader { source: t.fontDir + "Phosphor-Bold.ttf" }
    readonly property FontLoader fillFont: FontLoader { source: t.fontDir + "Phosphor-Fill.ttf" }
    readonly property string iconBold: boldFont.status === FontLoader.Ready ? boldFont.name : "Phosphor-Bold"
    readonly property string iconFill: fillFont.status === FontLoader.Ready ? fillFont.name : "Phosphor-Fill"
    readonly property int iXs: 14
    readonly property int iSm: 17
    readonly property int iMd: 20
    readonly property int iLg: 24
    readonly property int iXl: 30

    // ---- motion (follows Reduce motion)
    readonly property bool still: sys ? !!sys.noMotion : false
    readonly property int dFast: still ? 0 : 120
    readonly property int dBase: still ? 0 : 200
    readonly property int dSlow: still ? 0 : 320
}
