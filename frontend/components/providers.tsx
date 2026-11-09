"use client";
import { ThemeProvider } from "next-themes";
import { useState, type ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { SessionProvider } from "./session-provider";
import { NoticeProvider } from "./ui/notice-provider";

export function Providers({ children }: { children: ReactNode }) {
  const [client] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { retry: false, refetchOnWindowFocus: true, gcTime: 300000 },
        },
      }),
  );
  return (
    <ThemeProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      disableTransitionOnChange
    >
      <QueryClientProvider client={client}>
        <NoticeProvider>
          <SessionProvider>{children}</SessionProvider>
        </NoticeProvider>
      </QueryClientProvider>
    </ThemeProvider>
  );
}
