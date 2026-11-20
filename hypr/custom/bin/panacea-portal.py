#!/usr/bin/env python3
"""File-chooser and app-chooser portal backend that uses Panacea's island.

The app chooser ("Open with...", AppChooser) shows the suggested apps on an island page
(AppChooserView, `ipc call pill chooseApp`); it also falls back to GTK.

Apps (browsers, Electron apps like Claude or Discord, GTK apps...) ask
xdg-desktop-portal for an Open/Save dialog; xdg-desktop-portal hands the call
to this backend, which asks Panacea (over its IPC) to show its file manager in
picker mode and returns what you chose. If Panacea is not running or its
picker patch is missing, the call is forwarded to the GTK backend unchanged,
so an app never ends up without a dialog.

    panacea-portal.py                 run the backend (systemd user service)
    panacea-portal.py --reply ID JSON Panacea's answer for request ID
"""
import itertools, json, os, socket, subprocess, sys, threading, urllib.parse

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
SOCK = os.path.join(RUNTIME, "panacea-portal.sock")

if len(sys.argv) == 4 and sys.argv[1] == "--reply":
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(SOCK)
        s.sendall(json.dumps({"id": sys.argv[2], "answer": json.loads(sys.argv[3])}).encode())
    sys.exit(0)

from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.freedesktop.impl.portal.desktop.panacea"
PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.impl.portal.FileChooser"
GTK = "org.freedesktop.impl.portal.desktop.gtk"
PANACEA = os.path.expanduser("~/.config/panacea")
ARGS = '<arg type="o" name="handle" direction="in"/><arg type="s" name="app_id" direction="in"/>' \
       '<arg type="s" name="parent_window" direction="in"/><arg type="s" name="title" direction="in"/>' \
       '<arg type="a{sv}" name="options" direction="in"/>' \
       '<arg type="u" name="response" direction="out"/><arg type="a{sv}" name="results" direction="out"/>'
XML = f'<node><interface name="{IFACE}">' + "".join(
    f'<method name="{m}">{ARGS}</method>' for m in ("OpenFile", "SaveFile", "SaveFiles")) + \
    '<property name="version" type="u" access="read"/></interface>' + \
    '<interface name="org.freedesktop.impl.portal.AppChooser">' \
    '<method name="ChooseApplication"><arg type="o" name="handle" direction="in"/>' \
    '<arg type="s" name="app_id" direction="in"/><arg type="s" name="parent_window" direction="in"/>' \
    '<arg type="as" name="choices" direction="in"/><arg type="a{sv}" name="options" direction="in"/>' \
    '<arg type="u" name="response" direction="out"/><arg type="a{sv}" name="results" direction="out"/></method>' \
    '<method name="UpdateChoices"><arg type="o" name="handle" direction="in"/>' \
    '<arg type="as" name="choices" direction="in"/></method>' \
    '<property name="version" type="u" access="read"/></interface></node>'
CHOOSER = "org.freedesktop.impl.portal.AppChooser"

pending = {}            # request id -> (invocation, method, options)
ids = itertools.count(1)
bus = None


def log(*a):
    print("panacea-portal:", *a, file=sys.stderr, flush=True)


def path_of(ay):
    """Portal paths are NUL-terminated byte arrays."""
    if not ay:
        return ""
    return bytes(ay).rstrip(b"\0").decode("utf-8", "surrogateescape")


def uri(p):
    return "file://" + urllib.parse.quote(p)


def finish(inv, ok, uris):
    results = {"uris": GLib.Variant("as", uris)} if ok else {}
    inv.return_value(GLib.Variant("(ua{sv})", (0 if ok else 1, results)))


def forward_to_gtk(inv, method, params):
    def done(conn, res):
        try:
            inv.return_value(conn.call_finish(res))
        except GLib.Error as e:
            log("GTK fallback failed:", e.message)
            inv.return_value(GLib.Variant("(ua{sv})", (2, {})))
    bus.call(GTK, PATH, IFACE, method, params, GLib.VariantType("(ua{sv})"),
             Gio.DBusCallFlags.NONE, GLib.MAXINT, None, done)


