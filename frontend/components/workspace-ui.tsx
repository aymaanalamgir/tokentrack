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
  return (
    <div className="overflow-x-auto">
      <table className="workspace-table">
        <thead>
          <tr>
            <th>Person</th>
            <th>Home team</th>
            <th>{context === "project" ? "Project role" : "Visibility"}</th>
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
