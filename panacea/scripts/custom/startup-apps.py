#!/usr/bin/env python3
"""Startup apps (panacea-config): opens the apps switched on in the island's Startup screen.

The list: ~/.config/hypr/custom/startup-apps.json
    {"apps": [{"id": "vesktop.desktop", "name": "Vesktop", "icon": "vesktop",
               "exec": "vesktop %U", "on": true, "delay": 0}]}
Run once per Hyprland session, from hypr/custom/autostart.lua ("hyprland.start").
An app with a desktop id is opened like a launcher would (gtk-launch); otherwise its command.
`startup-apps.py --now <index>` opens one entry right away (the screen's "Open now").
"""
import json, os, re, subprocess, sys, threading, time

LIST = os.path.expanduser("~/.config/hypr/custom/startup-apps.json")


def launch(app):
    time.sleep(max(0, float(app.get("delay") or 0)))
    app_id = str(app.get("id") or "")
    if app_id.endswith(".desktop"):
        cmd = ["gtk-launch", app_id[:-8]]
    else:
        cmd = ["sh", "-c", re.sub(r"\s%[fFuUdDnNickvm]", "", str(app.get("exec") or "")).strip()]
    if cmd[-1]:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


def main():
    try:
        apps = json.load(open(LIST)).get("apps", [])
    except Exception:
        return
    if len(sys.argv) > 2 and sys.argv[1] == "--now":
        i = int(sys.argv[2])
        if 0 <= i < len(apps):
            launch(dict(apps[i], delay=0))
        return
    threads = [threading.Thread(target=launch, args=(a,)) for a in apps if a.get("on")]
    for t in threads:
        t.start()
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
