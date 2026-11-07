export type Connectivity = "connected" | "disconnected" | "loading" | "error";
export type ServiceHealth = {
  state: Connectivity;
  database: Connectivity;
  message: string;
};
export type HealthSnapshot = {
  core: ServiceHealth;
  usage: ServiceHealth;
  database: ServiceHealth;
  checkedAt: string;
};

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function checkService(
  kind: "core" | "usage",
  baseUrl: string,
  request: typeof fetch = fetch,
): Promise<ServiceHealth> {
  try {
    const response = await request(
      new URL(kind === "core" ? "/api/v1/health" : "/actuator/health", baseUrl),
      {
        cache: "no-store",
        signal: AbortSignal.timeout(4000),
        headers: { Accept: "application/json" },
      },
    );
    const body: unknown = await response.json();
    let database: Connectivity;
    let healthy: boolean;
    if (
      kind === "core" &&
      record(body) &&
      body.service === "core-api" &&
      ["ok", "error"].includes(String(body.status)) &&
      ["connected", "disconnected"].includes(String(body.database))
    ) {
      database = body.database as Connectivity;
      healthy = body.status === "ok";
    } else if (
      kind === "usage" &&
      record(body) &&
      ["UP", "DOWN", "OUT_OF_SERVICE", "UNKNOWN"].includes(
        String(body.status),
      ) &&
      record(body.components) &&
      record(body.components.db) &&
      ["UP", "DOWN", "OUT_OF_SERVICE", "UNKNOWN"].includes(
        String(body.components.db.status),
      )
    ) {
      database =
        body.components.db.status === "UP" ? "connected" : "disconnected";
      healthy = body.status === "UP";
    } else {
      return {
        state: "error",
        database: "error",
        message: "Unexpected health response",
      };
    }
    const connected = response.ok && healthy && database === "connected";
    return {
      state: connected ? "connected" : "error",
      database,
      message: connected ? "Health check passed" : "Service reported unhealthy",
    };
  } catch (error) {
    if (error instanceof SyntaxError)
      return {
        state: "error",
        database: "error",
        message: "Invalid health response",
      };
    return {
      state: "disconnected",
      database: "disconnected",
      message: "Service unreachable or timed out",
    };
  }
}

export async function getHealth(
  coreUrl: string,
  usageUrl: string,
  request: typeof fetch = fetch,
): Promise<HealthSnapshot> {
  const [core, usage] = await Promise.all([
    checkService("core", coreUrl, request),
    checkService("usage", usageUrl, request),
  ]);
  const connected =
    core.database === "connected" && usage.database === "connected";
  const database: ServiceHealth = {
    state: connected
      ? "connected"
      : core.database === "error" || usage.database === "error"
        ? "error"
        : "disconnected",
    database: connected ? "connected" : "disconnected",
    message: connected
      ? "Confirmed by both services"
      : "Both schema connections could not be confirmed",
  };
  return { core, usage, database, checkedAt: new Date().toISOString() };
}
