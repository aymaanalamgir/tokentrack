"use client";
import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { api, ApiError } from "@/lib/api-client";
import { useSession } from "@/components/session-provider";
import type { ApiResponse } from "./workspace-types";

export function useWorkspaceQuery<T>(path: string, enabled = true) {
  const { me, expire } = useSession();
  const result = useQuery({
    queryKey: [me?.organization.id, me?.user.id, path],
    queryFn: ({ signal }) => api<ApiResponse<T>>(path, { signal }),
    enabled: !!me && enabled,
    staleTime: 30000,
    retry: false,
    refetchInterval:
      /^projects\/[0-9a-f-]{36}(?:$|\?|\/memberships|\/team-groups)/.test(path)
        ? 10000
        : false,
  });
  useEffect(() => {
    if (result.error instanceof ApiError && result.error.status === 401)
      expire();
  }, [result.error, expire]);
  return result;
}
