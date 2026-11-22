#!/usr/bin/env node
// Panacea <-> boopis bots bridge. Run by the
// island (BotsLink.qml) while Settings > Bots is on. No dependencies: Node's own net and WebSocket.
//
// boopis runs an unmodified Hermes gateway per engine home (<boopis data>/engine, a bot's home is
// engine/profiles/<name>). Like boopis's own host this bridge:
//   1. asks the gateway's control socket (<home>/gateway.sock, one JSON line in, one out) for
//      `identify` and a single-use `session-ticket` for the profile;
//   2. opens ws://127.0.0.1:<port>/api/ws with the subprotocols
//      "hermes-gateway-v1" and "hermes-gateway-ticket.<ticket>", and no Origin;
//   3. speaks hermes-gateway-v1 JSON-RPC: runtime.describe, client.capabilities, then
//      profiles.list (roster), plugin.boopis.bots.read (looks), groups.* (team rooms) on the user's
//      link, and session.create / prompt.submit / approval.respond / session.interrupt on each
//      bot's own link (the engine binds a ticket to one profile).
// It never starts the engine: if no gateway answers it reports {"t":"link","up":false,"why":"closed"}.
//
// stdout, one JSON object per line (what BotsLink.qml reads):
//   {"t":"link","up":false,"why":"closed"|"nohome"|"incompatible"|"error","detail":...}
//   {"t":"bots","bots":[{id,name,role,model,shape,color,reaction,word,attention,last}]}
//   {"t":"bot","id",...changed fields}                        state of one bot changed
//   {"t":"msg","bot","id","who":"you"|<bot>,"text","done"}    a thread message (done:false = streaming)
//   {"t":"tool","bot","name","done"}                          a tool step of the turn in progress
//   {"t":"approval","bot","id","command","description","choices","timeout"}
//   {"t":"settled","bot","id"}
//   {"t":"rooms","rooms":[{id,name,members}]}  {"t":"roomlog","room","events":[{who,text,seq}]}
//   {"t":"roomstate","room","working":[ids]}
//   {"t":"notify","bot","title","body"}                       a reply finished while the island wasn't open on it
// stdin, one JSON object per line:
//   {"cmd":"send","bot","text"}  {"cmd":"approve","bot","id","choice":"once|session|always|deny"}
//   {"cmd":"interrupt","bot"}    {"cmd":"thread","bot"}  (the bot's latest session as messages)
//   {"cmd":"roomSend","room","text"}  {"cmd":"refresh"}
import { createConnection } from "node:net";
import { createInterface } from "node:readline";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DATA = process.env.BOOPIS_DATA || join(process.env.XDG_DATA_HOME || join(homedir(), ".local/share"), "dev.aphesist.boopis");
const ROOT = join(DATA, "engine");
const out = o => process.stdout.write(JSON.stringify(o) + "\n");
const REACT = { idle: "", listening: "listening", thinking: "thinking", working: "working", compute: "running",
                speaking: "replying", needs: "needs you", done: "done", error: "failed", sleeping: "asleep" };
