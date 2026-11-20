#!/usr/bin/env python3
"""Backend of the island's task manager (TasksView.qml, from portal-patch.py).

  taskman.py stream                  a JSON snapshot per line, every 1.5 s
  taskman.py signal <pid> term|kill  end a process (yours only, never PID 1 or the shell)
  taskman.py unit <user|system> <start|stop|restart> <unit>
                                     system units go through pkexec (Panacea asks)

Reads /proc directly (no psutil). The NVIDIA GPU is only queried while it is
already awake: nvidia-smi would wake it from runtime sleep and cost battery.
"""
import glob, json, os, re, signal, subprocess, sys, time

HZ = os.sysconf("SC_CLK_TCK")
# demo mode (for screenshots): placeholders instead of window titles, network name and address
DEMO = os.path.exists(os.path.expanduser("~/.cache/panacea-demo"))
PAGE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1
ME = os.getuid()


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def cpu_times():
    out = []
    for line in read("/proc/stat").splitlines():
        if line.startswith("cpu"):
            parts = line.split()
            vals = list(map(int, parts[1:9]))
            idle = vals[3] + vals[4]
            out.append((sum(vals), idle))
    return out   # [total, cpu0, cpu1, ...]


def meminfo():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        m[k] = int(v.split()[0]) * 1024 if v.split() else 0
    return {"total": m.get("MemTotal", 0), "used": m.get("MemTotal", 0) - m.get("MemAvailable", 0),
            "swapTotal": m.get("SwapTotal", 0), "swapUsed": m.get("SwapTotal", 0) - m.get("SwapFree", 0)}


def net_bytes():
    rx = tx = 0
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        if name == "lo" or not rest.split():
            continue
        f = rest.split()
        rx += int(f[0]); tx += int(f[8])
    return rx, tx


def disk_bytes():
    r = w = 0
    for line in read("/proc/diskstats").splitlines():
        f = line.split()
        if len(f) > 9 and (f[2].startswith("nvme") and "p" not in f[2][4:] or f[2][:2] in ("sd", "vd") and f[2][-1].isalpha()):
            r += int(f[5]) * 512; w += int(f[9]) * 512
    return r, w


def battery():
    for b in glob.glob("/sys/class/power_supply/BAT*"):
        cap = read(b + "/capacity").strip()
        if cap:
            return {"percent": int(cap), "status": read(b + "/status").strip(),
                    "watts": round(int(read(b + "/power_now", "0").strip() or 0) / 1e6, 1)}
    return None


def nvidia():
    dev = None
    for d in glob.glob("/sys/bus/pci/devices/*"):
        if read(d + "/vendor").strip() == "0x10de" and read(d + "/class").startswith("0x03"):
            dev = d
            break
    if not dev:
        return None
    state = read(dev + "/power/runtime_status").strip() or "active"
    out = {"name": "NVIDIA GPU", "awake": state == "active"}
    if out["awake"]:
        try:
            r = subprocess.run(["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                                "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=3)
            f = [x.strip() for x in r.stdout.strip().split(",")]
            if len(f) >= 6:
                out.update(name=f[0], util=float(f[1]), memUsed=float(f[2]) * 2**20, memTotal=float(f[3]) * 2**20,
                           temp=float(f[4]), watts=float(f[5]) if f[5].replace(".", "").isdigit() else 0)
        except (OSError, subprocess.TimeoutExpired, ValueError):
            pass
    return out


def cpu_temp():
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        if read(z + "/type").strip() in ("x86_pkg_temp", "TCPU", "coretemp"):
            t = read(z + "/temp").strip()
            if t:
                return int(t) / 1000
    return None


def windows():
    try:
        r = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=2)
        return {c["pid"]: {"title": c.get("title", ""), "cls": c.get("class", ""), "address": c.get("address", "")}
                for c in json.loads(r.stdout) if c.get("pid", 0) > 0}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}


def desktop_index():
    """window class / program name -> (app name, icon name), from .desktop files"""
    idx = {}
    dirs = [os.path.expanduser("~/.local/share/applications"), "/usr/share/applications",
            "/var/lib/flatpak/exports/share/applications", os.path.expanduser("~/.local/share/flatpak/exports/share/applications")]
    for d in reversed(dirs):
        for f in glob.glob(d + "/*.desktop"):
            name = icon = wm = exe = ""
            in_main = False
            for line in read(f).splitlines():
                if line.startswith("["):
                    in_main = line.strip() == "[Desktop Entry]"
                    continue
                if not in_main or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k == "Name" and not name: name = v.strip()
                elif k == "Icon": icon = v.strip()
                elif k == "StartupWMClass": wm = v.strip()
                elif k == "Exec" and not exe:
                    toks = [t for t in v.split() if "=" not in t and t not in ("env", "flatpak", "run") and not t.startswith("%")]
                    exe = os.path.basename(toks[0]) if toks else ""
            if not icon:
                continue
            stem = os.path.basename(f)[:-8]
            for key in {wm, stem, stem.split(".")[-1], exe}:
                if key:
                    idx.setdefault(key.lower(), (name, icon))
    return idx


