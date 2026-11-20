#!/usr/bin/env python3
"""Updates for the island's Updates screen (panacea-config). No root needed.

Repo updates: like checkupdates, a private copy of the sync databases refreshed under fakeroot.
AUR updates: yay -Qua. Arch news: the RSS feed (optional, short timeout). Cache and orphans: read-only.
Prints one JSON object and keeps a copy in $XDG_RUNTIME_DIR/panacea-updates.json (the Home dot reads it).
"""
import json, os, re, shutil, subprocess, time, urllib.request, xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime

RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
DB = os.path.join(RUN, "panacea-updates-db")
OUT = os.path.join(RUN, "panacea-updates.json")


def sh(cmd, timeout=120):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""


def repo_updates():
    os.makedirs(os.path.join(DB, "sync"), exist_ok=True)
    local = os.path.join(DB, "local")
    if not os.path.islink(local):
        os.symlink("/var/lib/pacman/local", local)
    for f in os.listdir("/var/lib/pacman/sync"):
        if f.endswith(".db"):
            src, dst = os.path.join("/var/lib/pacman/sync", f), os.path.join(DB, "sync", f)
            if not os.path.exists(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
                shutil.copy2(src, dst)
    sh(["fakeroot", "--", "pacman", "-Sy", "--disable-sandbox", "--dbpath", DB, "--logfile", "/dev/null"])
    out = []
    for line in sh(["pacman", "-Qu", "--dbpath", DB]).splitlines():
        m = re.match(r"(\S+) (\S+) -> (\S+)", line)
        if m:
            out.append({"n": m[1], "from": m[2], "to": m[3], "repo": "", "size": 0})
    if out:
        fmt = sh(["pacman", "-Sp", "--dbpath", DB, "--print-format", "%n %r %s"] + [p["n"] for p in out])
        info = {}
        for line in fmt.splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[2].isdigit():
                info[parts[0]] = (parts[1], int(parts[2]))
        for p in out:
            p["repo"], p["size"] = info.get(p["n"], ("", 0))
    return out


def aur_updates():
    out = []
    for line in sh(["yay", "-Qua"], timeout=60).splitlines():
        m = re.match(r"(\S+) (\S+) -> (\S+)", line)
        if m:
            out.append({"n": m[1], "from": m[2], "to": m[3], "repo": "aur", "size": 0})
    return out


def news():
    try:
        req = urllib.request.Request("https://archlinux.org/feeds/news/", headers={"User-Agent": "panacea-updates"})
        root = ET.fromstring(urllib.request.urlopen(req, timeout=8).read())
        items = []
        for it in root.iter("item"):
            when = parsedate_to_datetime(it.findtext("pubDate") or "").timestamp()
            if time.time() - when > 21 * 86400:
                continue
            items.append({"title": it.findtext("title"), "link": it.findtext("link"), "at": int(when)})
        return items[:2]
    except Exception:
        return []


def cache():
    d = "/var/cache/pacman/pkg"
    total, files = 0, 0
    try:
        for e in os.scandir(d):
            if e.is_file() and ".pkg.tar" in e.name and not e.name.endswith(".sig"):
                total += e.stat().st_size
                files += 1
    except Exception:
        pass
    return {"bytes": total, "files": files}


def main():
    repo = repo_updates()
    data = {
        "repo": repo,
        "aur": aur_updates(),
        "news": news(),
        "cache": cache(),
        "orphans": [l for l in sh(["pacman", "-Qdtq"]).split() if l],
        "checked": int(time.time()),
    }
    data["count"] = len(data["repo"]) + len(data["aur"])
    text = json.dumps(data)
    with open(OUT, "w") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main()