def choose_app(params, inv):
    """Open with...: the island lists the choices; GTK's dialog if the island can't."""
    _handle, app_id, _parent, choices, opts = params.unpack()
    target = opts.get("filename") or opts.get("uri") or ""
    spec = {"id": str(next(ids)), "kind": "app", "choices": list(choices), "app": app_id,
            "type": opts.get("content_type", ""), "target": target, "last": opts.get("last_choice", "")}
    try:
        r = subprocess.run(["qs", "-p", PANACEA, "ipc", "call", "pill", "chooseApp", json.dumps(spec)],
                           capture_output=True, text=True, timeout=5)
        ok = r.returncode == 0 and "chooseApp" not in (r.stderr + r.stdout)
    except (OSError, subprocess.TimeoutExpired):
        ok = False
    if not ok:
        log("Panacea app chooser unavailable - using the GTK dialog")
        def done(conn, res):
            try:
                inv.return_value(conn.call_finish(res))
            except GLib.Error as e:
                log("GTK fallback failed:", e.message)
                inv.return_value(GLib.Variant("(ua{sv})", (2, {})))
        bus.call(GTK, PATH, CHOOSER, "ChooseApplication", params, GLib.VariantType("(ua{sv})"),
                 Gio.DBusCallFlags.NONE, GLib.MAXINT, None, done)
        return
    pending[spec["id"]] = (inv, "ChooseApplication", opts)


def on_call(conn, sender, path, iface, method, params, inv):
    if iface == CHOOSER:
        if method == "ChooseApplication":
            choose_app(params, inv)
        else:   # UpdateChoices: the list on the island stays as it was
            inv.return_value(None)
        return
    _handle, app_id, _parent, title, opts = params.unpack()
    folder = path_of(opts.get("current_folder"))
    name = opts.get("current_name", "")
    cur = path_of(opts.get("current_file"))
    if cur:
        folder, name = os.path.dirname(cur), os.path.basename(cur)
    spec = {
        "id": str(next(ids)),
        "title": title or ("Save" if method != "OpenFile" else "Open"),
        "save": method == "SaveFile",
        "directory": bool(opts.get("directory")) or method == "SaveFiles",
        "multiple": bool(opts.get("multiple")),
        "name": name,
        "folder": folder if folder and os.path.isdir(folder) else "",
        "accept": opts.get("accept_label", ""),
        "app": app_id,
    }
    try:
        r = subprocess.run(["qs", "-p", PANACEA, "ipc", "call", "pill", "pickFile", json.dumps(spec)],
                           capture_output=True, text=True, timeout=5)
        ok = r.returncode == 0 and "pickFile" not in (r.stderr + r.stdout)
    except (OSError, subprocess.TimeoutExpired):
        ok = False
    if not ok:
        log(f"Panacea picker unavailable for {app_id or 'app'} - using the GTK dialog")
        forward_to_gtk(inv, method, params)
        return
    pending[spec["id"]] = (inv, method, opts)


def on_answer(msg):
    rid, ans = str(msg.get("id")), msg.get("answer") or {}
    item = pending.pop(rid, None)
    if not item:
        return False
    inv, method, opts = item
    if method == "ChooseApplication":
        choice = ans.get("choice")
        if ans.get("ok") and isinstance(choice, str) and choice:
            inv.return_value(GLib.Variant("(ua{sv})", (0, {"choice": GLib.Variant("s", choice)})))
        else:
            inv.return_value(GLib.Variant("(ua{sv})", (1, {})))
        return False
    paths = [p for p in ans.get("paths", []) if isinstance(p, str) and p]
    if not ans.get("ok") or not paths:
        finish(inv, False, [])
        return False
    if method == "SaveFiles":   # chosen folder + the names the app proposed
        names = [path_of(f) for f in opts.get("files", [])]
        finish(inv, True, [uri(os.path.join(paths[0], n)) for n in names])
    else:
        finish(inv, True, [uri(p) for p in (paths if opts.get("multiple") else paths[:1])])
    return False


def serve_socket():
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    os.chmod(SOCK, 0o600)
    srv.listen(4)
    while True:
        c, _ = srv.accept()
        with c:
            data = b""
            while chunk := c.recv(65536):
                data += chunk
        try:
            GLib.idle_add(on_answer, json.loads(data))
        except ValueError:
            pass


def on_bus(conn, name):
    global bus
    bus = conn
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    for i, ver in ((node.interfaces[0], 3), (node.interfaces[1], 2)):
        conn.register_object(PATH, i, on_call, lambda *a, v=ver: GLib.Variant("u", v), None)


threading.Thread(target=serve_socket, daemon=True).start()
Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE, on_bus, None,
                 lambda *a: (log("lost the bus name"), sys.exit(1)))
GLib.MainLoop().run()
