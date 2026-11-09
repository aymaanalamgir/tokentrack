"use client";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { api, ApiError } from "@/lib/api-client";
import type { ApiResponse, Me } from "@/lib/workspace-types";
import { invalidateProjectViews } from "@/lib/project-cache";

type Session = {
  me: Me | null;
  ready: boolean;
  switching: boolean;
  error: string | null;
  switchIdentity: (id: string) => Promise<void>;
  logout: () => Promise<void>;
  reload: () => void;
  expire: () => void;
  refreshAccess: (allowExpansion?: boolean) => Promise<void>;
};
const SessionContext = createContext<Session | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [ready, setReady] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const generation = useRef(0);
  const busy = useRef(false);
  const channel = useRef<BroadcastChannel | null>(null);
  const client = useQueryClient();
  const router = useRouter();
  const invalidatePendingSession = useCallback(() => {
    generation.current++;
  }, []);

  const clear = useCallback(async () => {
    setMe(null); // Remove privileged content before any asynchronous work.
    await client.cancelQueries();
    client.clear();
  }, [client]);

  const reload = useCallback(() => {
    const epoch = ++generation.current;
    setMe(null);
    setReady(false);
    void clear()
      .then(() => api<ApiResponse<Me>>("me"))
      .then((result) => {
        if (generation.current === epoch) {
          setMe(result.data);
          setError(null);
        }
      })
      .catch((reason) => {
        if (generation.current === epoch)
          setError(
            reason instanceof ApiError && reason.status === 401
              ? null
              : "The workspace could not be loaded. Check the Core API and retry.",
          );
      })
      .finally(() => {
        if (generation.current === epoch) setReady(true);
      });
  }, [clear]);

  useEffect(() => {
    const initial = setTimeout(reload, 0);
    channel.current = new BroadcastChannel("tokentrack-session");
    channel.current.onmessage = reload;
    const broadcast = channel.current;
    return () => {
      clearTimeout(initial);
      invalidatePendingSession();
      broadcast.close();
    };
  }, [reload, invalidatePendingSession]);

  const expire = useCallback(() => {
    generation.current++;
    void clear();
    setReady(true);
    setError("Your demo session expired. Choose an identity to continue.");
  }, [clear]);

  const refreshAccess = useCallback(
    async (allowExpansion = false) => {
      if (!me || busy.current) return;
      const epoch = generation.current;
      try {
        const result = await api<ApiResponse<Me>>("me");
        if (epoch !== generation.current) return;
        if (
          result.data.user.id !== me.user.id ||
          result.data.organization.id !== me.organization.id
        ) {
          reload();
          return;
        }
        if (
          result.data.access.scope_key !== me.access.scope_key &&
          !allowExpansion
        ) {
          const changedEpoch = ++generation.current;
          setReady(false);
          await clear();
          if (generation.current !== changedEpoch) return;
        }
        setMe(result.data);
        setReady(true);
      } catch (reason) {
        if (
          epoch === generation.current &&
          reason instanceof ApiError &&
          reason.status === 401
        )
          expire();
      }
    },
    [me, clear, expire, reload],
  );

  useEffect(() => {
    if (!me) return;
    const updates = new BroadcastChannel("tokentrack-projects");
    updates.onmessage = (event) => {
      if (event.data?.organizationId === me.organization.id) {
        void refreshAccess().then(() =>
          invalidateProjectViews(client, me.organization.id, me.user.id),
        );
      }
    };
    const focus = () => {
      if (document.visibilityState === "visible") void refreshAccess();
    };
    window.addEventListener("focus", focus);
    const interval = setInterval(focus, 15000);
    return () => {
      updates.close();
      window.removeEventListener("focus", focus);
      clearInterval(interval);
    };
  }, [me, refreshAccess, client]);

  async function change(id?: string) {
    if (busy.current) return;
    busy.current = true;
    const epoch = ++generation.current;
    setSwitching(true);
    setError(null);
    await clear();
    try {
      await api(id ? "demo/sessions" : "demo/session", {
        method: id ? "POST" : "DELETE",
        body: id ? { user_id: id } : {},
      });
      channel.current?.postMessage({ changed: true });
      if (id) {
        const result = await api<ApiResponse<Me>>("me");
        if (generation.current === epoch) setMe(result.data);
      }
      router.replace("/");
    } catch (reason) {
      if (generation.current === epoch)
        setError(
          reason instanceof Error
            ? reason.message
            : "Identity change failed. Try again.",
        );
    } finally {
      busy.current = false;
      setSwitching(false);
      if (generation.current === epoch) setReady(true);
    }
  }

  return (
    <SessionContext.Provider
      value={{
        me,
        ready,
        switching,
        error,
        switchIdentity: (id) => change(id),
        logout: () => change(),
        reload,
        expire,
        refreshAccess,
      }}
    >
      {children}
    </SessionContext.Provider>
  );
}

export function useSession() {
  const value = useContext(SessionContext);
  if (!value) throw new Error("SessionProvider is required");
  return value;
}
