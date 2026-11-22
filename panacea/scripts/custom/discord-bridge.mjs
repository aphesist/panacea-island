#!/usr/bin/env node
// Panacea <-> Discord (Vesktop) voice bridge. Run by the island (DiscordVoice.qml) while
// Settings > Discord is on. No dependencies: Node's own fetch and WebSocket.
//
// Vesktop is started with --remote-debugging-port (~/.config/vesktop-flags.conf; Chromium
// binds it to 127.0.0.1 only and refuses WebSockets that carry a web page's Origin). This
// attaches to Discord's page, installs a small listener that reads Vencord's webpack stores
// (VoiceStateStore, MediaEngineStore, SpeakingStore...) and calls Discord's own audio actions.
//
// stdout, one JSON object per line:
//   {"t":"link","up":false,"why":"closed"|"noflag"|"restart"}   not running / no port flag / started before it
//   {"t":"state", up:true, call, channel, guild, mute, deaf, ..., people:[...]}
//   {"t":"speak","id":"<user id>","on":true}
// stdin, one JSON object per line: {"cmd":"mute"|"deafen"|"disconnect"|"noise"|"refresh"}
//   {"cmd":"localMute","id":...}  {"cmd":"volume","id":...,"v":0..200}
import { readdirSync, readFileSync } from "node:fs";
import { createInterface } from "node:readline";

const PORT = Number(process.env.PANACEA_DISCORD_PORT || 9223);
const out = o => process.stdout.write(JSON.stringify(o) + "\n");

// ---- the part that runs inside Discord's page --------------------------------------------
const PAGE = String.raw`(() => {
  const emit = o => { try { window.__panaceaVoice(JSON.stringify(o)); } catch (e) {} };
  if (window.__panaceaVoiceKick) { window.__panaceaVoiceKick(); return "again"; }
  const V = window.Vencord, W = V && V.Webpack, C = W && W.Common;
  if (!C || !C.UserStore || !C.FluxDispatcher || !C.UserStore.getCurrentUser()) return "wait";
  const store = n => { try { return W.findStore(n) || null; } catch (e) { return null; } };
  const props = (...p) => { try { return W.findByProps(...p) || null; } catch (e) { return null; } };
  const VS = store("VoiceStateStore"), ME = store("MediaEngineStore"), SP = store("SpeakingStore");
  const RTC = store("RTCConnectionStore"), SC = C.SelectedChannelStore || store("SelectedChannelStore");
  const US = C.UserStore, CS = C.ChannelStore, GS = C.GuildStore, GM = C.GuildMemberStore;
  const audio = props("toggleSelfMute", "toggleSelfDeaf");
  const voice = props("selectVoiceChannel", "disconnect") || props("selectVoiceChannel");
  if (!VS || !ME || !SC || !audio) return "wait";
  const call = (f, ...a) => { try { return f ? f(...a) : undefined; } catch (e) { return undefined; } };
  let since = 0, lastCh = null;

  function build() {
    const me = US.getCurrentUser();
    const chId = SC.getVoiceChannelId();
    if (chId !== lastCh) { lastCh = chId; since = chId ? Date.now() : 0; }
    const ch = chId ? CS.getChannel(chId) : null;
    const gId = ch && ch.guild_id ? ch.guild_id : null;
    const g = gId ? GS.getGuild(gId) : null;
    const states = chId ? (VS.getVoiceStatesForChannel(chId) || {}) : {};
    const people = Object.values(states).map(s => {
      const u = US.getUser(s.userId);
      const self = !!me && s.userId === me.id;
      const nick = gId && GM ? call(GM.getNick.bind(GM), gId, s.userId) : null;
      return {
        id: s.userId, me: self,
        name: nick || (u && (u.globalName || u.username)) || "Unknown",
        avatar: u ? (call(u.getAvatarURL.bind(u), gId, 128) || "") : "",
        mute: !!(s.selfMute || s.mute || (self && ME.isSelfMute())), deaf: !!(s.selfDeaf || s.deaf),
        serverMute: !!s.mute, serverDeaf: !!s.deaf, video: !!s.selfVideo, stream: !!s.selfStream,
        speaking: !!(SP && call(SP.isSpeaking.bind(SP), s.userId)),
        localMute: !self && !!call(ME.isLocalMute.bind(ME), s.userId),
        volume: self ? 100 : Math.round(call(ME.getLocalVolume.bind(ME), s.userId) ?? 100)
      };
    }).sort((a, b) => (b.me - a.me) || a.name.localeCompare(b.name));
    const ncGet = ME.getNoiseCancellation || ME.getNoiseSuppression;
    return {
      t: "state", up: true, call: !!chId,
      channel: ch ? (ch.name || (ch.recipients ? "Call" : "Voice")) : "",
      guild: g ? g.name : (ch ? "Direct call" : ""),
      guildIcon: g && g.icon ? "https://cdn.discordapp.com/icons/" + g.id + "/" + g.icon + ".png?size=64" : "",
      since: since, mute: !!ME.isSelfMute(), deaf: !!ME.isSelfDeaf(),
      noise: ncGet ? !!call(ncGet.bind(ME)) : null,
      rtc: RTC ? String(call(RTC.getState.bind(RTC)) || "") : "",
      ping: RTC ? (call((RTC.getLastPing || RTC.getAveragePing || (() => 0)).bind(RTC)) || 0) : 0,
      me: me ? me.id : "", people: people
    };
  }
  let timer = 0, last = "";
  const fire = () => { clearTimeout(timer); timer = setTimeout(() => {
    const s = JSON.stringify(build()); if (s !== last) { last = s; emit(JSON.parse(s)); } }, 40); };
  [VS, ME, SC, RTC].forEach(s => s && s.addChangeListener && s.addChangeListener(fire));
  C.FluxDispatcher.subscribe("SPEAKING", e => { if (e && e.userId) emit({ t: "speak", id: e.userId, on: !!e.speakingFlags }); });
  window.__panaceaVoiceKick = () => { last = ""; fire(); };
  window.__panaceaVoiceCmd = c => {
    switch (c.cmd) {
      case "mute": audio.toggleSelfMute(); break;
      case "deafen": audio.toggleSelfDeaf(); break;
      case "disconnect": voice && (voice.disconnect ? voice.disconnect() : voice.selectVoiceChannel(null)); break;
      case "localMute": audio.toggleLocalMute && audio.toggleLocalMute(c.id); break;
      case "volume": audio.setLocalVolume && audio.setLocalVolume(c.id, Math.max(0, Math.min(200, Number(c.v) || 0))); break;
      case "noise": {
        const get = ME.getNoiseCancellation, set = audio.setNoiseCancellation;
        if (get && set) set(!get.call(ME)); break;
      }
      case "refresh": last = ""; break;
    }
    fire();
  };
  fire();
  return "ok";
})()`;

