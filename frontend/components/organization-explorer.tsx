"use client";
import { useState } from "react";
import Link from "next/link";
import { Building2, RefreshCw } from "lucide-react";
import { useSession } from "./session-provider";
import { useWorkspaceQuery } from "@/lib/use-workspace-query";
import type { Organization, Unit } from "@/lib/workspace-types";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import {
  EmptyState,
  ErrorState,
  PageHeading,
  Panel,
  Pending,
  PeopleTable,
  PersonName,
  ProjectList,
  Skeleton,
} from "./workspace-ui";

function UnitBranch({
  unit,
  units,
  selected,
  select,
}: {
  unit: Unit;
  units: Unit[];
  selected: string;
  select: (id: string) => void;
}) {
  const children = units.filter((item) => item.parent_unit_id === unit.id);
  const label = (
    <button
      className={`flex w-full min-w-0 items-center gap-2 rounded px-2 py-2 text-left text-[11px] ${selected === unit.id ? "bg-muted font-medium" : "hover:bg-muted/50"}`}
      onClick={() => select(unit.id)}
    >
      <Building2 size={12} className="shrink-0 text-muted-foreground" />
      <span className="truncate">{unit.name}</span>
      <span className="ml-auto font-mono text-[9px] text-muted-foreground">
        {unit.subtree_member_count}
      </span>
    </button>
  );
  return children.length ? (
    <details open>
      <summary className="cursor-pointer marker:text-muted-foreground">
        {label}
      </summary>
      <div className="tree-line">
        {children.map((child) => (
          <UnitBranch
            key={child.id}
            unit={child}
            units={units}
            selected={selected}
            select={select}
          />
        ))}
      </div>
    </details>
  ) : (
    label
  );
}

