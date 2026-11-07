"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { Cable, Database, Info, RefreshCw, Server } from "lucide-react";
import type { HealthSnapshot, ServiceHealth } from "@/lib/health-check";
import { Button } from "@/components/ui/button";
import { StatusCard } from "@/components/status-card";
import { Tooltip } from "@/components/ui/tooltip";

const loading: ServiceHealth = {
  state: "loading",
  database: "loading",
  message: "Waiting for health response",
};

export function SystemStatus() {
  const [health, setHealth] = useState<HealthSnapshot | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const active = useRef<AbortController | null>(null);
  const refresh = useCallback(async () => {
    active.current?.abort();
    const controller = new AbortController();
    active.current = controller;
    setRefreshing(true);
    try {
      const response = await fetch("/api/health", {
        cache: "no-store",
        signal: AbortSignal.any([controller.signal, AbortSignal.timeout(6500)]),
      });
      if (response.status !== 200 && response.status !== 503)
        throw new Error("Health route unavailable");
      const body = (await response.json()) as HealthSnapshot;
      if (!body.core?.state || !body.usage?.state || !body.database?.state)
        throw new Error("Invalid health snapshot");
      setHealth(body);
    } catch {
      if (controller.signal.aborted) return;
      const error: ServiceHealth = {
        state: "error",
        database: "error",
        message: "Unable to retrieve system health",
      };
      setHealth({
        core: error,
        usage: error,
        database: error,
        checkedAt: new Date().toISOString(),
      });
    } finally {
      if (!controller.signal.aborted) setRefreshing(false);
    }
  }, []);
  useEffect(() => {
    const initial = setTimeout(() => void refresh(), 0);
    const interval = setInterval(() => void refresh(), 15000);
    return () => {
      clearTimeout(initial);
      clearInterval(interval);
      active.current?.abort();
    };
  }, [refresh]);
  const connected =
    health &&
    [health.core, health.usage, health.database].every(
      (item) => item.state === "connected",
    );

  return (
    <section aria-labelledby="system-status">
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <h2 id="system-status" className="text-sm font-medium">
            System status
          </h2>
          <Tooltip label="Live health checks run through the Next.js server every 15 seconds. Database status requires both services to confirm connectivity.">
            <button
              aria-label="About system status"
              className="text-muted-foreground"
            >
              <Info size={13} />
            </button>
          </Tooltip>
        </div>
        <Button
          variant="ghost"
          size="default"
          disabled={refreshing}
          onClick={() => void refresh()}
          className="h-7 px-2 font-mono text-[10px]"
        >
          <RefreshCw className={refreshing ? "animate-spin" : ""} />
          Refresh status
        </Button>
      </div>
      <div
        className="grid gap-4 md:grid-cols-3"
        aria-live="polite"
        aria-busy={refreshing}
      >
        <StatusCard
          title="Core API"
          subtitle="Rails / business services"
          icon={Server}
          health={health?.core ?? loading}
          index="01"
        />
        <StatusCard
          title="Usage Engine"
          subtitle="Kotlin / processing services"
          icon={Cable}
          health={health?.usage ?? loading}
          index="02"
        />
        <StatusCard
          title="PostgreSQL"
          subtitle="business + usage / isolated schemas"
          icon={Database}
          health={health?.database ?? loading}
          index="03"
        />
      </div>
      <div
        className="mt-4 flex flex-wrap items-center justify-between gap-2 font-mono text-[10px] text-muted-foreground"
        role="status"
      >
        <span className="flex items-center gap-2">
          <span
            className={`size-1.5 rounded-full ${connected ? "bg-success" : health ? "bg-danger" : "bg-muted-foreground"}`}
          />
          {!health
            ? "Establishing service connections"
            : connected
              ? "All systems connected"
              : "Some connections need attention"}
        </span>
        <span>
          {health
            ? `Checked ${new Date(health.checkedAt).toLocaleTimeString()} · `
            : ""}
          auto-refresh 15s
        </span>
      </div>
    </section>
  );
}
