#!/bin/bash
# panacea-local: push-to-talk dictation (voxtype) for the island. Panacea's scripts/voxtype.sh
# hands every call to this (portal-patch). Hold Right Ctrl (Hyprland bind) or press the mic in
# Claude's island chat.
#
#   vox.sh start [chat|app]  start recording; without a target the island decides: its chat
#                            open -> the text goes into the chat box, else voxtype types it
#                            into the focused window
#   vox.sh stop              finish: transcribe and deliver
#   vox.sh toggle [target]   start or stop (the chat's mic button)
#   vox.sh cancel            drop the recording
#   vox.sh available         yes|no
PATH="$PATH:/usr/bin:/usr/local/bin:$HOME/.local/bin:/bin"
CFG="$HOME/.config/panacea"
RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voxtype"
OUT="$RUN/panacea-chat.txt"
TARGET="$RUN/panacea-target"
ipc() { qs -p "$CFG" ipc call pill "$@" 2>/dev/null; }

# voxtype opens the GPU (RTX) at its first transcription and never lets go, which keeps the RTX
# awake for good. 90 s after the last dictation the daemon restarts: the new one holds no GPU
# until it transcribes again, so the RTX can sleep. A new dictation cancels the pending restart.
RELEASE=voxtype-release
release_later() {
    systemctl --user stop "$RELEASE.timer" >/dev/null 2>&1
    systemd-run --user --quiet --collect --unit="$RELEASE" --on-active=90 \
        systemctl --user try-restart voxtype.service >/dev/null 2>&1
}

ensure_daemon() {
    systemctl --user is-active --quiet voxtype && return 0
    systemctl --user start voxtype 2>/dev/null
    for _ in $(seq 1 40); do [ -S "$RUN/audio.sock" ] && return 0; sleep 0.1; done
}

case "${1:-}" in
    available)
        command -v voxtype >/dev/null && echo yes || echo no ;;
    start)
        command -v voxtype >/dev/null || { ipc voxUnavailable >/dev/null; exit 1; }
        [ "$(voxtype status 2>/dev/null)" = recording ] && exit 0
        t="${2:-$(ipc voxTarget)}"; [ "$t" = chat ] || t=app
        systemctl --user stop "$RELEASE.timer" >/dev/null 2>&1
        ensure_daemon
        mkdir -p "$RUN"; printf '%s\n' "$t" > "$TARGET"; rm -f "$OUT"
        if [ "$t" = chat ]; then ok() { voxtype record start --file="$OUT" >/dev/null 2>&1; }
        else ok() { voxtype record start >/dev/null 2>&1; }; fi
        if ok || { sleep 0.25; ok; }; then ipc voxListening "$t" >/dev/null
        else rm -f "$TARGET"; ipc voxUnavailable >/dev/null; exit 1; fi ;;
    stop)
        t=$(cat "$TARGET" 2>/dev/null)
        [ -n "$t" ] || [ "$(voxtype status 2>/dev/null)" = recording ] || exit 0
        ipc voxTranscribing >/dev/null
        if [ "$t" = chat ]; then
            voxtype record stop --wait --timeout 60 --wait-file "$OUT" >/dev/null 2>&1
            text=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$OUT" 2>/dev/null)
            [ -n "$text" ] && ipc voxChatText "$text" >/dev/null
            rm -f "$OUT"
        else
            voxtype record stop >/dev/null 2>&1
            for _ in $(seq 1 200); do
                s=$(cat "$RUN/state" 2>/dev/null)
                [ "$s" = transcribing ] || [ "$s" = recording ] || break
                sleep 0.05
            done
        fi
        rm -f "$TARGET"
        ipc voxDone >/dev/null
        release_later ;;
    toggle)
        if [ -f "$TARGET" ] || [ "$(voxtype status 2>/dev/null)" = recording ]; then exec "$0" stop; else exec "$0" start "${2:-}"; fi ;;
    cancel)
        voxtype record cancel >/dev/null 2>&1
        rm -f "$TARGET" "$OUT"
        ipc voxDone >/dev/null
        release_later ;;
    *)
        echo "usage: vox.sh start [chat|app]|stop|toggle [chat|app]|cancel|available" >&2; exit 1 ;;
esac
