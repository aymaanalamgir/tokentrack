"use client";
import Link from "next/link";
import { ArrowDown, Check, LockKeyhole, ShieldCheck } from "lucide-react";
import { useSession } from "./session-provider";
import { useWorkspaceQuery } from "@/lib/use-workspace-query";
import type { Person, ReportingContext } from "@/lib/workspace-types";
import { Badge } from "./ui/badge";
import {
  EmptyState,
  ErrorState,
  humanize,
  PageHeading,
  Panel,
  PeopleTable,
  PersonName,
  ProjectList,
  Skeleton,
} from "./workspace-ui";

export function ProfileExplorer({ id }: { id?: string }) {
  const { me } = useSession();
  const userId = id ?? me?.user.id ?? "";
  const profile = useWorkspaceQuery<Person>(`users/${userId}`, !!userId);
  const reporting = useWorkspaceQuery<ReportingContext>(
    `users/${userId}/reporting-context`,
    !!profile.data?.data.can_view_reporting,
  );
  if (!me || profile.isPending)
    return <Skeleton label="Loading profile and access" />;
  if (profile.error)
    return <ErrorState error={profile.error} retry={profile.refetch} />;
  const person = profile.data.data;
  const own = person.id === me.user.id;
  const ancestry = reporting.data?.data.ancestors ?? [];
  const lineAncestors: ReportingContext["ancestors"] = [];
  const visited = new Set([person.id]);
  let reportId = person.id;
  while (true) {
    const edge = ancestry.find(
      (item) =>
        item.report_id === reportId &&
        item.relationship_type === "line_manager" &&
        !visited.has(item.id),
    );
    if (!edge) break;
    lineAncestors.push(edge);
    visited.add(edge.id);
    reportId = edge.id;
  }
  const otherRelationships = ancestry.filter(
    (item) => !lineAncestors.includes(item),
  );
  return (
    <>
      <PageHeading
        title={own ? "Profile & access" : person.name}
        description={
          own
            ? "Your identity, reporting position, and effective access grants."
            : `${me.organization.name} / authorized ${person.visibility} view`
        }
      >
        <Badge className="text-muted-foreground">
          <ShieldCheck size={11} />
          {person.visibility}
        </Badge>
      </PageHeading>
      <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
        <div className="min-w-0 space-y-5">
          <Panel title="Identity">
            <div className="p-5">
              <div className="flex items-center gap-3">
                <span className="avatar size-11! text-sm!">
                  {person.name
                    .split(" ")
                    .map((name) => name[0])
                    .join("")}
                </span>
                <div>
                  <h2 className="text-base font-medium">{person.name}</h2>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {person.job_title}
                  </p>
                </div>
              </div>
              <dl className="mt-5 space-y-3 text-xs">
                <div className="flex justify-between gap-3">
                  <dt className="text-muted-foreground">Job function</dt>
                  <dd>{person.job_function}</dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-muted-foreground">Organization</dt>
                  <dd>{me.organization.name}</dd>
                </div>
                {person.email && (
                  <div className="flex flex-wrap justify-between gap-3">
                    <dt className="text-muted-foreground">Email</dt>
                    <dd className="break-all font-mono text-[10px]">
                      {person.email}
                    </dd>
                  </div>
                )}
                <div className="flex justify-between gap-3">
                  <dt className="text-muted-foreground">Home team</dt>
                  <dd>
                    {person.primary_team ? (
                      <Link
                        href={`/organization/${person.primary_team.id}`}
                        className="entity-link"
                      >
                        {person.primary_team.name}
                      </Link>
                    ) : (
                      "Unassigned"
                    )}
                  </dd>
                </div>
              </dl>
              {person.memberships && (
                <div className="mt-5 flex flex-wrap gap-2 border-t border-border pt-4">
                  {person.memberships.map((team) => (
                    <Link key={team.id} href={`/organization/${team.id}`}>
                      <Badge className="text-muted-foreground">
                        {team.name}
                        {team.is_primary ? " · home" : " · additional"}
                      </Badge>
                    </Link>
                  ))}
                </div>
              )}
              {person.visibility === "directory" && (
                <p className="mt-5 border-t border-border pt-3 text-xs leading-relaxed text-muted-foreground">
                  This is a limited directory profile. Private contact details,
                  reporting context, and access grants are not included.
                </p>
              )}
            </div>
          </Panel>
          <Panel title="Project relationships">
            <ProjectList projects={person.projects ?? []} />
          </Panel>
        </div>
        <div className="min-w-0 space-y-5">
          <Panel title="Reporting position">
            {!person.can_view_reporting ? (
              <EmptyState
                title="Reporting context is restricted"
                description="Project coordination does not grant managerial access."
              />
            ) : reporting.isPending ? (
              <div className="p-4">
                <Skeleton label="Loading reporting chart" />
              </div>
            ) : reporting.error ? (
              <div className="p-4">
                <ErrorState error={reporting.error} retry={reporting.refetch} />
              </div>
            ) : (
              <div className="p-4">
                <div className="mx-auto flex max-w-sm flex-col items-center">
                  {[...lineAncestors].reverse().map((ancestor) => (
                    <div
                      key={ancestor.id}
                      className="flex w-full flex-col items-center"
                    >
                      <div className="w-full rounded-md border border-border bg-muted/30 px-3 py-3 text-xs">
                        <PersonName person={ancestor} />
                        <p className="mt-1 text-[10px] text-muted-foreground">
                          {ancestor.job_title}
                        </p>
                      </div>
                      <div className="flex items-center gap-1 py-2 text-[9px] text-muted-foreground">
                        <ArrowDown size={11} />
                        {humanize(ancestor.relationship_type)}
                      </div>
                    </div>
                  ))}
                  <div className="w-full rounded-md border border-foreground/50 bg-muted px-3 py-3 text-xs font-medium">
                    {person.name}
                    <p className="mt-1 text-[10px] font-normal text-muted-foreground">
                      {person.job_title}
                    </p>
                  </div>
                </div>
                {!!otherRelationships.length && (
                  <div className="mt-4 space-y-2 border-t border-border pt-3">
                    <p className="scope-label">
                      Additional reporting relationships
                    </p>
                    {otherRelationships.map((relationship, index) => (
                      <p key={index} className="text-[10px]">
                        <PersonName person={relationship} />
                        <span className="ml-2 text-muted-foreground">
                          {humanize(relationship.relationship_type)} for{" "}
                          {relationship.report_id === person.id
                            ? person.name
                            : (ancestry.find(
                                (item) => item.id === relationship.report_id,
                              )?.name ?? "a manager in this context")}
                        </span>
                      </p>
                    ))}
                  </div>
                )}
                {!!reporting.data?.data.direct_reports.length && (
                  <div className="mt-5 border-t border-border pt-4">
                    <p className="mb-3 text-[10px] text-muted-foreground">
                      Direct reports · managerial relationships
                    </p>
                    <PeopleTable people={reporting.data.data.direct_reports} />
                  </div>
                )}
                {!reporting.data?.data.ancestors.length &&
                  !reporting.data?.data.direct_reports.length && (
                    <p className="mt-3 text-center text-xs text-muted-foreground">
                      No reporting relationships assigned.
                    </p>
                  )}
              </div>
            )}
          </Panel>
          {own && (
            <Panel title="Access & permissions">
              <div className="space-y-5 p-4">
                <div className="space-y-2">
                  {me.access.grants.map((grant, index) => (
                    <div
                      key={index}
                      className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border px-3 py-2.5"
                    >
                      <span className="text-xs font-medium">
                        {humanize(grant.role)}
                      </span>
                      <span className="font-mono text-[10px] text-muted-foreground">
                        {grant.scope_name}
                      </span>
                    </div>
                  ))}
                </div>
                <div>
                  <p className="scope-label mb-3">Capabilities</p>
                  <ul className="space-y-2">
                    {me.access.capabilities.map((capability) => (
                      <li
                        key={capability}
                        className="flex items-center gap-2 text-[11px]"
                      >
                        <Check size={12} className="text-success" />
                        <span>{humanize(capability)}</span>
                      </li>
                    ))}
                  </ul>
                </div>
                <div className="border-t border-border pt-4">
                  <p className="scope-label mb-3">Restricted</p>
                  <ul className="space-y-2">
                    {me.access.restricted.map((restriction) => (
                      <li
                        key={restriction}
                        className="flex items-center gap-2 text-[11px] text-muted-foreground"
                      >
                        <LockKeyhole size={11} />
                        {restriction}
                      </li>
                    ))}
                  </ul>
                </div>
                <p className="border-t border-border pt-4 text-[10px] leading-relaxed text-muted-foreground">
                  A job function describes your work. Explicit roles define
                  authority within a self, team, project, or organization scope.
                  Financial approvals require separate future grants.
                </p>
              </div>
            </Panel>
          )}
        </div>
      </div>
    </>
  );
}
