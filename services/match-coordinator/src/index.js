const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};

const QUEUE_TTL_SECONDS = 600;

function json(status, value) {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function error(status, title, message) {
  return json(status, { schema: 1, state: "failed", title, message });
}

function base64UrlEncode(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function base64UrlDecode(value) {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function signingKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function issueCapability(ticketId, clientNonce, secret, nowSeconds) {
  const payload = new TextEncoder().encode(JSON.stringify({
    v: 1,
    t: ticketId,
    n: clientNonce,
    e: nowSeconds + QUEUE_TTL_SECONDS,
  }));
  const encoded = base64UrlEncode(payload);
  const signature = await crypto.subtle.sign("HMAC", await signingKey(secret), new TextEncoder().encode(encoded));
  return `${encoded}.${base64UrlEncode(new Uint8Array(signature))}`;
}

async function readCapability(value, secret, nowSeconds) {
  if (typeof value !== "string" || value.length < 24 || value.length > 1024) return null;
  const parts = value.split(".");
  if (parts.length !== 2) return null;
  let signature;
  let payload;
  try {
    signature = base64UrlDecode(parts[1]);
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])));
  } catch {
    return null;
  }
  const valid = await crypto.subtle.verify(
    "HMAC",
    await signingKey(secret),
    signature,
    new TextEncoder().encode(parts[0]),
  );
  if (!valid || payload?.v !== 1 || typeof payload.t !== "string" ||
      typeof payload.n !== "string" || !Number.isInteger(payload.e) || payload.e < nowSeconds) return null;
  return payload;
}

function validIdentifier(value, max = 64) {
  return typeof value === "string" && new RegExp(`^[A-Za-z0-9][A-Za-z0-9._-]{0,${max - 1}}$`, "u").test(value);
}

async function requestJson(request, maxBytes = 4096) {
  const contentLength = Number(request.headers.get("content-length") || 0);
  if (contentLength > maxBytes) throw new Error("request_too_large");
  const text = await request.text();
  if (text.length > maxBytes) throw new Error("request_too_large");
  return JSON.parse(text);
}

function configuredBeacons(env) {
  let beacons;
  try {
    beacons = JSON.parse(env.MATCHMAKER_BEACONS || "{}");
  } catch {
    throw new Error("invalid_beacon_configuration");
  }
  if (!beacons || typeof beacons !== "object" || Array.isArray(beacons) || Object.keys(beacons).length < 1) {
    throw new Error("invalid_beacon_configuration");
  }
  return beacons;
}

async function edgegap(env, path, init = {}) {
  const response = await fetch(`${env.MATCHMAKER_API_URL}${path}`, {
    ...init,
    headers: {
      accept: "application/json",
      authorization: env.EDGEGAP_MATCHMAKER_TOKEN,
      ...(init.body ? { "content-type": "application/json" } : {}),
    },
  });
  let body = {};
  try { body = await response.json(); } catch { /* sanitized below */ }
  if (!response.ok) {
    const failure = new Error("upstream_failed");
    failure.status = response.status;
    throw failure;
  }
  return body;
}

async function applyRateLimit(binding, key) {
  if (!binding?.limit) return true;
  const result = await binding.limit({ key });
  return result.success;
}

async function rateKey(request, scope) {
  const material = `${request.headers.get("cf-connecting-ip") || "local"}:${scope}`;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(material));
  return base64UrlEncode(new Uint8Array(digest));
}

function assignmentEndpoint(ticket, gamePort) {
  const assignment = ticket?.assignment;
  if (!assignment || typeof assignment.fqdn !== "string" || !assignment.ports) return null;
  let candidate = assignment.ports.gameport;
  if (!candidate) {
    candidate = Object.values(assignment.ports).find((port) =>
      Number(port?.internal) === gamePort && String(port?.protocol).toUpperCase() === "UDP");
  }
  const external = Number(candidate?.external);
  if (!candidate || Number(candidate.internal) !== gamePort ||
      String(candidate.protocol).toUpperCase() !== "UDP" ||
      !Number.isInteger(external) || external < 1 || external > 65535) return null;
  return { host: assignment.fqdn, port: external, transport: "enet_udp" };
}

function publicState(status) {
  switch (String(status || "").toUpperCase()) {
    case "SEARCHING": return "searching";
    case "MATCH_FOUND": return "deploying";
    case "HOST_ASSIGNED": return "ready";
    case "CANCELLED": return "failed";
    default: return "queued";
  }
}

