import http from "node:http";

const portArgument = process.argv.find((value) => value.startsWith("--port="));
const port = Number(portArgument?.slice("--port=".length) || 24810);
let polls = 0;

function send(response, status, value) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(value));
}

const server = http.createServer((request, response) => {
  let body = "";
  request.on("data", (chunk) => { body += chunk; });
  request.on("end", () => {
    let parsed = {};
    try { parsed = JSON.parse(body || "{}"); } catch { /* fail below */ }
    if (request.method === "GET" && request.url === "/health") {
      send(response, 200, { schema: 1, status: "ok" });
      return;
    }
    if (request.method !== "POST" || parsed.schema !== 1) {
      send(response, 400, { schema: 1, state: "failed", message: "invalid smoke request" });
      return;
    }
    if (request.url === "/v1/queue") {
      send(response, 201, {
        schema: 1,
        state: "queued",
        queue_token: "smoke-capability-0123456789abcdef",
        retry_after_ms: 10,
      });
      return;
    }
    if (request.url === "/v1/queue/status") {
      polls += 1;
      if (polls === 1) {
        send(response, 200, { schema: 1, state: "deploying", retry_after_ms: 10 });
      } else {
        send(response, 200, {
          schema: 1,
          state: "ready",
          endpoint: { host: "validation.pr.edgegap.net", port: 30937, transport: "enet_udp" },
          ticket: "smoke-ticket-alpha",
        });
      }
      return;
    }
    if (request.url === "/v1/queue/cancel") {
      send(response, 202, { schema: 1, state: "cancelled" });
      return;
    }
    send(response, 404, { schema: 1, state: "failed", message: "not found" });
  });
});

server.listen(port, "127.0.0.1", () => console.log(`FAKE_MATCH_COORDINATOR_READY ${port}`));

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
