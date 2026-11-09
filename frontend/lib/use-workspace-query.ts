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
  });
  useEffect(() => {
    if (result.error instanceof ApiError && result.error.status === 401)
      expire();
  }, [result.error, expire]);
  return result;
}
