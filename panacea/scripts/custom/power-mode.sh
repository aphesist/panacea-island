#!/bin/sh
# panacea-island: what a power mode does beyond TLP (which already sets the CPU and the Samsung
# firmware profile: quiet / balanced / performance). Run by the shell whenever the mode changes.
#   power-mode.sh <power-saver|balanced|performance> [saverHz 1|0]
# Saver drops the internal OLED to 60 Hz (a mode with a longer vertical blank, same pixel clock:
# inside the panel's 48-120 Hz range); the other modes go back to its native 120 Hz.
# Performance also turns on NVIDIA Dynamic Boost (nvidia-powerd: the GPU may borrow the CPU's
# power budget under load, on AC); the other modes turn it off, since it can keep the GPU awake.
# Starting/stopping it needs no password thanks to system/polkit/50-panacea-nvidia-powerd.rules.
profile="$1"; saver_hz="${2:-1}"

if systemctl cat nvidia-powerd.service >/dev/null 2>&1; then
    if [ "$profile" = "performance" ]; then
        systemctl is-active -q nvidia-powerd || systemctl start --no-ask-password nvidia-powerd.service 2>/dev/null
    else
        systemctl is-active -q nvidia-powerd && systemctl stop --no-ask-password nvidia-powerd.service 2>/dev/null
    fi
fi

out="eDP-1"
[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] || HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -1)
export HYPRLAND_INSTANCE_SIGNATURE
hyprctl monitors 2>/dev/null | grep -q "^Monitor $out " || exit 0      # no internal panel (lid closed, docked)

# the panel's own timings: 655.13 MHz, 2980 x 1832 total at 120 Hz; 3664 lines total = 60 Hz
SIXTY="modeline 655.13 2880 2912 2920 2980 1800 3640 3648 3664 +hsync -vsync"
current=$(hyprctl monitors | sed -n "/^Monitor $out /{n;p}" | sed 's/.*@\([0-9]*\).*/\1/')
if [ "$profile" = "power-saver" ] && [ "$saver_hz" = 1 ]; then
    [ "$current" -le 61 ] 2>/dev/null && exit 0
    mode="$SIXTY"
else
    [ "$current" -ge 119 ] 2>/dev/null && exit 0
    mode="preferred"          # native 120 Hz ("2880x1800@120" would be ignored: it equals the config's rule)
fi
scale=$(hyprctl monitors | sed -n "/^Monitor $out /,/^$/s/^\tscale: //p")
pos=$(hyprctl monitors | sed -n "/^Monitor $out /{n;p}" | sed 's/.* at \([0-9x-]*\).*/\1/')
hyprctl eval "hl.monitor({ output = \"$out\", mode = \"$mode\", position = \"${pos:-0x0}\", scale = ${scale:-1.6} })" >/dev/null