// ---- the bridge -----------------------------------------------------------------------------
let ws = null, nextId = 1, waiters = new Map(), linkSent = "", injectTimer = null;

// Why it can't be reached: "closed" (not running), "noflag" (the port isn't in
// vesktop-flags.conf) or "restart" (it is, but this Vesktop was started before).
function whyDown() {
  let cmd = null;
  try {
    for (const p of readdirSync("/proc")) {
      if (!/^\d+$/.test(p)) continue;
      try {
        if (readFileSync(`/proc/${p}/comm`, "utf8").trim() !== "vesktop") continue;
        const c = readFileSync(`/proc/${p}/cmdline`, "utf8");
        if (!c.includes("--type=")) { cmd = c; break; }   // the main process, not a helper
      } catch {}
    }
  } catch {}
  if (cmd === null) return "closed";
  if (cmd.includes(`--remote-debugging-port=${PORT}`)) return "closed";   // still starting
  let flags = "";
  try { flags = readFileSync(`${process.env.XDG_CONFIG_HOME || process.env.HOME + "/.config"}/vesktop-flags.conf`, "utf8"); } catch {}
  return flags.split("\n").some(l => l.trim() === `--remote-debugging-port=${PORT}`) ? "restart" : "noflag";
}
function link(why) {
  if (linkSent === why) return;
  linkSent = why;
  out({ t: "link", up: false, why });
}
function send(method, params = {}) {
  return new Promise(resolve => {
    if (!ws || ws.readyState !== 1) return resolve(null);
    const id = nextId++;
    waiters.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
    setTimeout(() => { if (waiters.delete(id)) resolve(null); }, 5000);
  });
}
async function inject() {
  clearTimeout(injectTimer);
  const r = await send("Runtime.evaluate", { expression: PAGE, returnByValue: true });
  const v = r && r.result && r.result.result && r.result.result.value;
  if (v !== "ok" && v !== "again") injectTimer = setTimeout(inject, 1500);   // Discord still loading
}
async function connect() {
  let list;
  try {
    const res = await fetch(`http://127.0.0.1:${PORT}/json/list`, { signal: AbortSignal.timeout(2000) });
    list = await res.json();
  } catch {
    link(whyDown());
    return setTimeout(connect, 3000);
  }
  const page = list.find(t => t.type === "page" && /^https:\/\/(\w+\.)?discord\.com\//.test(t.url));
  if (!page || !page.webSocketDebuggerUrl) { link("closed"); return setTimeout(connect, 2000); }
  ws = new WebSocket(page.webSocketDebuggerUrl);
  ws.onopen = async () => {
    await send("Runtime.addBinding", { name: "__panaceaVoice" });
    await send("Runtime.enable");
    inject();
  };
  ws.onmessage = ev => {
    let m; try { m = JSON.parse(ev.data); } catch { return; }
    if (m.id && waiters.has(m.id)) { waiters.get(m.id)(m); waiters.delete(m.id); return; }
    if (m.method === "Runtime.bindingCalled" && m.params.name === "__panaceaVoice") {
      linkSent = "";
      // Discord's CDN serves WebP, which Qt can't read without qt6-imageformats: ask for PNG
      process.stdout.write(m.params.payload.replace(/(https:\/\/cdn\.discordapp\.com\/[^"?]+?)\.(webp|gif)(\?size=\d+)?/g, "$1.png?size=128") + "\n");
    } else if (m.method === "Runtime.executionContextCreated" && m.params.context.auxData && m.params.context.auxData.isDefault) {
      clearTimeout(injectTimer); injectTimer = setTimeout(inject, 1500);   // the page reloaded
    }
  };
  ws.onclose = () => {
    ws = null; clearTimeout(injectTimer);
    for (const r of waiters.values()) r(null);
    waiters.clear();
    link(whyDown());
    setTimeout(connect, 2000);
  };
  ws.onerror = () => {};
}

createInterface({ input: process.stdin }).on("line", line => {
  let c; try { c = JSON.parse(line); } catch { return; }
  if (!c || typeof c.cmd !== "string") return;
  send("Runtime.evaluate", { expression: `window.__panaceaVoiceCmd && window.__panaceaVoiceCmd(${JSON.stringify(c)})` });
}).on("close", () => process.exit(0));   // the island went away

connect();
