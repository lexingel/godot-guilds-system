// Guildhold save transfer relay (Cloudflare Worker + KV).
// POST /send  body = exported save text -> {"code": "KX74QP"}; kept 15 minutes.
// GET  /take/<code>                     -> the save text, once (then deleted).
// Saves are a few dozen KB of game state; nothing else is stored.

const TTL = 900;                 // seconds a code stays valid
const MAX_BYTES = 512 * 1024;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";   // no 0/O, 1/I
const ORIGINS = ["https://lexingel.github.io"];

function cors(req) {
  const o = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(o) || o.startsWith("http://localhost") ? o : ORIGINS[0],
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    // Godot's web requests add their own headers (User-Agent and others), so
    // allow whatever the browser's preflight asks for.
    "Access-Control-Allow-Headers": req.headers.get("Access-Control-Request-Headers") || "Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function reply(req, body, status = 200, type = "application/json") {
  return new Response(body, { status, headers: { "Content-Type": type, ...cors(req) } });
}

function newCode() {
  const b = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(b, (x) => ALPHABET[x % ALPHABET.length]).join("");
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method === "OPTIONS") return reply(req, null, 204);
    if (req.method === "POST" && url.pathname === "/send") {
      const text = await req.text();
      if (text.length === 0 || text.length > MAX_BYTES) return reply(req, '{"error":"size"}', 413);
      try { JSON.parse(text); } catch { return reply(req, '{"error":"not a save"}', 400); }
      let code = newCode();
      for (let i = 0; i < 4 && (await env.SAVES.get(code)) !== null; i++) code = newCode();
      await env.SAVES.put(code, text, { expirationTtl: TTL });
      return reply(req, JSON.stringify({ code, ttl: TTL }));
    }
    const m = url.pathname.match(/^\/take\/([A-Za-z0-9]{6})$/);
    if (req.method === "GET" && m) {
      const code = m[1].toUpperCase();
      const text = await env.SAVES.get(code);
      if (text === null) return reply(req, '{"error":"expired"}', 404);
      await env.SAVES.delete(code);
      return reply(req, text);
    }
    return reply(req, '{"error":"not found"}', 404);
  },
};
