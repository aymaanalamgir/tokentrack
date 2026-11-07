import "server-only";
import { getHealth } from "./health-check";

export function getSystemHealth() {
  return getHealth(
    process.env.CORE_API_URL ?? "http://localhost:3001",
    process.env.USAGE_ENGINE_URL ?? "http://localhost:8080",
  );
}
