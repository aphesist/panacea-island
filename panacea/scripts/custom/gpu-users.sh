#!/bin/bash
# panacea-local: what keeps the RTX (NVIDIA dGPU) awake, one name per line, for the island's
# battery page. Your own processes with an NVIDIA device open (/dev/nvidia*, its render node);
# root's can't be seen from here, so if none is yours and nvidia-powerd runs, that's named.
# Reading this never wakes the GPU.
nv_nodes=""
for n in /sys/class/drm/renderD* /sys/class/drm/card[0-9]; do
    [ "$(basename "$(readlink -f "$n/device/driver")")" = nvidia ] && nv_nodes="$nv_nodes /dev/dri/$(basename "$n")"
done
found=""
for p in /proc/[0-9]*; do
    fds=$(ls -l "$p/fd" 2>/dev/null) || continue
    hit=$(printf '%s\n' "$fds" | grep -c -e '/dev/nvidia[0-9]' $(for d in $nv_nodes; do printf -- '-e %s ' "$d"; done))
    if [ "$hit" -gt 0 ]; then
        c=$(cat "$p/comm" 2>/dev/null)
        case " $found " in *" $c "*) ;; *) found="$found $c" ;; esac
    fi
done
for c in $found; do
    case "$c" in voxtype*) echo "voxtype (dictation)" ;; *) echo "$c" ;; esac
done
if [ -z "$found" ] && systemctl is-active --quiet nvidia-powerd; then
    echo "nvidia-powerd (Dynamic Boost, Performance mode)"
fi
