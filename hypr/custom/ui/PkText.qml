import QtQuick

// Panacea kit - text in one of the kit's roles: "body", "emph", "label", "caption", "sub", "title", "soft".
Text {
    property var sys
    readonly property var t: sys.pk
    property string role: "body"
    color: role === "sub" || role === "caption" ? t.muted : role === "soft" ? t.soft : t.fg
    elide: Text.ElideRight
    textFormat: Text.PlainText
    font.family: t.font
    font.pixelSize: ({ body: t.tBody, emph: t.tEmph, label: t.tLabel, caption: t.tCaption, sub: t.tCaption, title: t.tTitle, soft: t.tBody })[role] || t.tBody
    font.weight: role === "title" ? Font.Bold : (role === "emph" || role === "label" || role === "caption") ? Font.DemiBold : Font.Normal
}
