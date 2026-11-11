"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTheme } from "next-themes";
import {
  Activity,
  AudioLines,
  Bot,
  Building2,
  ChartNoAxesCombined,
  ChevronDown,
  FolderKanban,
  Gauge,
  GitPullRequestArrow,
  LogOut,
  Menu,
  Moon,
  Settings2,
  ShieldCheck,
  Sun,
  UserRound,
  Users,
  Wallet,
  X,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tooltip } from "@/components/ui/tooltip";
import { useSession } from "@/components/session-provider";
import { DemoEntry, IdentityPicker } from "@/components/identity-picker";
import { humanize, Pending, Skeleton } from "@/components/workspace-ui";

const icons: Record<string, LucideIcon> = {
  overview: Gauge,
  projects: FolderKanban,
  teams: Users,
  organization: Building2,
  profile: UserRound,
  analytics: ChartNoAxesCombined,
  agents: Bot,
  budgets: Wallet,
  requests: GitPullRequestArrow,
  settings: Settings2,
};

function Brand() {
  return (
    <Link
      href="/"
      className="flex items-center gap-2.5 text-base font-semibold tracking-tight"
      aria-label="TokenTrack home"
    >
      <span className="brand-mark">
        <AudioLines size={18} />
      </span>
      TokenTrack<span className="text-muted-foreground">.</span>
    </Link>
  );
}

