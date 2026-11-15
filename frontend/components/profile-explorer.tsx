"use client";
import Link from "next/link";
import { useState } from "react";
import { ArrowRight, Check, LockKeyhole, ShieldCheck } from "lucide-react";
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
  ShowMore,
  Skeleton,
} from "./workspace-ui";

export function ProfileExplorer({ id }: { id?: string }) {
  const { me } = useSession();
  const [allReports, setAllReports] = useState(false);
  const [allProjects, setAllProjects] = useState(false);
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
  const reports = reporting.data?.data.direct_reports ?? [];
  const projects = person.projects ?? [];
  const initials = person.name.split(" ").map((name) => name[0]).join("");
  const reportingBody = !person.can_view_reporting ? (
    <EmptyState title="Reporting context is restricted" description="Project coordination does not grant managerial access." />
  ) : reporting.isPending ? (
    <div className="p-4"><Skeleton label="Loading reporting chart" /></div>
  ) : reporting.error ? (
    <div className="p-4"><ErrorState error={reporting.error} retry={reporting.refetch} /></div>
  ) : (
    <ol className="space-y-1.5 p-4" aria-label="Line management chain">
      {[...lineAncestors].reverse().map((ancestor) => (
        <li key={ancestor.id} className="rounded-md border border-border px-3 py-2 text-xs">
          <PersonName person={ancestor} />
          <p className="mt-0.5 truncate text-[10px] text-muted-foreground">{ancestor.job_title} · {humanize(ancestor.relationship_type)}</p>
        </li>
      ))}
      <li className="rounded-md border border-foreground/40 bg-muted px-3 py-2 text-xs font-medium">
        {person.name}
        <p className="mt-0.5 truncate text-[10px] font-normal text-muted-foreground">{person.job_title}</p>
      </li>
      {!!otherRelationships.length && (
        <li className="pt-2 text-[10px] text-muted-foreground">
          <p className="scope-label mb-1">Additional relationships</p>
          {otherRelationships.map((relationship, index) => (
            <p key={index}>
              <PersonName person={relationship} /> · {humanize(relationship.relationship_type)} for{" "}
              {relationship.report_id === person.id ? person.name : (ancestry.find((item) => item.id === relationship.report_id)?.name ?? "a manager in this context")}
            </p>
          ))}
        </li>
      )}
      {!lineAncestors.length && !reports.length && <li className="pt-1 text-center text-xs text-muted-foreground">No reporting relationships assigned.</li>}
    </ol>
  );
  return (
    <>
      <PageHeading
        title={own ? "Profile & access" : person.name}
        description={own ? "Your identity, reporting position, and effective access grants." : `${me.organization.name} / authorized ${person.visibility} view`}
      >
        <Badge className="text-muted-foreground"><ShieldCheck size={11} />{person.visibility}</Badge>
      </PageHeading>
      <div className="space-y-5">
        <section className="rounded-lg border border-border bg-surface p-5" aria-label="Identity" data-testid="profile-identity">
          <div className="flex flex-wrap items-start gap-4">
            <span className="avatar size-12! text-sm!">{initials}</span>
            <div className="min-w-0 flex-1">
              <h2 className="text-base font-medium">{person.name}</h2>
              <p className="mt-1 text-xs text-muted-foreground">
                {person.job_title}{person.office ? ` · ${person.office}` : ""}
                {person.primary_team && <> · <Link href={`/organization/${person.primary_team.id}`} className="entity-link">{person.primary_team.name}</Link></>}
              </p>
              <div className="mt-2.5 flex flex-wrap gap-1.5">
                {own && <Badge className="text-muted-foreground">{humanize(me.access.persona)}</Badge>}
                {own && me.access.grants.some((g) => g.role === "financial_operator") && <Badge className="text-muted-foreground">financial operator</Badge>}
                {person.status && <Badge className={person.status === "active" ? "text-success" : "text-muted-foreground"}>{person.status}</Badge>}
              </div>
            </div>
            <dl className="grid w-full gap-x-8 gap-y-2 text-xs sm:grid-cols-3 lg:w-auto lg:min-w-[420px]">
              <div><dt className="text-[10px] text-muted-foreground">Job function</dt><dd className="mt-0.5">{person.job_function}</dd></div>
              <div><dt className="text-[10px] text-muted-foreground">Organization</dt><dd className="mt-0.5">{me.organization.name}</dd></div>
              {person.email && <div className="min-w-0"><dt className="text-[10px] text-muted-foreground">Email</dt><dd className="mt-0.5 break-all font-mono text-[10px]">{person.email}</dd></div>}
            </dl>
          </div>
          {person.visibility === "directory" && (
            <p className="mt-4 border-t border-border pt-3 text-xs text-muted-foreground">Limited directory profile: private contact details, reporting context, and access grants are not included.</p>
          )}
        </section>
        <div className="grid gap-5 lg:grid-cols-2">
          <Panel title="Organization" className="h-full">
            <div className="grid sm:grid-cols-2">
              <div className="border-b border-border sm:border-b-0 sm:border-r"><p className="scope-label px-4 pt-4">Reporting line</p>{reportingBody}</div>
              <div><p className="scope-label px-4 pt-4">Teams</p>
                <ul className="space-y-1.5 p-4">
                  {(person.memberships ?? (person.primary_team ? [{ ...person.primary_team, is_primary: true, membership_type: "home_team" }] : [])).map((team) => (
                    <li key={team.id}><Link href={`/organization/${team.id}`} className="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2 text-xs hover:bg-muted/40"><span className="min-w-0 truncate">{team.name}</span><span className="shrink-0 text-[10px] text-muted-foreground">{team.is_primary ? "home" : humanize(team.membership_type)}</span></Link></li>
                  ))}
                  {!person.memberships?.length && !person.primary_team && <li className="text-xs text-muted-foreground">No team membership recorded.</li>}
                </ul>
              </div>
            </div>
          </Panel>
          <Panel title="Project relationships" className="h-full" action={<span className="text-[10px] text-muted-foreground">{projects.length}</span>}>
            <ProjectList projects={allProjects ? projects : projects.slice(0, 3)} />
            <ShowMore total={projects.length} shown={3} expanded={allProjects} onToggle={() => setAllProjects(!allProjects)} noun="projects" />
          </Panel>
        </div>
        {!!reports.length && (
          <Panel title={`Direct reports · ${reports.length}`} action={<Link href="/people" className="entity-link inline-flex items-center gap-1 text-[11px]">Open People<ArrowRight size={11} /></Link>}>
            <PeopleTable people={allReports ? reports : reports.slice(0, 5)} />
            <ShowMore total={reports.length} shown={5} expanded={allReports} onToggle={() => setAllReports(!allReports)} noun="direct reports" />
          </Panel>
        )}
        {own && (
          <Panel title="Access & permissions">
            <div className="grid gap-px bg-border md:grid-cols-3">
              <div className="bg-surface p-4">
                <p className="scope-label mb-3">Role assignments</p>
                <ul className="space-y-2">
                  {me.access.grants.map((grant, index) => (
                    <li key={index} className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border px-3 py-2">
                      <span className="text-xs font-medium">{humanize(grant.role)}</span>
                      <span className="font-mono text-[10px] text-muted-foreground">{grant.scope_name}</span>
                    </li>
                  ))}
                </ul>
              </div>
              <div className="bg-surface p-4">
                <p className="scope-label mb-3">Capabilities</p>
                <ul className="space-y-1.5">
                  {me.access.capabilities.map((capability) => (
                    <li key={capability} className="flex items-center gap-2 text-[11px]"><Check size={12} className="shrink-0 text-success" /><span>{humanize(capability)}</span></li>
                  ))}
                </ul>
              </div>
              <div className="bg-surface p-4">
                <p className="scope-label mb-3">Restricted</p>
                <ul className="space-y-1.5">
                  {me.access.restricted.map((restriction) => (
                    <li key={restriction} className="flex items-start gap-2 text-[11px] text-muted-foreground"><LockKeyhole size={11} className="mt-0.5 shrink-0" />{restriction}</li>
                  ))}
                </ul>
                <p className="mt-4 border-t border-border pt-3 text-[10px] leading-relaxed text-muted-foreground">Job functions describe work. Explicit roles define authority within a self, team, project, or organization scope.</p>
              </div>
            </div>
          </Panel>
        )}
      </div>
    </>
  );
}