// boopis's default look for a bot with none saved (apps/desktop/ui/src/data/looks.ts lookFor)
const SWATCHES = ["#efece6", "#a6a6ab", "#1c1c24", "#c4834a", "#f23b5a", "#f5a337", "#2fd26a", "#4fc9a8", "#3b82f6", "#6d5cf0", "#9b5cf6", "#f472b6"];
const SHAPES = ["circle", "squircle", "soft", "wide", "tall", "bean", "drop", "ghost", "triangle", "hexagon", "diamond", "cloud", "clover", "flower", "star"];
function lookFor(name) {
  let h = 0x811c9dc5;
  for (let i = 0; i < name.length; i++) { h ^= name.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return { color: SWATCHES[h % SWATCHES.length], shape: SHAPES[(h >>> 8) % SHAPES.length] };
}

// ---- the control socket ---------------------------------------------------------------------
function control(home, req) {
  return new Promise((resolve, reject) => {
    const sock = createConnection(join(home, "gateway.sock"));
    let buf = "";
    const t = setTimeout(() => { sock.destroy(); reject(new Error("timeout")); }, 2000);
    sock.on("connect", () => sock.write(JSON.stringify({ protocol: 1, id: 1, ...req }) + "\n"));
    sock.on("data", d => {
      buf += d;
      const nl = buf.indexOf("\n");
      if (nl < 0) return;
      clearTimeout(t); sock.end();
      try { const m = JSON.parse(buf.slice(0, nl)); m.error ? reject(new Error(m.error.message || "refused")) : resolve(m.result); }
      catch (e) { reject(e); }
    });
    sock.on("error", e => { clearTimeout(t); reject(e); });
  });
}
async function dial(home) {
  const id = await control(home, { verb: "identify" });
  if (id.state !== "ready") throw new Error("gateway " + id.state);
  const served = id.served_profiles || [];
  const p = served.find(s => s.home === home) || (served.length === 1 ? served[0] : null);
  if (!p) throw new Error("the gateway does not serve " + home);
  const r = await control(home, { verb: "session-ticket", params: { profile_id: p.profile_id, instance_id: id.instance_id, purpose: "interactive" } });
  const url = id.api_origin.replace(/^http/, "ws").replace(/\/$/, "") + "/api/ws";
  if (!/^ws:\/\/(127\.0\.0\.1|localhost|\[::1\])[:/]/.test(url)) throw new Error("not a loopback gateway");
  return { url, protocols: ["hermes-gateway-v1", "hermes-gateway-ticket." + r.ticket], describe: id };
}

// ---- one link (JSON-RPC over the gateway WebSocket) -------------------------------------------
class Link {
  constructor(name, home) { this.name = name; this.home = home; this.ws = null; this.next = 1; this.wait = new Map(); this.onEvent = () => {}; }
  async open() {
    const d = await dial(this.home);
    await new Promise((ok, bad) => {
      const ws = new WebSocket(d.url, d.protocols);
      ws.onopen = () => { this.ws = ws; ok(); };
      ws.onerror = () => bad(new Error("websocket refused"));
      ws.onclose = () => { this.ws = null; for (const r of this.wait.values()) r.bad(new Error("closed")); this.wait.clear(); this.onClose && this.onClose(); };
      ws.onmessage = ev => this.frame(ev.data);
    });
    await this.call("runtime.describe", {});
    await this.call("client.capabilities", { server_requests: true }).catch(() => {});
    return this;
  }
  frame(raw) {
    let f; try { f = JSON.parse(raw); } catch { return; }
    if (f.id !== undefined && this.wait.has(f.id)) {
      const w = this.wait.get(f.id); this.wait.delete(f.id);
      f.error ? w.bad(Object.assign(new Error(f.error.message), { code: f.error.code })) : w.ok(f.result);
    } else if (f.method === "event" && f.params) this.onEvent(f.params);
    else if (f.method && f.id !== undefined) {            // a server request (clarify, secret, sudo...): not ours to answer here
      this.ws.send(JSON.stringify({ jsonrpc: "2.0", id: f.id, error: { code: -32601, message: "the island does not answer " + f.method } }));
    }
  }
  call(method, params) {
    return new Promise((ok, bad) => {
      if (!this.ws) return bad(new Error("not connected"));
      const id = this.next++;
      this.wait.set(id, { ok, bad });
      this.ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
      setTimeout(() => { if (this.wait.delete(id)) bad(new Error("timeout: " + method)); }, 30000);
    });
  }
}

// ---- state ------------------------------------------------------------------------------------
const bots = new Map();          // id -> {id,name,role,model,shape,color,reaction,word,attention,last}
const chats = new Map();         // id -> {link, session, running, approvals:Map(prompt->gen), gen}
let user = null, rooms = [];

function setBot(id, patch) {
  const b = bots.get(id); if (!b) return;
  const changed = {};
  for (const k of Object.keys(patch)) if (b[k] !== patch[k]) { b[k] = patch[k]; changed[k] = patch[k]; }
  if (patch.reaction !== undefined) changed.word = b.word = b.attention ? "needs you" : REACT[b.reaction] ?? "";
  if (Object.keys(changed).length) out({ t: "bot", id, ...changed });
}

async function roster() {
  const listed = await user.call("profiles.list", { include_sessions: true });
  let looks = {};
  try {
    const r = await user.call("plugin.boopis.bots.read", {});
    for (const b of r.bots || []) if (b.record && b.record.look) looks[b.name] = b.record.look;
  } catch {}
  bots.clear();
  // profiles.list leaves model empty for named profiles (BUGS in PLAN.md): describe fills it
  const models = {};
  await Promise.all((listed.profiles || []).filter(p => !p.is_default && !p.model).map(p =>
    user.call("profiles.describe", { name: p.name }).then(d => { models[p.name] = d && d.model && (d.model.default || d.model.name) || ""; }).catch(() => {})));
  for (const p of listed.profiles || []) {
    if (p.is_default || p.name.startsWith("archived--")) continue;
    const look = { ...lookFor(p.name), ...(looks[p.name] || {}) };
    bots.set(p.name, {
      id: p.name, name: p.display_name || p.name, role: p.description || "", model: p.model || models[p.name] || "",
      shape: look.shape, color: look.color, reaction: "idle", word: "", attention: false,
      last: (p.last_session && (p.last_session.preview || p.last_session.title)) || "",
      lastAt: toMs(p.last_session && (p.last_session.updated_at || p.last_session.last_active || p.last_session.ended_at || p.last_session.started_at))
    });
  }
  out({ t: "bots", bots: [...bots.values()] });
}

// a time from boopis (unix seconds, ms or ISO) as ms, 0 if none
function toMs(v) {
  if (v == null || v === "") return 0;
  if (typeof v === "number") return v < 1e12 ? Math.round(v * 1000) : v;
  const n = Date.parse(v); return isNaN(n) ? 0 : n;
}

async function chat(id) {
  let c = chats.get(id);
  if (c && c.link.ws) return c;
  const link = await new Link(id, join(ROOT, "profiles", id)).open();
  c = { link, session: null, running: null, approvals: new Map(), gen: 0 };
  link.onEvent = ev => onBotEvent(id, c, ev);
  link.onClose = () => chats.delete(id);
  chats.set(id, c);
  return c;
}

function onBotEvent(id, c, ev) {
  if (c.session && ev.session_id && ev.session_id !== c.session) return;
  const p = ev.payload || {};
  if (typeof ev.execution_generation === "number") c.gen = ev.execution_generation;
  const msg = () => (c.running ||= { id: "m" + Date.now(), text: "" });
  switch (ev.type) {
    case "message.start": msg(); setBot(id, { reaction: "thinking" }); break;
    case "tool.start": msg(); setBot(id, { reaction: "working" }); out({ t: "tool", bot: id, name: p.name || p.tool_name || "tool", done: false }); break;
    case "tool.complete": out({ t: "tool", bot: id, name: p.name || p.tool_name || "tool", done: true }); break;
    case "message.delta": { const r = msg(); r.text += p.text || ""; setBot(id, { reaction: "speaking" }); out({ t: "msg", bot: id, id: r.id, who: id, text: r.text, done: false }); break; }
    case "message.complete": {
      const r = msg(), text = typeof p.text === "string" ? p.text : r.text;
      c.running = null;
      out({ t: "msg", bot: id, id: r.id, who: id, text, done: true });
      setBot(id, { reaction: "idle", last: text.split("\n")[0].slice(0, 200), lastAt: Date.now() });
      out({ t: "notify", bot: id, title: bots.get(id)?.name + " replied", body: text.slice(0, 280) });
      break;
    }
    case "approval.request": {
      c.approvals.set(p.prompt_id, typeof p.execution_generation === "number" ? p.execution_generation : c.gen);
      setBot(id, { attention: true, reaction: "needs" });
      out({ t: "approval", bot: id, id: p.prompt_id, command: p.command || "", description: p.description || "",
            choices: p.choices || ["once", "session", "always", "deny"], timeout: p.timeout_s || 0 });
      break;
    }
    case "approval.settled": {
      c.approvals.delete(p.prompt_id);
      out({ t: "settled", bot: id, id: p.prompt_id });
      if (!c.approvals.size) setBot(id, { attention: false, reaction: c.running ? "working" : "idle" });
      break;
    }
  }
}

async function send(id, text) {
  const c = await chat(id);
  if (!c.session) {
    const r = await c.link.call("session.create", { source: "panacea-island", close_on_disconnect: false, follow_profile_config: true });
    c.session = r.session_id || (r.session && r.session.id);
  }
  out({ t: "msg", bot: id, id: "u" + Date.now(), who: "you", text, done: true });
  await c.link.call("prompt.submit", { session_id: c.session, text, submission_id: "island-" + Date.now() });
}

async function rooms_() {
  try {
    const r = await user.call("groups.list", { limit: 100 });
    rooms = (r.rooms || []).filter(x => !x.disbanded_at);
    out({ t: "rooms", rooms: rooms.map(x => ({ id: x.room_id, name: x.name, members: x.members.map(m => m.profile || m.member_id) })) });
  } catch { out({ t: "rooms", rooms: [] }); }
}
async function roomLog(room, since) {
  const r = await user.call("groups.log", { room_id: room, since_seq: since || 0, limit: 200 });
  out({ t: "roomlog", room, events: (r.events || []).filter(e => e.type === "message.user" || e.type === "message.member")
        .map(e => ({ seq: e.seq, who: e.type === "message.user" ? "you" : String(e.payload?.member_id ?? ""), text: e.payload?.text ?? "" })) });
  const st = await user.call("groups.state", { room_id: room }).catch(() => null);
  const d = st && st.driver_status;
  out({ t: "roomstate", room, working: d && d.working ? (d.member_activity || []).map(a => a.member_id) : [] });
}

// ---- start --------------------------------------------------------------------------------------
async function start() {
  if (!existsSync(ROOT)) { out({ t: "link", up: false, why: "nohome" }); return setTimeout(start, 10000); }
  try {
    user = await new Link("", ROOT).open();
  } catch (e) {
    out({ t: "link", up: false, why: /ENOENT|ECONNREFUSED|timeout/.test(String(e)) ? "closed" : "error", detail: String(e.message || e) });
    return setTimeout(start, 5000);
  }
  user.onClose = () => { out({ t: "link", up: false, why: "closed" }); setTimeout(start, 3000); };
  user.onEvent = ev => { if (ev.type === "groups.changed" && ev.payload?.room_id) roomLog(ev.payload.room_id).catch(() => {}); };
  out({ t: "link", up: true });
  await roster().catch(e => out({ t: "link", up: false, why: "error", detail: String(e.message || e) }));
  await rooms_();
}

createInterface({ input: process.stdin }).on("line", async line => {
  let c; try { c = JSON.parse(line); } catch { return; }
  try {
    if (c.cmd === "send") await send(c.bot, c.text);
    else if (c.cmd === "approve") {
      const ch = chats.get(c.bot);
      if (ch) await ch.link.call("approval.respond", { session_id: ch.session, execution_generation: ch.approvals.get(c.id) ?? ch.gen, prompt_id: c.id, choice: c.choice });
    }
    else if (c.cmd === "interrupt") { const ch = chats.get(c.bot); if (ch && ch.session) await ch.link.call("session.interrupt", { session_id: ch.session }); }
    else if (c.cmd === "roomSend") await user.call("groups.send", { room_id: c.room, event_id: "island-" + Date.now(), payload: { thread_id: "main", text: c.text } });
    else if (c.cmd === "room") await roomLog(c.room);
    else if (c.cmd === "refresh") { await roster(); await rooms_(); }
  } catch (e) { out({ t: "error", cmd: c.cmd, detail: String(e.message || e) }); }
}).on("close", () => process.exit(0));

start();
