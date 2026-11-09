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

type Session = {
  me: Me | null;
  ready: boolean;
  switching: boolean;
  error: string | null;
  switchIdentity: (id: string) => Promise<void>;
  logout: () => Promise<void>;
  reload: () => void;
  expire: () => void;
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
