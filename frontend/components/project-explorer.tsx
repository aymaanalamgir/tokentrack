"use client";
import { useState } from "react";
import { CreateProjectAction } from "./project-forms";
import { ProjectWorkspace } from "./project-workspace";
import Link from "next/link";
import { Filter, RefreshCw } from "lucide-react";
import { useWorkspaceQuery } from "@/lib/use-workspace-query";
import type { Project, Unit } from "@/lib/workspace-types";
import { useSession } from "./session-provider";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import {
  EmptyState,
  ErrorState,
  humanize,
  PageHeading,
  Panel,
  Pending,
  PersonName,
  Skeleton,
} from "./workspace-ui";

export function ProjectDirectory() {
  const [status, setStatus] = useState("");
  const [department, setDepartment] = useState("");
  const [membership, setMembership] = useState("");
  const [search, setSearch] = useState("");
  const [offset, setOffset] = useState(0);
  const units = useWorkspaceQuery<Unit[]>("organizational-units?limit=100");
  const parameters = new URLSearchParams({
    status,
    department,
    membership,
    q: search,
    limit: "20",
    offset: String(offset),
  });
  const query = useWorkspaceQuery<Project[]>(`projects?${parameters}`);
  const { me } = useSession();
  return (
    <>
      <PageHeading
        title="Projects"
        description="Initiatives and contributors within your authorized scope."
      >
        <div className="flex items-center gap-2">
          <CreateProjectAction />
          <Button
            variant="outline"
            disabled={query.isFetching}
            onClick={() => void query.refetch()}
          >
            <RefreshCw />
            Refresh
          </Button>
        </div>
      </PageHeading>
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Filter size={13} className="mr-1 text-muted-foreground" />
        <input
          aria-label="Find projects"
          className="workspace-input w-full! sm:w-52!"
          placeholder="Find a project…"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setOffset(0);
          }}
        />
        <select
          aria-label="Project status"
          className="workspace-input w-auto!"
          value={status}
          onChange={(event) => {
            setStatus(event.target.value);
            setOffset(0);
          }}
        >
          <option value="">All statuses</option>
          {["active", "planned", "archived"].map((value) => (
            <option key={value} value={value}>
              {value}
            </option>
          ))}
        </select>
        <select
          aria-label="Project department"
          className="workspace-input max-w-full! w-auto!"
          value={department}
          onChange={(event) => {
            setDepartment(event.target.value);
            setOffset(0);
          }}
        >
          <option value="">All teams</option>
          {units.data?.data.map((unit) => (
            <option key={unit.id} value={unit.id}>
              {unit.name}
            </option>
          ))}
        </select>
        <select
          aria-label="Project membership"
          className="workspace-input w-auto!"
          value={membership}
          onChange={(event) => {
            setMembership(event.target.value);
            setOffset(0);
          }}
        >
          <option value="">All authorized</option>
          <option value="mine">My memberships</option>
          {me?.access.capabilities.includes("projects.read.led") && (
            <option value="led">Projects I lead</option>
          )}
        </select>
        {query.isFetching && <Pending label="Updating projects" />}
      </div>
      {query.isPending ? (
        <Skeleton label="Loading projects" />
      ) : query.error ? (
        <ErrorState error={query.error} retry={query.refetch} />
      ) : (
        <Panel
          title={`${query.data.meta?.total ?? query.data.data.length} projects`}
        >
          {!query.data.data.length ? (
            <EmptyState
              title="No matching projects"
              description="Try another status, team, or membership filter."
            />
          ) : (
            <div className="overflow-x-auto">
              <table className="workspace-table">
                <thead>
                  <tr>
                    <th>Project</th>
                    <th>Status</th>
                    <th>Lead</th>
                    <th>Contributors</th>
                    <th>Teams</th>
                    <th>My role</th>
                  </tr>
                </thead>
                <tbody>
                  {query.data.data.map((project) => (
                    <tr key={project.id}>
                      <td>
                        <Link
                          href={`/projects/${project.id}`}
                          className="entity-link"
                        >
                          {project.name}
                        </Link>
                      </td>
                      <td>
                        <Badge className="text-muted-foreground">
                          {project.status}
                        </Badge>
                      </td>
                      <td>
                        {project.leads.map((lead) => (
                          <p key={lead.id}>
                            <PersonName person={lead} />
                          </p>
                        ))}
                      </td>
                      <td className="font-mono">{project.contributor_count}</td>
                      <td>
                        <div className="flex max-w-64 flex-wrap gap-1">
                          {project.teams.map((team) => (
                            <Link
                              key={team.id}
                              href={`/organization/${team.id}`}
                              className="text-[10px] text-muted-foreground hover:underline"
                            >
                              {team.name}
                              <span className="px-1 opacity-40">/</span>
                            </Link>
                          ))}
                        </div>
                      </td>
                      <td className="font-mono text-[10px]">
                        {humanize(project.my_role ?? "observer")}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="flex items-center justify-between border-t border-border p-3 text-[10px] text-muted-foreground">
            <span>Authorization applies before filters and pagination.</span>
            <div className="flex gap-2">
              <Button
                variant="ghost"
                disabled={offset === 0}
                onClick={() => setOffset(Math.max(0, offset - 20))}
              >
                Previous
              </Button>
              <Button
                variant="ghost"
                disabled={offset + 20 >= (query.data.meta?.total ?? 0)}
                onClick={() => setOffset(offset + 20)}
              >
                Next
              </Button>
            </div>
          </div>
        </Panel>
      )}
    </>
  );
}

export function ProjectDetail({ id }: { id: string }) {
  return <ProjectWorkspace id={id} />;
}
