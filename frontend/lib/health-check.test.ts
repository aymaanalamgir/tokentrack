import { test } from "node:test";
import assert from "node:assert/strict";
import { checkService, getHealth } from "./health-check";

function mock(body: unknown, status = 200): typeof fetch {
  return (async () => Response.json(body, { status })) as typeof fetch;
}

test("Rails requires a database confirmation, not just HTTP 200", async () => {
  assert.equal(
    (
      await checkService(
        "core",
        "http://core",
        mock({ service: "core-api", status: "ok", database: "connected" }),
      )
    ).state,
    "connected",
  );
  assert.equal(
    (await checkService("core", "http://core", mock({ status: "ok" }))).state,
    "error",
  );
});
test("Actuator DOWN produces an error and disconnected database", async () => {
  const health = await checkService(
    "usage",
    "http://usage",
    mock({ status: "DOWN", components: { db: { status: "DOWN" } } }, 503),
  );
  assert.equal(health.state, "error");
  assert.equal(health.database, "disconnected");
});
test("invalid JSON and unexpected bodies are handled", async () => {
  assert.equal(
    (
      await checkService(
        "core",
        "http://core",
        (async () => new Response("not json")) as typeof fetch,
      )
    ).state,
    "error",
  );
  assert.equal(
    (await checkService("usage", "http://usage", mock(null))).state,
    "error",
  );
});
test("network failures and timeouts are disconnected", async () => {
  for (const error of [
    new TypeError("connection refused"),
    new DOMException("timeout", "TimeoutError"),
  ]) {
    assert.equal(
      (
        await checkService("core", "http://core", (async () => {
          throw error;
        }) as typeof fetch)
      ).state,
      "disconnected",
    );
  }
});
test("database status combines both independent service checks", async () => {
  const request = (async (input: string | URL | Request) =>
    String(input).includes("core")
      ? Response.json({
          service: "core-api",
          status: "ok",
          database: "connected",
        })
      : Response.json({
          status: "UP",
          components: { db: { status: "UP" } },
        })) as typeof fetch;
  assert.equal(
    (await getHealth("http://core", "http://usage", request)).database.state,
    "connected",
  );
  const failedUsage = (async (
    input: string | URL | Request,
    init?: RequestInit,
  ) => {
    if (String(input).includes("usage")) throw new TypeError("unreachable");
    return request(input, init);
  }) as typeof fetch;
  const result = await getHealth("http://core", "http://usage", failedUsage);
  assert.equal(result.core.state, "connected");
  assert.equal(result.usage.state, "disconnected");
  assert.equal(result.database.state, "disconnected");
});
