"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useTheme } from "next-themes";
import {
  Activity,
  ArrowUpRight,
  AudioLines,
  Blocks,
  Bot,
  Boxes,
  Building2,
  ChartNoAxesCombined,
  ChevronDown,
  CircleHelp,
  Command,
  FolderKanban,
  Gauge,
  GitPullRequestArrow,
  Menu,
  Moon,
  Settings2,
  Sun,
  Wallet,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tooltip } from "@/components/ui/tooltip";

const navigation = [
  { label: "Overview", icon: Gauge, href: "/" },
  { label: "Analytics", icon: ChartNoAxesCombined },
  { label: "Projects", icon: FolderKanban },
  { label: "Tools & Models", icon: Boxes },
  { label: "Agents", icon: Bot },
  { label: "Budgets", icon: Wallet },
  { label: "Requests", icon: GitPullRequestArrow },
  { label: "Organization", icon: Building2 },
  { label: "Settings", icon: Settings2 },
];

function SidebarContent({ close }: { close?: () => void }) {
  return (
    <>
      <div className="flex h-[72px] items-center justify-between px-6">
        <Link
          href="/"
          onClick={close}
          className="flex items-center gap-2.5 text-lg font-semibold tracking-tight"
          aria-label="TokenTrack home"
        >
          <span className="brand-mark">
            <AudioLines size={19} strokeWidth={2.3} />
          </span>
          TokenTrack<span className="text-muted-foreground">.</span>
        </Link>
        {close && (
          <Button
            variant="ghost"
            size="icon"
            aria-label="Close navigation"
            onClick={close}
          >
            <X />
          </Button>
        )}
      </div>
      <div className="mx-4 mb-7 flex items-center gap-3 rounded-md border border-border bg-surface p-3">
        <span className="flex size-8 items-center justify-center rounded border border-border bg-muted">
          <Blocks size={15} />
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-xs font-medium">Local workspace</p>
          <p className="mt-1 font-mono text-[10px] text-muted-foreground">
            development
          </p>
        </div>
        <ChevronDown
          size={13}
          className="text-muted-foreground"
          aria-hidden="true"
        />
      </div>
      <p className="px-6 font-mono text-[10px] uppercase tracking-[.16em] text-muted-foreground">
        Workspace
      </p>
      <nav aria-label="Main navigation" className="mt-3 space-y-1 px-3">
        {navigation.map(({ label, icon: Icon, href }, index) => (
          <div
            key={label}
            className={index === 7 ? "mt-6! border-t border-border pt-4" : ""}
          >
            {href ? (
              <Link
                href={href}
                onClick={close}
                aria-current="page"
                className="nav-item nav-active"
              >
                <Icon size={16} />
                <span>{label}</span>
                <span className="ml-auto size-1 rounded-full bg-foreground" />
              </Link>
            ) : (
              <Tooltip label={`${label} is planned for a future slice`}>
                <span className="block">
                  <button
                    disabled
                    className="nav-item w-full cursor-not-allowed opacity-45"
                  >
                    <Icon size={16} />
                    <span>{label}</span>
                    <span className="ml-auto text-[9px]">soon</span>
                  </button>
                </span>
              </Tooltip>
            )}
          </div>
        ))}
      </nav>
      <div className="mt-auto p-4">
        <div className="rounded-md border border-border p-3.5">
          <div className="flex items-center gap-2 text-xs font-medium">
            <Command size={13} />
            Built for what comes next
          </div>
          <p className="mt-2 text-[11px] leading-relaxed text-muted-foreground">
            Your AI spending workspace starts with a connected foundation.
          </p>
        </div>
        <div className="mt-5 flex items-center justify-between px-1 font-mono text-[10px] text-muted-foreground">
          <span className="flex items-center gap-1.5">
            <Activity size={12} />
            local / slice_01
          </span>
          <span>v0.1.0</span>
        </div>
      </div>
    </>
  );
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const { resolvedTheme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);
  const dark = mounted && resolvedTheme === "dark";

  return (
    <div className="min-h-screen">
      <a href="#main-content" className="skip-link">
        Skip to content
      </a>
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-border bg-sidebar lg:flex">
        <SidebarContent />
      </aside>
      <dialog
        ref={dialog}
        aria-label="Navigation"
        className="mobile-dialog"
        onClick={(event) => {
          if (event.target === event.currentTarget) dialog.current?.close();
        }}
      >
        <div className="flex h-full w-[280px] max-w-[85vw] flex-col bg-sidebar">
          <SidebarContent close={() => dialog.current?.close()} />
        </div>
      </dialog>
      <div className="lg:pl-60">
        <header className="flex h-[72px] items-center justify-between gap-3 border-b border-border px-5 sm:px-9">
          <div className="flex items-center gap-3">
            <Button
              variant="ghost"
              size="icon"
              className="lg:hidden"
              aria-label="Open navigation"
              onClick={() => dialog.current?.showModal()}
            >
              <Menu />
            </Button>
            <span className="text-sm font-semibold tracking-tight lg:hidden">
              TokenTrack.
            </span>
            <span className="hidden text-muted-foreground lg:block">
              <Blocks size={15} />
            </span>
            <span className="hidden text-border sm:block">/</span>
            <span className="hidden font-mono text-xs sm:inline">Overview</span>
          </div>
          <div className="flex items-center gap-3 sm:gap-5">
            <Badge className="text-muted-foreground">
              <span className="size-1.5 rounded-full bg-amber-500" />
              <span className="hidden sm:inline">DEMO</span>
              <span className="sm:hidden">DEMO</span>
              <span className="hidden md:inline">ENVIRONMENT</span>
            </Badge>
            <Tooltip
              label={dark ? "Switch to light theme" : "Switch to dark theme"}
            >
              <Button
                variant="ghost"
                size="icon"
                aria-label={
                  dark ? "Switch to light theme" : "Switch to dark theme"
                }
                onClick={() => setTheme(dark ? "light" : "dark")}
                suppressHydrationWarning
              >
                {dark ? <Sun /> : <Moon />}
              </Button>
            </Tooltip>
            <div className="flex items-center gap-2.5 border-l border-border pl-4">
              <span className="flex size-7 items-center justify-center rounded-full border border-border bg-muted font-mono text-[10px]">
                DV
              </span>
              <div className="hidden sm:block">
                <p className="text-[11px] font-medium">Developer</p>
                <p className="font-mono text-[9px] text-muted-foreground">
                  local identity
                </p>
              </div>
            </div>
          </div>
        </header>
        <main
          id="main-content"
          className="mx-auto max-w-[1440px] px-5 py-9 sm:px-9 sm:py-11 xl:px-12"
        >
          {children}
        </main>
        <footer className="mx-5 flex flex-wrap items-center justify-between gap-3 border-t border-border py-5 font-mono text-[10px] text-muted-foreground sm:mx-9 xl:mx-12">
          <span>
            TokenTrack <span className="mx-2 text-border">/</span> AI spending
            intelligence
          </span>
          <span className="flex items-center gap-1.5">
            <CircleHelp size={12} />
            Local foundation · No usage data collected
            <ArrowUpRight size={11} />
          </span>
        </footer>
      </div>
    </div>
  );
}
