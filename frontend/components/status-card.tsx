import {
  Check,
  CircleAlert,
  LoaderCircle,
  Unplug,
  type LucideIcon,
} from "lucide-react";
import type { ServiceHealth } from "@/lib/health-check";
import { Badge } from "@/components/ui/badge";

const states = {
  connected: {
    label: "Connected",
    icon: Check,
    color: "text-success",
    background: "bg-success/10",
  },
  disconnected: {
    label: "Disconnected",
    icon: Unplug,
    color: "text-danger",
    background: "bg-danger/10",
  },
  loading: {
    label: "Checking",
    icon: LoaderCircle,
    color: "text-muted-foreground",
    background: "bg-muted",
  },
  error: {
    label: "Error",
    icon: CircleAlert,
    color: "text-danger",
    background: "bg-danger/10",
  },
};

export function StatusCard({
  title,
  subtitle,
  icon: Icon,
  health,
  index,
}: {
  title: string;
  subtitle: string;
  icon: LucideIcon;
  health: ServiceHealth;
  index: string;
}) {
  const state = states[health.state];
  const StateIcon = state.icon;
  return (
    <article className="rounded-lg border border-border bg-surface p-5 sm:p-6">
      <div className="flex items-center justify-between">
        <span className="flex size-9 items-center justify-center rounded-md border border-border text-muted-foreground">
          <Icon size={17} />
        </span>
        <span className="font-mono text-[10px] text-muted-foreground">
          {index}
        </span>
      </div>
      <h3 className="mt-5 text-sm font-medium">{title}</h3>
      <p className="mt-1 font-mono text-[10px] text-muted-foreground">
        {subtitle}
      </p>
      <div className="mt-6 border-t border-border pt-4">
        <Badge
          className={`${state.color} ${state.background} border-transparent`}
        >
          <StateIcon
            size={11}
            className={health.state === "loading" ? "animate-spin" : ""}
          />
          {state.label}
        </Badge>
        <p className="mt-2.5 min-h-4 text-[11px] text-muted-foreground">
          {health.message}
        </p>
      </div>
    </article>
  );
}
