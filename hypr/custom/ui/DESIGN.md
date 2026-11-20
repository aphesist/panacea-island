# Panacea design system

The island's look in one place. Tokens live in `PkTheme.qml`; the shell holds one instance as
`sys.pk` (wired by portal-patch.py, which copies every `Pk*` file next to shell.qml). Every page
builds from the `Pk*` components in this folder. If a page needs something the kit doesn't have,
add it to the kit; don't hand-roll it in the page.

The feel: Nothing OS and Apple, not Android. Black, quiet, typographic, a few big confident
shapes; no chrome, no outlines, no icons in circles.

## Principles

- No strokes, no divider lines. Surfaces are told apart by tone and space only.
- Concentric corners. Every radius comes from the island's (`rIsland`, 26): a card inside the
  island is `rSurface` (20), a row or field inside a card `rControl` (14), small insets `rSmall` (10).
  Pills (buttons, chips, switches, search) are `height / 2`.
- On is white. A tile, switch or primary button that is on/active turns solid `on` (#f4f4f4)
  with black ink; off is a grey veil (`surface`) with white ink. Never show state by colour alone.
- Icons are Phosphor, big and bare: Bold when off or idle, Fill when on or selected. No circle,
  square or badge behind an icon unless the shape means something (album art, an app icon).
- One red. `accent` (#d71921) only as a dot (unread, recording, live), for errors and for the
  destructive button. `accentText` (#ff7a7f) is the red for text on black (commands, code).
- Numbers that matter are dot-matrix (`DotText`): the clock, battery, counters.
- Type is JetBrains Mono; hierarchy comes from weight and colour (fg / soft / muted / faint),
  not from big size jumps.
- Panacea's own island tabs (house glyph "Home", the Claude logo, the Zen logo) stay exactly as
  they are; the top-right of every tab page is the settings gear.

## Tokens (`sys.pk`)

- Radii: `rIsland` 26, `rSurface` 20, `rControl` 14, `rSmall` 10, `concentric(outer, inset)`.
- Colour: `fg`, `soft` .7, `muted` .45, `faint` .28 (text); `on` / `onInk` / `onSub` (white state);
  `surface` .075 (a card), `surfaceLow` .045 (big work areas), `hover` .06, `selected` .12,
  `pressed` .16, `track` .16 (empty slider/switch), `dotOff` .14, `raised` #1d1d1d (menus, find
  bars floating over a card), `scrim` (code and logs sunk into a card), `accent`, `accentText`.
- Spacing: `s1`..`s5` = 4 / 8 / 12 / 16 / 20; `pad` 15 (page inset = the island's), `gap` 8
  (between cards), `groupGap` 16 (between groups); rows `rowH` 44, `rowH2` 52 (with subtitle).
- Type: `tCaption` 11, `tLabel` 12, `tBody` 13, `tEmph` 14, `tTitle` 20, `tDisplay` 42.
- Icons: `iXs` 14, `iSm` 17, `iMd` 20, `iLg` 24, `iXl` 30; fonts `iconBold`, `iconFill`.
- Motion: `dFast` 120 (hover, press, colour), `dBase` 200 (state), `dSlow` 320; shapes use
  `PkMorph` with `sys.animMs` (below). All of it follows Reduce motion (`still`).

## Morphing

Anything that changes shape (the island, a panel, a card growing out of a row, a pill) follows
three rules, so its corners match its edges on every frame and it never moves in steps.

1. One spring for the whole shape. Width, height, x/y and every corner radius are bound to a
   `PkMorph` each, all with the same `ms` and `bounce` (the Motion tab: `sys.animMs`,
   `sys.animBounce`, `still: sys.noMotion`). Never mix curves or durations on one shape.
2. No `Behavior` on geometry. A `NumberAnimation` restarts from zero speed when its target
   changes mid-flight (it stalls, then jumps); Qt's `SpringAnimation` ticks every 16 ms, so on
   this 120 Hz screen it moves every other frame (a stutter). `PkMorph` integrates on every
   frame and keeps its speed when the target changes.
3. Content follows the animated shape, never its target. Either lay children out on the shape's
   current size, or, if they keep a fixed (final) width, fade them by the room the shape already
   has: `room = clamp((shape.width - content.width - 4) / 24)`, `opacity: room * room`. Parts
   that exist in one state only (a strip of tabs on hover) do the same with the height. A radius
   that depends on the size is derived (`Math.min(r, height / 2)`), never animated on its own.

```qml
Rectangle {
    id: card
    PkMorph { id: mw; to: open ? 330 : 190; ms: sys.animMs; bounce: sys.animBounce; still: sys.noMotion }
    PkMorph { id: mh; to: open ? 72 : 38;   ms: sys.animMs; bounce: sys.animBounce; still: sys.noMotion }
    PkMorph { id: mr; to: open ? 26 : 19;   ms: sys.animMs; bounce: sys.animBounce; still: sys.noMotion }
    width: mw.value; height: mh.value; radius: mr.value
    clip: true
    Row { id: extra; anchors.horizontalCenter: parent.horizontalCenter
          readonly property real room: Math.max(0, Math.min(1, (card.height - 38) / 34))
                                     * Math.max(0, Math.min(1, (card.width - implicitWidth - 4) / 24))
          opacity: room * room }
}
```

Colour and opacity changes (hover, press, selection) are not morphs: they stay short tweens (`dFast`).

## Components

- `PkText`: text in a role: `body`, `emph`, `label`, `caption`, `sub`, `title`, `soft`.
- `PkIcon`: a Phosphor icon by name (`"wifi-high"`, names from phosphoricons.com); `filled`, `size`.
- `PkCard`: a surface (`rSurface`, `surface`). `interactive` gives hover/press and `clicked()`.
- `PkTile`: a control tile: icon top-left, title and state bottom-left; white when `on`.
  `toggled()` on click, `opened()` on right-click or press-and-hold (its page).
- `PkVSlider`: a tall pill slider (volume, brightness): white fill from the bottom, icon inside;
  `moved(v)`, `iconClicked()` (mute).
- `PkSlider`: a thin horizontal slider with a white knob; `moved(v)`.
- `PkToggle`: a switch; white track when on. `toggled(on)`.
- `PkButton`: `kind` primary (white; one per screen), secondary (veil), ghost (text), danger (red,
  only to confirm something destructive). `text`, `icon` or `image`, `small`.
- `PkIconButton`: a bare icon with a round veil on hover; `selected` fills it; `dot` adds the red dot.
- `PkSegmented`: one sliding white-veil pill; `options: [{ id, text }]`, `value`, `picked(id)`.
- `PkChip`: a filter pill; `selected`.
- `PkSearch`: a search pill with clear; `text`, `placeholder`, `accepted()`.
- `PkHeader`: back chevron, title (+ `dirty` dot), subtitle, actions on the right (children).
- `PkSection`: caption, a card holding rows (children), an optional note under it.
- `PkRow`: icon (optional), title, sub, `value`, `caret`, trailing children; `hot` (selected),
  `danger`, `dim`; `clicked()`.
- `PkDotBar`: a row of dots for a level (battery, earbuds); `low` turns the lit dots red.
- `PkMorph`: the shape spring (see Morphing).
- `PkNotifCard`: every notification card: app tile, "App · time" (red dot when urgent), title,
  up to `lines` of body; `clicked()`, `closed()` (x on hover). The island's toast copies its order.

Settings: `SettingsPanel.qml` is the frame (search, groups, segmented sub-pages). The pages keep
Panacea's `Set*` building blocks, which `ui/settings/Set*.qml` redraw with the kit (same API; the
originals stay as `.pristine`). New settings pages use those blocks, or Pk components directly.

## Building a page

```qml
Item {
    id: page
    property var sys
    readonly property var t: sys.pk
    implicitHeight: col.implicitHeight
    Column {
        id: col
        width: parent.width; spacing: page.t.groupGap
        PkHeader { sys: page.sys; width: parent.width; title: "Logs"; back: true; onBackClicked: page.sys.page = "main" }
        PkSearch { sys: page.sys; width: parent.width }
        PkSection { sys: page.sys; width: parent.width; title: "Today"
            PkRow { sys: page.sys; width: parent.width; icon: "warning"; title: "..."; caret: true }
        }
    }
}
```

Lists that change live are ListModels updated row by row; nothing rebuilds on a poll.
Kit files never declare inline `component`s: Quickshell then fails with "X is not a type" in
the files that use them. A helper is its own `Pk*.qml` file.
A page never sets its own fonts, colours or radii: it takes them from `sys.pk`.
