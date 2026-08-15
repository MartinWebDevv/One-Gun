import assert from "node:assert/strict";
import test from "node:test";
import { handleRequest } from "../src/index.js";

test("queue creation rate key cannot be bypassed by rotating client nonce", async (t) => {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  let ticket = 0;
  globalThis.fetch = async () => Response.json({ id: `ticket-${++ticket}`, status: "SEARCHING" }, { status: 201 });
  const keys = [];
  const env = {
    EDGEGAP_MATCHMAKER_TOKEN: "backend-only-matchmaker-token",
    COORDINATOR_SIGNING_KEY: "0123456789abcdef0123456789abcdef",
    MATCHMAKER_API_URL: "https://matchmaker.test",
    MATCHMAKER_PROFILE: "simple-example",
    MATCHMAKER_BEACONS: '{"Montreal":12.3}',
    GAME_VERSION: "0.0.4",
    NETWORK_PROTOCOL: "2",
    GAME_PORT: "24545",
    QUEUE_RATE_LIMITER: {
      async limit({ key }) { keys.push(key); return { success: true }; },
    },
  };
  for (const nonce of ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]) {
    const response = await handleRequest(new Request("https://coordinator.test/v1/queue", {
      method: "POST",
      headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.9" },
      body: JSON.stringify({
        schema: 1,
        client_nonce: nonce,
        game_version: "0.0.4",
        protocol: 2,
        build_id: "dev-test",
      }),
    }), env, 1000);
    assert.equal(response.status, 201);
  }
  assert.equal(keys.length, 2);
  assert.equal(keys[0], keys[1]);
});
