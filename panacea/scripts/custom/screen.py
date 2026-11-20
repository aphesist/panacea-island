#!/usr/bin/env python3
"""Screen tools for the island's Screen page (panacea-config).

    screen.py area|window|screen|text|color [delay seconds]

area   Panacea's own frozen-frame screenshot (scripts/shot.sh): saved and copied
window the active window          } saved to ~/Pictures/Screenshots, copied,
screen the focused monitor         } shown by the island (ipc shotCopied)
text   text from an area of a frozen frame (scripts/ocr.sh), copied
color  the colour of one pixel of a frozen frame, copied as #rrggbb; the last
       ones are kept in $XDG_RUNTIME_DIR/panacea-colors.json for the page

It waits for the island to fold away first, then for the delay.
"""
import importlib.util, json, os, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
CFG = os.path.join(HOME, ".config/panacea")
SCRIPTS = os.path.join(CFG, "scripts")
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
SHOTS = os.path.join(os.environ.get("XDG_PICTURES_DIR", os.path.join(HOME, "Pictures")), "Screenshots")
COLORS = os.path.join(RUN, "panacea-colors.json")


def ipc(*args):
    subprocess.run(["qs", "-p", CFG, "ipc", "call", "pill", *args], capture_output=True)


def notify(title, body=""):
    subprocess.run(["notify-send", "-a", "Screen", title, body], capture_output=True)


def hypr(what):
    return json.loads(subprocess.run(["hyprctl", "-j", what], capture_output=True, text=True).stdout or "null")


def out_path():
    os.makedirs(SHOTS, exist_ok=True)
    return os.path.join(SHOTS, time.strftime("Screenshot_%Y-%m-%d_%H-%M-%S.png"))


def saved(path):
    with open(path, "rb") as f:
        subprocess.run(["wl-copy", "-t", "image/png"], stdin=f)
    ipc("shotCopied", path)


def frozen_pick(point=False):
    """A still frame shown by the shell while you select. -> (ppm path, slurp geometry) or None."""
    fd, ppm = tempfile.mkstemp(dir=RUN, prefix="panacea-screen.", suffix=".ppm")
    os.close(fd)
    if subprocess.run(["grim", "-t", "ppm", ppm]).returncode != 0:
        os.unlink(ppm)
        return None
    ipc("freeze", ppm)
    time.sleep(0.08)
    cmd = ["slurp", "-p"] if point else ["slurp", "-b", "00000060", "-c", "ffffffff", "-w", "1"]
    geom = subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
    ipc("unfreeze")
    if not geom:
        os.unlink(ppm)
        return None
    return ppm, geom


def shotcrop():
    spec = importlib.util.spec_from_file_location("shotcrop", os.path.join(SCRIPTS, "shotcrop.py"))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "area"
    delay = float(sys.argv[2]) if len(sys.argv) > 2 else 0
    time.sleep(0.45 + delay)          # the island folds away first

    if mode == "area":
        os.execv(os.path.join(SCRIPTS, "shot.sh"), ["shot.sh"])

    if mode == "window":
        w = hypr("activewindow") or {}
        if not w.get("size"):
            notify("No window to capture")
            return
        (x, y), (ww, hh) = w["at"], w["size"]
        path = out_path()
        if subprocess.run(["grim", "-g", f"{x},{y} {ww}x{hh}", path]).returncode == 0:
            saved(path)
        return

    if mode == "screen":
        mon = next((m for m in hypr("monitors") or [] if m.get("focused")), None)
        path = out_path()
        if subprocess.run(["grim"] + (["-o", mon["name"]] if mon else []) + [path]).returncode == 0:
            saved(path)
        return

    if mode == "text":
        pick = frozen_pick()
        if not pick:
            return
        ppm, geom = pick
        fd, png = tempfile.mkstemp(dir=RUN, prefix="panacea-ocr.", suffix=".png")
        os.close(fd)
        try:
            subprocess.run(["python3", os.path.join(SCRIPTS, "shotcrop.py"), ppm, geom, png], check=True)
            r = subprocess.run([os.path.join(SCRIPTS, "ocr.sh"), png, "--copy"], capture_output=True, text=True)
            text = r.stdout.strip()
            if r.returncode == 0 and text:
                first = text.splitlines()[0]
                notify("Text copied", first[:80] + ("…" if len(first) > 80 or "\n" in text else ""))
            elif r.returncode == 2:
                notify("Text recognition isn't installed", "Install tesseract")
            else:
                notify("No text found in that area")
        finally:
            for f in (ppm, png):
                try:
                    os.unlink(f)
                except OSError:
                    pass
        return

    if mode == "color":
        pick = frozen_pick(point=True)
        if not pick:
            return
        ppm, geom = pick
        try:
            sc = shotcrop()
            w, h, data = sc.read_ppm(ppm)
            x, y, _, _ = sc.parse_geom(geom)
            min_x, min_y, scale = sc.layout_frame(w)
            px = min(w - 1, max(0, int((x - min_x) * scale)))
            py = min(h - 1, max(0, int((y - min_y) * scale)))
            i = (py * w + px) * 3
            hexc = "#%02x%02x%02x" % (data[i], data[i + 1], data[i + 2])
        finally:
            os.unlink(ppm)
        subprocess.run(["wl-copy", hexc])
        try:
            last = json.load(open(COLORS))
        except Exception:
            last = []
        last = [hexc] + [c for c in last if c != hexc]
        json.dump(last[:8], open(COLORS, "w"))
        notify("Colour copied", hexc)


if __name__ == "__main__":
    main()
