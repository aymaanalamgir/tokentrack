"use client";
import Link from "next/link";
import { ArrowRight, Check, ChevronDown, ShieldCheck } from "lucide-react";
import { useSession } from "@/components/session-provider";
import { useWorkspaceQuery } from "@/lib/use-workspace-query";
import type { Overview } from "@/lib/workspace-types";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  ErrorState,
  humanize,
  PageHeading,
  Panel,
  PeopleTable,
  PersonName,
  ProjectList,
  Skeleton,
} from "@/components/workspace-ui";
import { SystemStatus } from "@/components/system-status";

const titles = {
  leadership: "Organization overview",
  manager: "Team workspace",
  project_lead: "Project workspace",
  employee: "My workspace",
};

export default function OverviewPage() {
  const { me } = useSession();
  const query = useWorkspaceQuery<Overview>("me/overview");
  if (!me || query.isPending) return <Skeleton />;
  if (query.error)
    return <ErrorState error={query.error} retry={query.refetch} />;
  const data = query.data.data;
  return (
    <>
      <PageHeading
        title={titles[data.persona]}
        description={`${me.organization.name} / ${me.user.name}`}
      >
        <Badge className="text-muted-foreground">
          <ShieldCheck size={11} />
          {humanize(data.persona)}
        </Badge>
      </PageHeading>
      <div
        className={`mb-6 grid grid-cols-2 gap-3 ${data.counts.length === 4 ? "xl:grid-cols-4" : "md:grid-cols-3"}`}
      >
        {data.counts.map((count) => (
          <div
            key={count.label}
            className="rounded-lg border border-border bg-surface px-4 py-4"
          >
            <p className="font-mono text-[10px] text-muted-foreground">
              {count.label}
            </p>
            <p className="mt-3 font-mono text-2xl tracking-tight">
              {count.value}
            </p>
          </div>
        ))}
      </div>
      {data.persona === "employee" ? (
        <div className="mb-5 grid gap-5 lg:grid-cols-2">
          <Panel
            title="My organizational position"
            action={
              <Link className="entity-link text-[10px]" href="/profile">
                Explore profile →
              </Link>
            }
          >
            <div className="space-y-4 p-4">
              <div>
                <p className="scope-label">Home team</p>
                {me.user.primary_team ? (
                  <Link
                    href={`/organization/${me.user.primary_team.id}`}
                    className="entity-link mt-1.5 block text-sm"
                  >
                    {me.user.primary_team.name}
                  </Link>
                ) : (
                  <p className="mt-2 text-xs text-muted-foreground">
                    No primary team assigned
                  </p>
                )}
              </div>
              <div>
                <p className="scope-label">Reporting manager</p>
                {me.user.managers?.length ? (
                  me.user.managers.map((manager) => (
                    <p className="mt-1.5 text-xs" key={manager.id}>
                      <PersonName person={manager} />
                      <span className="ml-2 text-muted-foreground">
                        {manager.job_title}
                      </span>
                    </p>
                  ))
                ) : (
                  <p className="mt-2 text-xs text-muted-foreground">
                    No reporting manager assigned
                  </p>
                )}
              </div>
              <p className="border-t border-border pt-3 text-xs text-muted-foreground">
                {me.user.job_title} · {me.user.job_function}
              </p>
            </div>
          </Panel>
          <Panel title="My access">
            <div className="space-y-3 p-4">
              {me.access.grants.map((grant, index) => (
                <p key={index} className="flex items-center gap-2 text-xs">
                  <Check size={12} className="text-success" />
                  {humanize(grant.role)}
                  <span className="ml-auto text-[10px] text-muted-foreground">
                    {grant.scope_name}
                  </span>
                </p>
              ))}
              <Link
                href="/profile"
                className="entity-link inline-flex items-center gap-2 pt-2 text-xs"
              >
                View capabilities and restrictions
                <ArrowRight size={12} />
              </Link>
            </div>
          </Panel>
        </div>
      ) : (
        <div className="mb-5 grid items-start gap-5 xl:grid-cols-[1fr_1.3fr]">
          <Panel
            title={
              data.persona === "leadership"
                ? "Organization structure"
                : data.persona === "manager"
                  ? "Managed teams"
                  : "Participating teams"
            }
            action={
              <Link href="/organization" className="entity-link text-[10px]">
                Explore →
              </Link>
            }
          >
            <div className="divide-y divide-border">
              {data.units
                .filter(
                  (unit) =>
                    !unit.parent_unit_id ||
                    !data.units.some(
                      (parent) => parent.id === unit.parent_unit_id,
                    ),
                )
                .map((unit) => (
                  <Link
                    href={`/organization/${unit.id}`}
                    key={unit.id}
                    className="flex items-center justify-between gap-3 px-4 py-3.5 hover:bg-muted/40"
                  >
                    <div>
                      <p className="text-xs font-medium">{unit.name}</p>
                      <p className="mt-1 font-mono text-[9px] text-muted-foreground">
                        {unit.unit_type}
                      </p>
                    </div>
                    <span className="font-mono text-[10px] text-muted-foreground">
                      {unit.subtree_member_count} people in subtree
                    </span>
                  </Link>
                ))}
            </div>
          </Panel>
          <Panel
            title={
              data.persona === "manager"
                ? "Team members & reports"
                : data.persona === "project_lead"
                  ? "Authorized collaborators"
                  : "People"
            }
          >
            <PeopleTable people={data.people} />
          </Panel>
        </div>
      )}
      <Panel
        title={
          data.persona === "employee" ? "My projects" : "Projects in your scope"
        }
        action={
          <Link href="/projects" className="entity-link text-[10px]">
            All projects →
          </Link>
        }
      >
        <ProjectList projects={data.projects} />
      </Panel>
      <div className="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-md border border-dashed border-border px-4 py-3 text-xs text-muted-foreground">
        <span>AI usage, spending, and budget intelligence</span>
        <div className="flex items-center gap-3">
          <Badge>COMING SOON</Badge>
          <Button asChild variant="ghost" className="h-6 px-1 text-[10px]">
            <Link href="/analytics">
              View workspace
              <ArrowRight />
            </Link>
          </Button>
        </div>
      </div>
      <details className="mt-7 border-t border-border pt-4">
        <summary className="flex cursor-pointer list-none items-center justify-between text-[11px] text-muted-foreground">
          System connectivity
          <ChevronDown size={13} />
        </summary>
        <div className="pt-5">
          <SystemStatus />
        </div>
      </details>
    </>
  );
}
