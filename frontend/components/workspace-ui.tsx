"use client";
import Link from "next/link";
import {
  ArrowRight,
  CircleAlert,
  FolderKanban,
  LoaderCircle,
  RefreshCw,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import type { Person, PersonLink, Project } from "@/lib/workspace-types";

export function humanize(value: string) {
  return value.replaceAll(/[._]/g, " ");
}
export function PageHeading({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children?: React.ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h1 className="text-xl font-medium tracking-tight">{title}</h1>
        {description && (
          <p className="mt-1.5 text-xs text-muted-foreground">{description}</p>
        )}
      </div>
      {children}
    </div>
  );
}
export function Panel({
  title,
  children,
  action,
  className = "",
}: {
  title: string;
  children: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`min-w-0 rounded-lg border border-border bg-surface ${className}`}
    >
      <div className="flex items-center justify-between gap-2 border-b border-border px-4 py-3">
        <h2 className="text-xs font-medium">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}
export function Skeleton({ label = "Loading workspace" }: { label?: string }) {
  return (
    <div
      role="status"
      aria-label={label}
      className="space-y-4"
      data-testid="workspace-skeleton"
    >
      <div className="h-7 w-44 animate-pulse rounded bg-muted" />
      <div className="grid grid-cols-3 gap-3">
        {[1, 2, 3].map((i) => (
          <div
            key={i}
            className="h-24 animate-pulse rounded border border-border bg-muted/50"
          />
        ))}
      </div>
      <div className="h-64 animate-pulse rounded-lg border border-border bg-muted/50" />
      <span className="sr-only">{label}</span>
    </div>
  );
}
export function ErrorState({
  error,
  retry,
}: {
  error: Error | null;
  retry: () => unknown;
}) {
  return (
    <div
      role="alert"
      className="rounded-lg border border-border bg-surface p-5"
    >
      <CircleAlert size={18} className="mb-3 text-danger" />
      <p className="text-sm">
        {error?.message ?? "The view could not be loaded"}
      </p>
      <Button variant="outline" onClick={() => void retry()} className="mt-4">
        <RefreshCw />
        Try again
      </Button>
    </div>
  );
}
export function EmptyState({
  title,
  description,
}: {
  title: string;
  description?: string;
}) {
  return (
    <div className="p-6 text-center">
      <FolderKanban size={19} className="mx-auto mb-3 text-muted-foreground" />
      <p className="text-sm">{title}</p>
      {description && (
        <p className="mx-auto mt-2 max-w-sm text-xs leading-relaxed text-muted-foreground">
          {description}
        </p>
      )}
    </div>
  );
}
export function Pending({ label }: { label: string }) {
  return (
    <span
      role="status"
      className="inline-flex items-center gap-2 text-xs text-muted-foreground"
    >
      <LoaderCircle size={13} className="animate-spin" />
      {label}
    </span>
  );
}
export function PersonName({ person }: { person: PersonLink }) {
  return person.can_view === false ? (
    <span>{person.name}</span>
  ) : (
    <Link href={`/people/${person.id}`} className="entity-link">
      {person.name}
    </Link>
  );
}
export function PeopleTable({
  people,
  context = "team",
}: {
  people: Person[];
  context?: "team" | "project";
}) {
  if (!people.length) return <EmptyState title="No people in this view" />;
  const showProjects =
    context === "team" && people.some((person) => !!person.project_assignments);
  return (
    <div className="overflow-x-auto">
      <table className="workspace-table">
        <thead>
          <tr>
            <th>Person</th>
            <th>Home team</th>
            <th>{context === "project" ? "Project role" : "Visibility"}</th>
            {showProjects && <th>Active projects</th>}
          </tr>
        </thead>
        <tbody>
          {people.map((person) => (
            <tr key={person.id}>
              <td>
                <div className="flex items-center gap-2.5">
                  <span className="avatar">
                    {person.name
                      .split(" ")
                      .slice(0, 2)
                      .map((s) => s[0])
                      .join("")}
                  </span>
                  <div>
                    <PersonName person={person} />
                    <p className="mt-0.5 text-[10px] text-muted-foreground">
                      {person.job_title}
                      {person.office ? ` · ${person.office}` : ""}
                    </p>
                  </div>
                </div>
              </td>
              <td>{person.primary_team?.name ?? "—"}</td>
              <td>
                <Badge className="text-muted-foreground">
                  {humanize(
                    context === "project"
                      ? (person.project_role ?? "contributor")
                      : person.visibility,
                  )}
                </Badge>
              </td>
              {showProjects && (
                <td>
                  <div className="flex max-w-64 flex-wrap gap-1.5">
                    {person.project_assignments
                      ?.filter((project) => project.status === "active")
                      .map((project) => (
                        <Link
                          key={project.id}
                          href={`/projects/${project.id}`}
                          className="rounded border border-border px-1.5 py-1 text-[9px] hover:bg-muted"
                        >
                          {project.name}
                        </Link>
                      )) ?? (
                      <span className="text-muted-foreground">Restricted</span>
                    )}
                  </div>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
export function ProjectList({ projects }: { projects: Project[] }) {
  if (!projects.length)
    return (
      <EmptyState
        title="No projects in this scope"
        description="Projects appear here when your access grants or team relationships permit them."
      />
    );
  return (
    <div className="divide-y divide-border">
      {projects.map((project) => (
        <Link
          key={project.id}
          href={`/projects/${project.id}`}
          className="flex items-center justify-between gap-3 px-4 py-3.5 hover:bg-muted/40"
        >
          <div className="min-w-0">
            <span className="text-xs font-medium">{project.name}</span>
            <p className="mt-1 text-[10px] text-muted-foreground">
              {project.contributor_count} contributors · {project.teams.length}{" "}
              teams
              {(project.member_role ?? project.my_role)
                ? ` · ${humanize(project.member_role ?? project.my_role ?? "")}`
                : ""}
            </p>
            <p className="mt-1 text-[10px] text-muted-foreground">
              Lead:{" "}
              {project.administrators
                ?.map((person) => person.name)
                .join(", ") || "Unassigned"}{" "}
              ·{" "}
              {project.teams
                .map((team) => team.name)
                .slice(0, 2)
                .join(", ")}
              {project.teams.length > 2 ? ` +${project.teams.length - 2}` : ""}
            </p>
          </div>
          <div className="flex shrink-0 items-center gap-3">
            <Badge className="text-muted-foreground">{project.status}</Badge>
            <ArrowRight size={12} className="text-muted-foreground" />
          </div>
        </Link>
      ))}
    </div>
  );
}

// ---- Shared layout primitives (UI refinement) ---------------------------------------------------------
// One metric tile pattern for every workspace: equal heights per row, mono value, one short context line.
// Tones are sparing accents: green for AI spend and healthy results, amber for attention, red for inefficiency or
// overspend. Most tiles stay neutral.
export type Tone = "default" | "spend" | "good" | "warning" | "danger";
export const toneText: Record<Tone, string> = { default: "", spend: "text-success", good: "text-success", warning: "text-warning", danger: "text-danger" };
export type Metric = { label: string; value: React.ReactNode; detail?: React.ReactNode; title?: string; tone?: Tone };
export function MetricGrid({ metrics, columns = 4, testId }: { metrics: Metric[]; columns?: 3 | 4 | 5 | 6; testId?: string }) {
  const cols = { 3: "lg:grid-cols-3", 4: "lg:grid-cols-4", 5: "lg:grid-cols-5", 6: "lg:grid-cols-6" }[columns];
  return (
    <div data-testid={testId} className={`grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-border bg-border ${cols}`}>
      {metrics.map((m) => (
        <div key={m.label} className="flex min-h-[92px] min-w-0 flex-col justify-between bg-surface p-4 odd:last:col-span-2 lg:odd:last:col-span-1" title={m.title}>
          <p className="flex items-center gap-1.5 truncate text-[10px] text-muted-foreground">{m.tone && m.tone !== "default" && <span aria-hidden="true" className={`size-1.5 shrink-0 rounded-full ${{ spend: "bg-success", good: "bg-success", warning: "bg-warning", danger: "bg-danger" }[m.tone]}`} />}{m.label}</p>
          <p className={`my-1.5 truncate font-mono text-xl ${toneText[m.tone ?? "default"]}`}>{m.value}</p>
          <p className="truncate text-[10px] text-muted-foreground">{m.detail ?? " "}</p>
        </div>
      ))}
    </div>
  );
}
// Accessible segmented tabs; the caller owns state (often the URL).
export function Segmented<T extends string>({ label, value, options, onChange, size = "md" }: { label: string; value: T; options: { value: T; label: string; count?: number }[]; onChange: (value: T) => void; size?: "sm" | "md" }) {
  return (
    <div role="tablist" aria-label={label} className="inline-flex max-w-full overflow-x-auto rounded-md border border-border bg-muted/40 p-0.5">
      {options.map((o) => (
        <button key={o.value} role="tab" type="button" aria-selected={o.value === value} onClick={() => onChange(o.value)}
          className={`whitespace-nowrap rounded px-2.5 ${size === "sm" ? "py-1 text-[11px]" : "py-1.5 text-xs"} ${o.value === value ? "bg-surface font-medium text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"}`}>
          {o.label}{o.count !== undefined && <span className="ml-1.5 font-mono text-[10px] text-muted-foreground">{o.count}</span>}
        </button>
      ))}
    </div>
  );
}
// Expands a preview list in place; renders nothing when everything already fits.
export function ShowMore({ total, shown, expanded, onToggle, noun }: { total: number; shown: number; expanded: boolean; onToggle: () => void; noun: string }) {
  if (total <= shown && !expanded) return null;
  return (
    <button type="button" onClick={onToggle} aria-expanded={expanded} className="w-full border-t border-border px-4 py-2.5 text-left text-[11px] text-muted-foreground hover:bg-muted/40 hover:text-foreground">
      {expanded ? `Show fewer ${noun}` : `Show all ${total} ${noun}`}
    </button>
  );
}
export function SearchInput({ value, onChange, label, placeholder }: { value: string; onChange: (value: string) => void; label: string; placeholder?: string }) {
  return (
    <input type="search" aria-label={label} placeholder={placeholder ?? label} value={value} onChange={(e) => onChange(e.target.value)}
      className="h-8 w-full min-w-0 rounded-md border border-border bg-surface px-2.5 text-xs text-foreground placeholder:text-muted-foreground sm:w-56" />
  );
}
