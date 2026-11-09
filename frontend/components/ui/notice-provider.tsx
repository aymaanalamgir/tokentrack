"use client";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { Check, X } from "lucide-react";

const NoticeContext = createContext<(message: string) => void>(() => {});
export function NoticeProvider({ children }: { children: ReactNode }) {
  const [notice, setNotice] = useState<{ message: string; id: number } | null>(
    null,
  );
  const notify = useCallback(
    (message: string) => setNotice({ message, id: Date.now() }),
    [],
  );
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(null), 5000);
    return () => clearTimeout(timer);
  }, [notice]);
  return (
    <NoticeContext.Provider value={notify}>
      {children}
      {notice && (
        <div
          role="status"
          className="fixed bottom-5 right-4 z-[100] flex max-w-[calc(100vw-32px)] items-center gap-3 rounded-md border border-border bg-surface px-4 py-3 text-xs shadow-sm"
        >
          <Check size={14} className="text-success" />
          {notice.message}
          <button
            aria-label="Dismiss notification"
            onClick={() => setNotice(null)}
          >
            <X size={13} />
          </button>
        </div>
      )}
    </NoticeContext.Provider>
  );
}
export function useNotice() {
  return useContext(NoticeContext);
}
