"use client";
import { useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useSession } from "@/components/session-provider";
import { api, ApiError } from "./api-client";
import { invalidateProjectViews } from "./project-cache";
import type { ApiResponse } from "./workspace-types";
import { useNotice } from "@/components/ui/notice-provider";

export function useProjectMutation() {
  const { me, refreshAccess } = useSession();
  const client = useQueryClient();
  const notify = useNotice();
  const lock = useRef(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function run<T>(
    path: string,
    method: string,
    body: unknown,
    message = "Project changes saved",
  ): Promise<T | undefined> {
    if (lock.current || !me) return;
    lock.current = true;
    setPending(true);
    setError(null);
    try {
      const result = await api<ApiResponse<T>>(path, { method, body });
      await refreshAccess(
        method === "POST" && !path.endsWith("transfer-ownership"),
      );
      await invalidateProjectViews(client, me.organization.id, me.user.id);
      const channel = new BroadcastChannel("tokentrack-projects");
      channel.postMessage({ organizationId: me.organization.id });
      channel.close();
      notify(message);
      return result.data;
    } catch (reason) {
      if (reason instanceof ApiError && [401, 403, 404].includes(reason.status))
        await refreshAccess();
      setError(
        reason instanceof Error ? reason.message : "Project change failed",
      );
    } finally {
      lock.current = false;
      setPending(false);
    }
  }
  return { run, pending, error, clearError: () => setError(null) };
}