async function createQueue(request, env, nowSeconds) {
  let body;
  try { body = await requestJson(request); } catch { return error(400, "INVALID REQUEST", "The queue request was invalid."); }
  if (body?.schema !== 1 || !validIdentifier(body.client_nonce, 64) ||
      body.game_version !== env.GAME_VERSION || Number(body.protocol) !== Number(env.NETWORK_PROTOCOL) ||
      !validIdentifier(body.build_id, 64)) {
    return error(409, "VERSION MISMATCH", "Restart One Gun to download the current playtest build.");
  }
  if (!await applyRateLimit(env.QUEUE_RATE_LIMITER, await rateKey(request, "queue-create"))) {
    return error(429, "QUEUE RATE LIMITED", "Wait a minute before creating another ticket.");
  }
  const playerIp = request.headers.get("cf-connecting-ip");
  let ticket;
  try {
    ticket = await edgegap(env, "/tickets", {
      method: "POST",
      body: JSON.stringify({
        player_ip: playerIp || null,
        profile: env.MATCHMAKER_PROFILE,
        attributes: { beacons: configuredBeacons(env) },
      }),
    });
  } catch {
    return error(503, "MATCHMAKER UNAVAILABLE", "The development Matchmaker could not create a ticket.");
  }
  if (!validIdentifier(ticket?.id, 128)) return error(502, "INVALID MATCHMAKER RESPONSE", "No ticket was created.");
  const queueToken = await issueCapability(ticket.id, body.client_nonce, env.COORDINATOR_SIGNING_KEY, nowSeconds);
  return json(201, { schema: 1, state: "queued", queue_token: queueToken, retry_after_ms: 2500 });
}

async function readQueue(request, env, nowSeconds) {
  let body;
  try { body = await requestJson(request); } catch { return error(400, "INVALID REQUEST", "The status request was invalid."); }
  const capability = await readCapability(body?.queue_token, env.COORDINATOR_SIGNING_KEY, nowSeconds);
  if (!capability) return error(401, "QUEUE EXPIRED", "This queue request is invalid or expired.");
  if (!await applyRateLimit(env.STATUS_RATE_LIMITER, await rateKey(request, capability.n))) {
    return error(429, "STATUS RATE LIMITED", "Wait briefly before checking again.");
  }
  let ticket;
  try { ticket = await edgegap(env, `/tickets/${encodeURIComponent(capability.t)}`); }
  catch { return error(503, "MATCHMAKER UNAVAILABLE", "The development Matchmaker did not return ticket status."); }
  const state = publicState(ticket.status);
  if (state !== "ready") {
    return json(200, { schema: 1, state, retry_after_ms: 2500,
      ...(state === "failed" ? { message: "The Matchmaker cancelled this ticket." } : {}) });
  }
  const endpoint = assignmentEndpoint(ticket, Number(env.GAME_PORT));
  if (!endpoint) return error(502, "INVALID SERVER ASSIGNMENT", "The assigned ENet UDP port was missing.");
  return json(200, { schema: 1, state: "ready", endpoint, ticket: capability.t });
}

async function cancelQueue(request, env, nowSeconds) {
  let body;
  try { body = await requestJson(request); } catch { return json(202, { schema: 1, state: "cancelled" }); }
  const capability = await readCapability(body?.queue_token, env.COORDINATOR_SIGNING_KEY, nowSeconds);
  if (capability) {
    try { await edgegap(env, `/tickets/${encodeURIComponent(capability.t)}`, { method: "DELETE" }); }
    catch { /* expiration and already-assigned tickets are harmless here */ }
  }
  return json(202, { schema: 1, state: "cancelled" });
}

export async function handleRequest(request, env, nowSeconds = Math.floor(Date.now() / 1000)) {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/health") {
    return json(200, { service: "one-gun-match-coordinator", status: "ok", schema: 1 });
  }
  if (request.method !== "POST") return error(405, "METHOD NOT ALLOWED", "Use the documented coordinator operation.");
  if (!env.EDGEGAP_MATCHMAKER_TOKEN || !env.COORDINATOR_SIGNING_KEY ||
      env.COORDINATOR_SIGNING_KEY.length < 32) {
    return error(503, "COORDINATOR MISCONFIGURED", "The coordinator is not ready.");
  }
  if (url.pathname === "/v1/queue") return createQueue(request, env, nowSeconds);
  if (url.pathname === "/v1/queue/status") return readQueue(request, env, nowSeconds);
  if (url.pathname === "/v1/queue/cancel") return cancelQueue(request, env, nowSeconds);
  return error(404, "NOT FOUND", "The coordinator route does not exist.");
}

export default { fetch: (request, env) => handleRequest(request, env) };
