import { getSystemHealth } from "@/lib/health";

export const dynamic = "force-dynamic";
export async function GET() {
  const health = await getSystemHealth();
  const healthy = [health.core, health.usage, health.database].every(
    (service) => service.state === "connected",
  );
  return Response.json(health, {
    status: healthy ? 200 : 503,
    headers: { "Cache-Control": "no-store" },
  });
}
