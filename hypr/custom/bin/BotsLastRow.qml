import QtQuick

// written by portal-patch.py (panacea-island) - the Bots stage's idle row: clock, the bot's last
// activity (elides), and when (always shows), centred.
Item {
    id: lr
    property var sys
    readonly property var t: sys.pk
    property string words: ""
    property string when: ""
    TextMetrics { id: lm; font: lt.font; text: lr.words }
    readonly property real ww: Math.min(lm.advanceWidth + 1, width - 21 - wt.implicitWidth)
    readonly property real tw: ww + wt.implicitWidth
    PkIcon { sys: lr.sys; name: "clock"; size: 14; color: lr.t.muted; anchors.verticalCenter: parent.verticalCenter
             x: Math.round((lr.width - lr.tw - 21) / 2) }
    Text { id: lt; anchors.verticalCenter: parent.verticalCenter; x: Math.round((lr.width - lr.tw - 21) / 2) + 21
           width: lr.ww; elide: Text.ElideRight; text: lr.words
           color: lr.t.fg; opacity: 0.8; font { family: lr.t.font; pixelSize: 12 } }
    Text { id: wt; anchors.verticalCenter: parent.verticalCenter; anchors.left: lt.right
           text: lr.when; color: lr.t.muted; font: lt.font }
}
