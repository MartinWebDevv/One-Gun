import assert from "node:assert/strict";
import test from "node:test";
import { handleRequest } from "../src/index.js";

const ENV = {
  EDGEGAP_MATCHMAKER_TOKEN: "backend-only-matchmaker-token",
  COORDINATOR_SIGNING_KEY: "0123456789abcdef0123456789abcdef",
  MATCHMAKER_API_URL: "https://matchmaker.test",
  MATCHMAKER_PROFILE: "simple-example",
  MATCHMAKER_BEACONS: '{"Montreal":12.3}',
  GAME_VERSION: "0.0.4",
  NETWORK_PROTOCOL: "2",
  GAME_PORT: "24545",
};

function post(path, body) {
  return new Request(`https://coordinator.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.7" },
    body: JSON.stringify(body),
  });
}

test("queue capability hides the backend token and returns assigned UDP endpoint", async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let createdBody;
  globalThis.fetch = async (url, init = {}) => {
    assert.equal(init.headers.authorization, ENV.EDGEGAP_MATCHMAKER_TOKEN);
    if (String(url).endsWith("/tickets") && init.method === "POST") {
      createdBody = JSON.parse(init.body);
      return Response.json({ id: "ticket-alpha", status: "SEARCHING" }, { status: 201 });
    }
    assert.match(String(url), /\/tickets\/ticket-alpha$/u);
    return Response.json({
      id: "ticket-alpha",
      status: "HOST_ASSIGNED",
      assignment: {
        fqdn: "assigned.pr.edgegap.net",
        ports: { gameport: { internal: 24545, external: 31983, protocol: "UDP" } },
      },
    });
  };

  const created = await handleRequest(post("/v1/queue", {
    schema: 1,
    client_nonce: "0123456789abcdef0123456789abcdef",
    game_version: "0.0.4",
    protocol: 2,
    build_id: "dev-test",
  }), ENV, 1000);
  assert.equal(created.status, 201);
  const createdJson = await created.json();
  assert.ok(createdJson.queue_token.length > 24);
  assert.equal(JSON.stringify(createdJson).includes(ENV.EDGEGAP_MATCHMAKER_TOKEN), false);
  assert.equal(createdBody.player_ip, "203.0.113.7");
  assert.equal(createdBody.profile, "simple-example");

  const ready = await handleRequest(post("/v1/queue/status", {
    schema: 1,
    queue_token: createdJson.queue_token,
  }), ENV, 1001);
  assert.equal(ready.status, 200);
  assert.deepEqual(await ready.json(), {
    schema: 1,
    state: "ready",
    endpoint: { host: "assigned.pr.edgegap.net", port: 31983, transport: "enet_udp" },
    ticket: "ticket-alpha",
  });
});

test("tampered capabilities and incompatible clients fail closed", async () => {
  const mismatch = await handleRequest(post("/v1/queue", {
    schema: 1,
    client_nonce: "0123456789abcdef0123456789abcdef",
    game_version: "0.0.4",
    protocol: 1,
    build_id: "old-build",
  }), ENV, 1000);
  assert.equal(mismatch.status, 409);

  const tampered = await handleRequest(post("/v1/queue/status", {
    schema: 1,
    queue_token: "eyJ0IjoiZXZpbCJ9.invalid-signature",
  }), ENV, 1000);
  assert.equal(tampered.status, 401);
});

test("invalid external mapping is never returned to the game", async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (url) => Response.json(
    String(url).endsWith("/tickets")
      ? { id: "ticket-beta", status: "SEARCHING" }
      : { id: "ticket-beta", status: "HOST_ASSIGNED", assignment: {
          fqdn: "assigned.pr.edgegap.net",
          ports: { gameport: { internal: 7777, external: 31983, protocol: "UDP" } },
        } },
    { status: String(url).endsWith("/tickets") ? 201 : 200 },
  );
  const created = await handleRequest(post("/v1/queue", {
    schema: 1,
    client_nonce: "fedcba9876543210fedcba9876543210",
    game_version: "0.0.4",
    protocol: 2,
    build_id: "dev-test",
  }), ENV, 2000);
  const token = (await created.json()).queue_token;
  const status = await handleRequest(post("/v1/queue/status", { schema: 1, queue_token: token }), ENV, 2001);
  assert.equal(status.status, 502);
});