def hardware():
    """the parts, for the Performance tab (read once)"""
    hw = {}
    cpu = {}
    for line in read("/proc/cpuinfo").splitlines():
        if line.startswith("model name") and "model" not in cpu:
            cpu["model"] = line.split(":", 1)[1].strip()
    cores = set()
    for d in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/topology"):
        cores.add((read(d + "/physical_package_id").strip(), read(d + "/core_id").strip()))
    cpu["cores"] = len(cores) or NCPU
    cpu["threads"] = NCPU
    mx = [int(read(f).strip() or 0) for f in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq")]
    cpu["maxMHz"] = round(max(mx) / 1000) if mx else 0
    hw["cpu"] = cpu
    gpus = []
    try:
        for line in subprocess.run(["lspci", "-mm"], capture_output=True, text=True, timeout=3).stdout.splitlines():
            f = [x.strip('"') for x in re.findall(r'"[^"]*"|\S+', line)]
            if len(f) > 3 and ("VGA" in f[1] or "3D" in f[1] or "Display" in f[1]):
                gpus.append(f[2].replace(" Corporation", "") + " " + re.sub(r"\s*\[.*?\]\s*", " ", f[3]).strip())
    except (OSError, subprocess.TimeoutExpired):
        pass
    hw["gpus"] = gpus
    disks = []
    try:
        data = json.loads(subprocess.run(["lsblk", "-J", "-d", "-b", "-o", "NAME,MODEL,SIZE,TRAN,ROTA,TYPE"],
                                         capture_output=True, text=True, timeout=3).stdout)
        for b in data.get("blockdevices", []):
            if b.get("type") == "disk" and not str(b.get("name", "")).startswith(("zram", "loop")):
                disks.append({"name": b["name"], "model": (b.get("model") or "").strip(), "size": int(b.get("size") or 0),
                              "kind": "NVMe SSD" if b.get("tran") == "nvme" else ("HDD" if b.get("rota") else "SSD")})
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    hw["disks"] = disks
    st = os.statvfs("/")
    hw["root"] = {"total": st.f_blocks * st.f_frsize, "free": st.f_bavail * st.f_frsize}
    m = meminfo()
    # speed and type: systemd's udev reads the DMI memory tables at boot (no root needed)
    mod = {}
    try:
        for line in subprocess.run(["udevadm", "info", "/sys/devices/virtual/dmi/id"], capture_output=True, text=True, timeout=3).stdout.splitlines():
            mm = re.match(r"E: MEMORY_DEVICE_(\d+)_(\w+)=(.*)", line)
            if mm:
                mod.setdefault(int(mm.group(1)), {})[mm.group(2)] = mm.group(3)
    except (OSError, subprocess.TimeoutExpired):
        pass
    sticks = [d for d in mod.values() if d.get("SIZE", "0").isdigit() and int(d.get("SIZE", "0")) > 0]
    first = sticks[0] if sticks else {}
    ram_extra = {"type": first.get("TYPE", ""), "speed": int(first.get("CONFIGURED_SPEED_MTS") or first.get("SPEED_MTS") or 0),
                 "rated": int(first.get("SPEED_MTS") or 0), "maker": first.get("MANUFACTURER", ""),
                 "part": first.get("PART_NUMBER", "").strip(), "form": first.get("FORM_FACTOR", ""),
                 "modules": len(sticks), "slots": len(mod)}
    hw["ram"] = {**ram_extra, "total": m["total"], "swap": m["swapTotal"],
                 "zram": any(read(f).strip() for f in glob.glob("/sys/block/zram*/disksize") if read(f).strip() not in ("", "0"))}
    net = {}
    try:
        r = subprocess.run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"], capture_output=True, text=True, timeout=3)
        for line in r.stdout.splitlines():
            dev, typ, state, conn = (line.split(":") + ["", "", "", ""])[:4]
            if state == "connected" and typ in ("wifi", "ethernet"):
                net = {"device": dev, "type": "Wi-Fi" if typ == "wifi" else "Ethernet", "connection": conn}
                break
        if net:
            r = subprocess.run(["ip", "-4", "-br", "addr", "show", net["device"]], capture_output=True, text=True, timeout=3)
            parts = r.stdout.split()
            net["ip"] = parts[2].split("/")[0] if len(parts) > 2 else ""
            drv = os.path.realpath(f"/sys/class/net/{net['device']}/device/driver")
            net["driver"] = os.path.basename(drv)
    except (OSError, subprocess.TimeoutExpired):
        pass
    if DEMO and net:
        net.update(connection="Home Wi-Fi", ip="192.168.1.24")
    hw["net"] = net
    bat = {}
    for b in glob.glob("/sys/class/power_supply/BAT*"):
        full = int(read(b + "/charge_full", "0").strip() or read(b + "/energy_full", "0").strip() or 0)
        design = int(read(b + "/charge_full_design", "0").strip() or read(b + "/energy_full_design", "0").strip() or 0)
        bat = {"model": (read(b + "/manufacturer").strip() + " " + read(b + "/model_name").strip()).strip(),
               "health": round(100 * full / design) if design else 0,
               "cycles": int(read(b + "/cycle_count", "0").strip() or 0), "tech": read(b + "/technology").strip()}
        break
    hw["battery"] = bat
    fam = read("/sys/class/dmi/id/product_family").strip()
    hw["machine"] = fam if fam and fam.lower() not in ("default string", "to be filled by o.e.m.") else \
        (read("/sys/class/dmi/id/sys_vendor").strip() + " " + read("/sys/class/dmi/id/product_name").strip()).strip()
    mxf = [read(f).strip() for f in glob.glob("/sys/class/drm/card*/gt_max_freq_mhz")]
    hw["igpuMaxMHz"] = int(mxf[0]) if mxf and mxf[0].isdigit() else 1500
    return hw


def cpu_mhz():
    f = [int(read(x).strip() or 0) for x in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
    return round(sum(f) / len(f) / 1000) if f else 0


def igpu_mhz():
    for f in glob.glob("/sys/class/drm/card*/gt_cur_freq_mhz") + glob.glob("/sys/class/drm/card*/device/tile0/gt0/freq0/cur_freq"):
        v = read(f).strip()
        if v.isdigit():
            return int(v)
    return 0


def processes():
    procs = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        stat = read(f"/proc/{d}/stat")
        if not stat:
            continue
        try:
            name = stat[stat.index("(") + 1:stat.rindex(")")]
            f = stat[stat.rindex(")") + 2:].split()
            st = os.stat(f"/proc/{d}")
        except (ValueError, OSError):
            continue
        procs[int(d)] = {"pid": int(d), "name": name, "state": f[0], "ppid": int(f[1]),
                         "ticks": int(f[11]) + int(f[12]), "threads": int(f[17]),
                         "rss": int(f[21]) * PAGE, "uid": st.st_uid}
    return procs


def pretty_name(pid, name):
    cmd = read(f"/proc/{pid}/cmdline").split("\0")
    if cmd and " " in cmd[0] and not os.path.exists(cmd[0]):   # Electron folds its args into argv[0]
        cmd = cmd[0].split(" ") + cmd[1:]
    exe = os.path.basename(cmd[0]) if cmd and cmd[0] else ""
    if exe in ("python3", "python", "bash", "sh", "node", "electron") and len(cmd) > 1:
        arg = next((a for a in cmd[1:] if a and not a.startswith("-")), "")
        if arg:
            return f"{os.path.basename(arg)} ({exe})"
    if exe and (re.fullmatch(r"[\d.]+", name) or (len(exe) > len(name) and exe.startswith(name[:15]))):
        return exe if not re.fullmatch(r"[\d.]+", exe) else os.path.basename(os.path.dirname(cmd[0])) or name
    return name


def stream():
    prev_cpu, prev_ticks, prev_t = cpu_times(), {}, time.time()
    prev_net, prev_disk = net_bytes(), disk_bytes()
    names, wins, gpu, n = {}, {}, None, 0
    icons = desktop_index()
    time.sleep(0.5)
    while True:
        now = time.time(); dt = max(now - prev_t, 0.1)
        cur = cpu_times()
        usage = []
        for (t1, i1), (t0, i0) in zip(cur, prev_cpu):
            usage.append(round(100 * (1 - (i1 - i0) / max(t1 - t0, 1)), 1))
        prev_cpu = cur
        if n % 2 == 0:
            wins = windows()
        if n % 3 == 0:
            gpu = nvidia()
        procs = processes()
        rows, byPid, kids = [], {}, {}
        for pid, p in procs.items():
            d = p["ticks"] - prev_ticks.get(pid, p["ticks"])
            if pid not in names:
                names[pid] = pretty_name(pid, p["name"])
            ent = icons.get(names[pid].split(" ")[0].lower()) or icons.get(p["name"].lower())
            r = {"pid": pid, "ppid": p["ppid"], "name": names[pid], "cpu": round(100 * d / HZ / dt / NCPU, 1),
                 "mem": p["rss"], "mine": p["uid"] == ME, "kernel": p["rss"] == 0 and p["ppid"] in (0, 2),
                 "icon": ent[1] if ent else ""}
            rows.append(r); byPid[pid] = r
            kids.setdefault(p["ppid"], []).append(pid)
        prev_ticks = {pid: p["ticks"] for pid, p in procs.items()}
        # apps: each window's process with everything it started, summed (like Windows)
        apps, covered = [], set()
        for wpid in sorted(wins, key=lambda x: x):
            if wpid not in byPid or wpid in covered:
                continue
            tree, stack = [], [wpid]
            while stack:
                x = stack.pop()
                if x in covered:
                    continue
                covered.add(x); tree.append(x)
                stack.extend(kids.get(x, []))
            w = wins[wpid]
            ent = icons.get(w["cls"].lower()) or icons.get(w["cls"].split(".")[-1].lower()) or icons.get(byPid[wpid]["name"].split(" ")[0].lower())
            members = sorted((byPid[x] for x in tree), key=lambda r: (-r["cpu"], -r["mem"]))
            apps.append({"pid": wpid, "name": ent[0] if ent and ent[0] else (w["cls"] or byPid[wpid]["name"]),
                         "window": ("Window" if DEMO else w["title"]), "icon": ent[1] if ent else byPid[wpid]["icon"],
                         "cpu": round(sum(r["cpu"] for r in members), 1), "mem": sum(r["mem"] for r in members),
                         "count": len(members),
                         "kids": [{"pid": r["pid"], "name": r["name"], "cpu": r["cpu"], "mem": r["mem"], "icon": r["icon"]} for r in members[:40]]})
        names = {pid: v for pid, v in names.items() if pid in procs}
        net, disk = net_bytes(), disk_bytes()
        snap = {
            "t": now, "ncpu": NCPU,
            "cpu": {"total": usage[0] if usage else 0, "cores": usage[1:], "temp": cpu_temp(),
                    "load": read("/proc/loadavg").split()[:3]},
            "mem": meminfo(),
            "net": {"rx": (net[0] - prev_net[0]) / dt, "tx": (net[1] - prev_net[1]) / dt},
            "disk": {"read": (disk[0] - prev_disk[0]) / dt, "write": (disk[1] - prev_disk[1]) / dt},
            "gpu": gpu, "battery": battery(),
            "uptime": float(read("/proc/uptime", "0").split()[0]),
            "apps": apps,
            "procs": sorted([{k: r[k] for k in ("pid", "name", "cpu", "mem", "mine", "icon")} for r in rows
                             if not r["kernel"] and r["pid"] not in covered], key=lambda r: (-r["cpu"], -r["mem"]))[:400],
            "mhz": cpu_mhz(), "igpuMHz": igpu_mhz(),
            "count": len(rows),
        }
        prev_net, prev_disk, prev_t = net, disk, now
        print(json.dumps(snap, separators=(",", ":")), flush=True)
        n += 1
        time.sleep(1.5)


def units():
    out = []
    for scope in ("user", "system"):
        args = ["systemctl", "--no-pager", "--plain", "--no-legend", "list-units", "--type=service", "--all", "--output=json"]
        if scope == "user":
            args.insert(1, "--user")
        try:
            data = json.loads(subprocess.run(args, capture_output=True, text=True, timeout=5).stdout or "[]")
        except (OSError, ValueError, subprocess.TimeoutExpired):
            data = []
        for u in data:
            if u.get("load") != "loaded":
                continue
            out.append({"scope": scope, "unit": u.get("unit", ""), "active": u.get("active", ""),
                        "sub": u.get("sub", ""), "desc": u.get("description", "")})
    return {"units": out}


def main(argv):
    cmd = argv[0] if argv else "stream"
    if cmd == "stream":
        try:
            stream()
        except (BrokenPipeError, KeyboardInterrupt):
            return None
    if cmd == "units":
        return units()
    if cmd == "hw":
        return hardware()
    if cmd == "signal" and len(argv) == 3:
        pid = int(argv[1])
        if pid <= 1 or pid == os.getpid():
            raise ValueError("not that one")
        if os.stat(f"/proc/{pid}").st_uid != ME:
            raise ValueError("That process belongs to another user")
        os.kill(pid, signal.SIGKILL if argv[2] == "kill" else signal.SIGTERM)
        return {"ok": True}
    if cmd == "unit" and len(argv) == 4:
        scope, action, unit = argv[1:]
        if action not in ("start", "stop", "restart") or not unit.endswith(".service") or "/" in unit:
            raise ValueError("bad unit action")
        args = ["systemctl", "--user", action, unit] if scope == "user" else ["pkexec", "systemctl", action, unit]
        r = subprocess.run(args, capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise ValueError((r.stderr or r.stdout).strip().splitlines()[-1] if (r.stderr or r.stdout).strip() else "failed")
        return {"ok": True}
    raise ValueError("usage: stream | units | signal <pid> term|kill | unit <user|system> <action> <unit>")


if __name__ == "__main__":
    try:
        res = main(sys.argv[1:])
        if res is not None:
            print(json.dumps(res, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
