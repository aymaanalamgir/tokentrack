import {
  ArrowDownToLine,
  ArrowRight,
  Bot,
  ChartNoAxesCombined,
  Check,
  Code2,
  FolderKanban,
  LockKeyhole,
  Terminal,
  Wallet,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { SystemStatus } from "@/components/system-status";

const workspaces = [
  {
    name: "Usage analytics",
    description:
      "Understand every token. See spending across your tools and models.",
    icon: ChartNoAxesCombined,
    tag: "VISIBILITY",
  },
  {
    name: "Project spending",
    description: "Connect AI costs to the projects and teams behind them.",
    icon: FolderKanban,
    tag: "ATTRIBUTION",
  },
  {
    name: "Budget management",
    description: "Give every team a clear view of its funding and limits.",
    icon: Wallet,
    tag: "CONTROL",
  },
  {
    name: "Agent intelligence",
    description: "Explore execution costs, retries, and cost per outcome.",
    icon: Bot,
    tag: "EFFICIENCY",
  },
];

export default function Overview() {
  return (
    <>
      <div className="mb-9 flex flex-wrap items-start justify-between gap-5">
        <div>
          <p className="mb-3 font-mono text-[10px] uppercase tracking-[.18em] text-muted-foreground">
            Workspace / overview
          </p>
          <h1 className="text-[28px] font-medium tracking-[-.045em] sm:text-[32px]">
            A clearer view of your AI spend.
          </h1>
          <p className="mt-3 max-w-lg text-sm leading-relaxed text-muted-foreground">
            One workspace to understand usage, connect costs, and make better
            decisions. Your foundation is taking shape.
          </p>
        </div>
        <Badge className="mt-1 gap-2 px-2.5 py-1.5 text-muted-foreground">
          <Code2 size={12} />
          SLICE 01 <span className="text-border">/</span> FOUNDATION
        </Badge>
      </div>
      <div className="mb-9 flex items-start gap-3 rounded-md border border-border bg-muted/40 px-4 py-3.5">
        <Terminal size={15} className="mt-0.5 shrink-0 text-muted-foreground" />
        <div>
          <p className="text-xs font-medium">
            Local environment. Real connections.
          </p>
          <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
            This workspace checks your running services. Analytics will arrive
            in future slices; no spending data is simulated here.
          </p>
        </div>
      </div>
      <SystemStatus />
      <section
        aria-labelledby="analytics-workspace"
        className="mt-11 border-t border-border pt-8"
      >
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 id="analytics-workspace" className="text-sm font-medium">
              Analytics workspace
            </h2>
            <p className="mt-1.5 text-xs text-muted-foreground">
              The next layer of your spending intelligence.
            </p>
          </div>
          <Badge className="text-muted-foreground">COMING SOON</Badge>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          {workspaces.map(({ name, description, icon: Icon, tag }) => (
            <article
              key={name}
              className="group rounded-lg border border-border bg-surface p-5 sm:p-6"
            >
              <div className="flex items-center justify-between">
                <Icon
                  size={19}
                  strokeWidth={1.5}
                  className="text-muted-foreground"
                />
                <LockKeyhole size={12} className="text-muted-foreground/60" />
              </div>
              <h3 className="mt-5 text-sm font-medium">{name}</h3>
              <p className="mt-2 max-w-xs text-xs leading-relaxed text-muted-foreground">
                {description}
              </p>
              <div className="mt-6 flex items-center justify-between border-t border-border pt-3 font-mono text-[9px] tracking-wider text-muted-foreground">
                <span>{tag}</span>
                <span className="flex items-center gap-1.5">
                  PLANNED
                  <ArrowRight size={12} />
                </span>
              </div>
            </article>
          ))}
        </div>
      </section>
      <section
        aria-labelledby="foundation"
        className="my-9 rounded-lg border border-border bg-surface"
      >
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-4">
          <h2
            id="foundation"
            className="flex items-center gap-2 text-xs font-medium"
          >
            <ArrowDownToLine size={14} className="text-muted-foreground" />A
            foundation with clear boundaries
          </h2>
          <span className="font-mono text-[9px] text-muted-foreground">
            LOCAL-FIRST ARCHITECTURE
          </span>
        </div>
        <div className="grid gap-5 p-5 sm:grid-cols-3">
          {[
            "Business logic in Rails",
            "Usage processing in Kotlin",
            "One database, two schemas",
          ].map((label) => (
            <div
              key={label}
              className="flex items-center gap-2 text-[11px] text-muted-foreground"
            >
              <Check size={12} className="text-success" />
              {label}
            </div>
          ))}
        </div>
      </section>
    </>
  );
}