function Sidebar({ close }: { close?: () => void }) {
  const { me } = useSession();
  const pathname = usePathname();
  return (
    <>
      <div className="flex h-16 items-center justify-between px-5">
        <Brand />
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
      {me && (
        <>
          <Link
            href="/organization"
            onClick={close}
            className="mx-3 mb-5 flex items-center gap-2.5 rounded-md border border-border bg-surface p-3"
          >
            <Building2 size={15} className="shrink-0 text-muted-foreground" />
            <div className="min-w-0">
              <p className="truncate text-[11px] font-medium">
                {me.organization.name}
              </p>
              <p className="mt-1 font-mono text-[9px] text-muted-foreground">
                Fictional organization
              </p>
            </div>
          </Link>
          <nav aria-label="Main navigation" className="space-y-1 px-3">
            {me.access.navigation.map((item) => {
              const Icon = icons[item.icon] ?? Gauge;
              const active =
                item.href === "/"
                  ? pathname === "/"
                  : pathname.startsWith(item.href);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  onClick={close}
                  aria-current={active ? "page" : undefined}
                  className={`nav-item ${active ? "nav-active" : "hover:bg-muted/50"}`}
                >
                  <Icon size={15} />
                  <span>{item.label}</span>
                  {["/requests"].includes(
                    item.href,
                  ) && (
                    <span className="ml-auto text-[9px] opacity-60">soon</span>
                  )}
                </Link>
              );
            })}
          </nav>
          <div className="mx-4 mt-auto border-t border-border py-4">
            <p className="flex items-center gap-2 text-[10px] text-muted-foreground">
              <ShieldCheck size={12} />
              {humanize(me.access.persona)} scope
            </p>
            <p className="mt-2 font-mono text-[9px] text-muted-foreground">
              local / demo workspace
            </p>
          </div>
        </>
      )}
    </>
  );
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const { me, ready, switching, logout } = useSession();
  const { resolvedTheme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);
  const navigation = useRef<HTMLDialogElement>(null);
  const picker = useRef<HTMLDialogElement>(null);
  const pathname = usePathname();
  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);
  const dark = mounted && resolvedTheme === "dark";
  const title =
    me?.access.navigation.find(
      (item) => item.href !== "/" && pathname.startsWith(item.href),
    )?.label ?? (pathname.startsWith("/people/") ? "Person" : "Overview");

  return (
    <div className="min-h-screen">
      <a href="#main-content" className="skip-link">
        Skip to content
      </a>
      {me && (
        <>
          <aside className="fixed inset-y-0 left-0 z-30 hidden w-56 flex-col border-r border-border bg-sidebar lg:flex">
            <Sidebar />
          </aside>
          <dialog
            ref={navigation}
            aria-label="Navigation"
            className="mobile-dialog"
            onClick={(event) => {
              if (event.target === event.currentTarget)
                navigation.current?.close();
            }}
          >
            <div className="flex h-full w-[280px] max-w-[85vw] flex-col bg-sidebar">
              <Sidebar close={() => navigation.current?.close()} />
            </div>
          </dialog>
        </>
      )}
      <div className={me ? "lg:pl-56" : ""}>
        <header className="flex h-16 items-center justify-between gap-2 border-b border-border px-4 sm:px-7">
          <div className="flex min-w-0 items-center gap-2">
            {me ? (
              <>
                <Button
                  variant="ghost"
                  size="icon"
                  className="lg:hidden"
                  aria-label="Open navigation"
                  onClick={() => navigation.current?.showModal()}
                >
                  <Menu />
                </Button>
                <span className="font-semibold tracking-tight lg:hidden">
                  TokenTrack.
                </span>
                <span className="hidden font-mono text-[11px] text-muted-foreground lg:inline">
                  {title}
                </span>
              </>
            ) : (
              <Brand />
            )}
          </div>
          <div className="flex shrink-0 items-center gap-1.5 sm:gap-3">
            <Badge className="hidden text-muted-foreground sm:inline-flex">
              <span className="size-1.5 rounded-full bg-amber-500" />
              DEMO
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
            {me && (
              <>
                <button
                  aria-label="Switch identity"
                  aria-haspopup="dialog"
                  disabled={switching}
                  onClick={() => {
                    setPickerOpen(true);
                    picker.current?.showModal();
                  }}
                  className="flex items-center gap-2 rounded-md border border-border bg-surface px-2.5 py-1.5 hover:bg-muted"
                >
                  <span className="avatar size-6!">
                    {me.user.name
                      .split(" ")
                      .map((n) => n[0])
                      .join("")}
                  </span>
                  <span className="hidden text-left sm:block">
                    <span className="block text-[11px] font-medium">
                      {me.user.name}
                    </span>
                    <span className="block max-w-40 truncate font-mono text-[9px] text-muted-foreground">
                      {me.user.job_title}
                    </span>
                  </span>
                  <ChevronDown size={12} className="text-muted-foreground" />
                </button>
                <Tooltip label="Leave demo session">
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label="Sign out"
                    onClick={() => void logout()}
                    disabled={switching}
                  >
                    <LogOut />
                  </Button>
                </Tooltip>
              </>
            )}
          </div>
        </header>
        {me && (
          <div
            aria-label={`Active workspace: ${me.organization.name}. Viewing as ${me.user.name}`}
            className="flex min-w-0 items-center justify-between gap-3 border-b border-border bg-surface px-4 py-2 text-[10px] lg:hidden"
          >
            <span
              title={me.organization.name}
              className="min-w-0 truncate text-muted-foreground"
            >
              {me.organization.name}
            </span>
            <span title={me.user.name} className="shrink-0 font-mono">
              {me.user.name}
            </span>
          </div>
        )}
        <main
          id="main-content"
          className="mx-auto max-w-[1440px] px-4 py-6 sm:px-7 sm:py-8 xl:px-9"
        >
          {!ready ? (
            <Skeleton label="Restoring demo session" />
          ) : switching ? (
            <div className="space-y-5">
              <Pending label="Switching identity…" />
              <Skeleton />
            </div>
          ) : !me ? (
            <DemoEntry />
          ) : (
            <div key={`${me.organization.id}:${me.user.id}`}>{children}</div>
          )}
        </main>
        <footer className="mx-4 mt-6 flex flex-wrap justify-between gap-2 border-t border-border py-4 font-mono text-[9px] text-muted-foreground sm:mx-7 xl:mx-9">
          <span className="flex items-center gap-1.5">
            <Activity size={11} />
            TokenTrack · Local demo
          </span>
          <span>Fictional demo data · Modeled metered AI expenditure</span>
        </footer>
      </div>
      {me && (
        <dialog
          ref={picker}
          aria-label="Switch demo identity"
          className="identity-dialog"
          onClose={() => setPickerOpen(false)}
          onClick={(event) => {
            if (event.target === event.currentTarget) picker.current?.close();
          }}
        >
          <div className="flex items-center justify-between border-b border-border px-5 py-4">
            <h2 className="text-sm font-medium">Switch identity</h2>
            <Button
              variant="ghost"
              size="icon"
              aria-label="Close identity switcher"
              onClick={() => picker.current?.close()}
            >
              <X />
            </Button>
          </div>
          <div className="p-5">
            {pickerOpen && (
              <IdentityPicker onSelected={() => picker.current?.close()} />
            )}
          </div>
        </dialog>
      )}
    </div>
  );
}
