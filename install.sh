#!/usr/bin/env bash
# Install panacea-island on top of Panacea. Run as YOUR USER:
#     bash install.sh
# Everything lands in folders Panacea keeps across updates (hypr/custom, panacea/scripts/custom).
# The Panacea files that change (shell.qml, FilesView.qml, the settings) are patched in place by
# hypr/custom/bin/portal-patch.py, which keeps .pristine copies and re-runs itself (a systemd path
# unit) whenever a Panacea update replaces one of them.
# Files that already exist are backed up to ~/.local/state/panacea-island/backup-<time>/.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "run as your user, not root"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
BK="$HOME/.local/state/panacea-island/backup-$(date +%Y%m%d-%H%M%S)"
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
[ -d "$CFG/panacea" ] || { echo "Panacea not found in $CFG/panacea - install Panacea first"; exit 1; }

put() {   # put <repo path> <destination>
    local src="$HERE/$1" dst="$2"
    if [ -e "$dst" ] && ! cmp -s "$src" "$dst"; then
        mkdir -p "$BK/$(dirname "${dst#$HOME/}")"; cp -a "$dst" "$BK/${dst#$HOME/}"
    fi
    install -Dm"$( [ -x "$src" ] && echo 755 || echo 644 )" "$src" "$dst"
}

say "Island views, the Pk design kit and the patcher (hypr/custom)"
while IFS= read -r f; do put "${f#$HERE/}" "$CFG/${f#$HERE/}"; done < <(find "$HERE/hypr/custom/bin" "$HERE/hypr/custom/ui" -type f)
[ -e "$CFG/hypr/custom/startup-apps.json" ] || put hypr/custom/startup-apps.json "$CFG/hypr/custom/startup-apps.json"   # your list, never overwritten

say "Icon fonts (Phosphor, MIT)"
for f in "$HERE"/fonts/phosphor/*; do put "${f#$HERE/}" "$DATA/fonts/phosphor/$(basename "$f")"; done
fc-cache -f "$DATA/fonts" >/dev/null 2>&1 || true

say "Helper scripts (panacea/scripts/custom)"
for f in "$HERE"/panacea/scripts/custom/*; do put "${f#$HERE/}" "$CFG/${f#$HERE/}"; done

say "Editor as an app (Open with > Panacea Editor; no default is changed)"
put applications/panacea-editor.desktop "$DATA/applications/panacea-editor.desktop"

say "Portal backend: the island's file picker and Open with for every app"
put portal/panacea.portal "$DATA/xdg-desktop-portal/portals/panacea.portal"
put portal/org.freedesktop.impl.portal.desktop.panacea.service "$DATA/dbus-1/services/org.freedesktop.impl.portal.desktop.panacea.service"
put portal/hyprland-portals.conf "$CFG/xdg-desktop-portal/hyprland-portals.conf"

say "systemd user units (portal backend, re-patching after Panacea updates)"
for f in "$HERE"/systemd/user/*; do put "${f#$HERE/}" "$CFG/systemd/user/$(basename "$f")"; done
systemctl --user daemon-reload
systemctl --user enable --now panacea-portal-patch.path

say "Patching Panacea"
python3 -I "$CFG/hypr/custom/bin/portal-patch.py" || echo "  patch skipped (see the message above) - Panacea stays as it was"
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
systemctl --user restart panacea-portal.service 2>/dev/null || true
systemctl --user try-restart xdg-desktop-portal || true

echo
[ -d "$BK" ] && echo "Backups of replaced files: $BK"
cat <<'EOF'
Done. The shell reloads by itself. Optional, once:
  - startup apps: run ~/.config/panacea/scripts/custom/startup-apps.py once per session,
    e.g. from hypr/custom/autostart.lua inside hl.on("hyprland.start", ...)
  - task manager shortcut: bind `qs -p ~/.config/panacea ipc call pill tasks` (e.g. Super+Shift+Esc)
EOF