export function OrganizationExplorer({
  initialId = "",
  teams = false,
}: {
  initialId?: string;
  teams?: boolean;
}) {
  const { me } = useSession();
  const [selected, setSelected] = useState(initialId);
  const [search, setSearch] = useState("");
  const [offset, setOffset] = useState(0);
  const [rosterOffset, setRosterOffset] = useState(0);
  function selectUnit(id: string) {
    setSelected(id);
    setRosterOffset(0);
  }
  const managed =
    me?.access.capabilities.includes("teams.read.managed") &&
    !me.access.capabilities.includes("organization.read");
  const unitsQuery = useWorkspaceQuery<Unit[]>(
    `organizational-units?limit=100&offset=${offset}${managed ? "&managed=true" : ""}`,
  );
  const orgQuery = useWorkspaceQuery<Organization>(
    `organizations/${me?.organization.id}`,
  );
  const units = unitsQuery.data?.data ?? [];
  const selectedId = selected || units[0]?.id || "";
  const detail = useWorkspaceQuery<Unit>(
    `organizational-units/${selectedId}?limit=20&offset=${rosterOffset}`,
    !!selectedId,
  );
  if (!me || unitsQuery.isPending || orgQuery.isPending)
    return <Skeleton label="Loading organization chart" />;
  if (unitsQuery.error || orgQuery.error)
    return (
      <ErrorState
        error={unitsQuery.error ?? orgQuery.error}
        retry={() => {
          void unitsQuery.refetch();
          void orgQuery.refetch();
        }}
      />
    );
  if (teams && !me.access.navigation.some((item) => item.href === "/teams"))
    return (
      <EmptyState
        title="Team management is outside your access scope"
        description="Your permitted directory context remains available in My organization."
      />
    );
  const roots = units.filter(
    (unit) =>
      !unit.parent_unit_id ||
      !units.some((parent) => parent.id === unit.parent_unit_id),
  );
  const org = orgQuery.data.data;
  return (
    <>
      <PageHeading
        title={teams ? "Teams" : me.organization.name}
        description={
          me.access.persona === "leadership"
            ? "Explore departments, teams, and reporting relationships."
            : "Your authorized teams and collaboration context."
        }
      >
        <Button
          variant="outline"
          onClick={() => {
            void unitsQuery.refetch();
            void detail.refetch();
          }}
          disabled={unitsQuery.isFetching || detail.isFetching}
        >
          <RefreshCw />
          Refresh
        </Button>
      </PageHeading>
      <div className="mb-5 flex flex-wrap gap-4 font-mono text-[10px] text-muted-foreground">
        <span>{org.employee_count} visible people</span>
        <span>{org.unit_count} visible units</span>
        <span>{org.project_count} authorized projects</span>
        <Badge className="ml-auto">{org.scope}</Badge>
      </div>
      <div className="grid items-start gap-5 lg:grid-cols-[280px_minmax(0,1fr)]">
        <Panel title="Organizational structure">
          <div className="p-3">
            <input
              aria-label="Find a team"
              className="workspace-input mb-3"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Find a team…"
            />
            <div className="max-h-[560px] overflow-auto">
              {search
                ? units
                    .filter((unit) =>
                      unit.name.toLowerCase().includes(search.toLowerCase()),
                    )
                    .map((unit) => (
                      <button
                        key={unit.id}
                        onClick={() => selectUnit(unit.id)}
                        className="block w-full rounded p-2 text-left text-xs hover:bg-muted"
                      >
                        {unit.name}
                      </button>
                    ))
                : roots.map((unit) => (
                    <UnitBranch
                      key={unit.id}
                      unit={unit}
                      units={units}
                      selected={selectedId}
                      select={selectUnit}
                    />
                  ))}
            </div>
            {!units.length && (
              <EmptyState title="No organizational units in scope" />
            )}
            {(unitsQuery.data.meta?.total ?? 0) > 100 && (
              <div className="mt-3 flex gap-2">
                <Button
                  variant="outline"
                  disabled={!offset}
                  onClick={() => setOffset(Math.max(0, offset - 100))}
                >
                  Previous
                </Button>
                <Button
                  variant="outline"
                  disabled={offset + 100 >= (unitsQuery.data.meta?.total ?? 0)}
                  onClick={() => setOffset(offset + 100)}
                >
                  Next units
                </Button>
              </div>
            )}
          </div>
        </Panel>
        <div className="min-w-0 space-y-5">
          {!selectedId ? (
            <EmptyState title="Select a team to explore" />
          ) : detail.isPending ? (
            <Skeleton label="Loading selected unit" />
          ) : detail.error ? (
            <ErrorState error={detail.error} retry={detail.refetch} />
          ) : (
            <>
              <Panel
                title={detail.data.data.name}
                action={
                  detail.isFetching ? (
                    <Pending label="Refreshing" />
                  ) : (
                    <Badge className="mr-4 text-muted-foreground">
                      {detail.data.data.roster_visibility} view
                    </Badge>
                  )
                }
              >
                <div className="space-y-3 p-4">
                  <p className="text-xs leading-relaxed text-muted-foreground">
                    {detail.data.data.description}
                  </p>
                  <div className="flex flex-wrap gap-4 text-xs">
                    <span>
                      {detail.data.data.member_count} direct members ·{" "}
                      {detail.data.data.subtree_member_count} people in subtree
                    </span>
                    {detail.data.data.managers.map((manager) => (
                      <span key={manager.id} className="text-muted-foreground">
                        Manager: <PersonName person={manager} />
                      </span>
                    ))}
                  </div>
                  {!!detail.data.data.children?.length && (
                    <div className="flex flex-wrap gap-2 border-t border-border pt-3">
                      {detail.data.data.children.map((child) => (
                        <button
                          key={child.id}
                          onClick={() => selectUnit(child.id)}
                          className="rounded border border-border px-2 py-1.5 text-[10px] hover:bg-muted"
                        >
                          {child.name} →
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </Panel>
              <Panel title="Team roster">
                <PeopleTable people={detail.data.data.members ?? []} />
                {detail.data.data.members_meta &&
                  detail.data.data.members_meta.total >
                    detail.data.data.members_meta.limit && (
                    <div className="flex items-center justify-between border-t border-border p-3 text-[10px] text-muted-foreground">
                      <Link href="/people" className="entity-link">
                        Search people →
                      </Link>
                      <div className="flex gap-2">
                        <Button
                          variant="ghost"
                          disabled={!rosterOffset}
                          onClick={() =>
                            setRosterOffset(Math.max(0, rosterOffset - 20))
                          }
                        >
                          Previous
                        </Button>
                        <Button
                          variant="ghost"
                          disabled={
                            rosterOffset + 20 >=
                            detail.data.data.members_meta.total
                          }
                          onClick={() => setRosterOffset(rosterOffset + 20)}
                        >
                          Next
                        </Button>
                      </div>
                    </div>
                  )}
              </Panel>
              <Panel title="Associated projects">
                <ProjectList projects={detail.data.data.projects ?? []} />
              </Panel>
              <p className="text-[10px] leading-relaxed text-muted-foreground">
                Directory views include only permitted collaboration details.
                Reporting management and project participation carry separate
                authority.{" "}
                <Link href="/profile" className="entity-link">
                  Review your access →
                </Link>
              </p>
            </>
          )}
        </div>
      </div>
    </>
  );
}
