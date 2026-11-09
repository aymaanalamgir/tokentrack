"use client";
import { useRef, useState } from "react";
import Link from "next/link";
import { useQueryClient } from "@tanstack/react-query";
import { Filter, Pencil, RefreshCw, X } from "lucide-react";
import { api } from "@/lib/api-client";
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
  PeopleTable,
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
        <Button
          variant="outline"
          disabled={query.isFetching}
          onClick={() => void query.refetch()}
        >
          <RefreshCw />
          Refresh
        </Button>
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

function EditProject({
  project,
  done,
}: {
  project: Project;
  done: () => void;
}) {
  const client = useQueryClient();
  const { me } = useSession();
  const [name, setName] = useState(project.name);
  const [description, setDescription] = useState(project.description);
  const [status, setStatus] = useState(project.status);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <form
      className="space-y-4 p-5"
      onSubmit={async (event) => {
        event.preventDefault();
        if (pending) return;
        setPending(true);
        setError(null);
        try {
          await api(`projects/${project.id}`, {
            method: "PATCH",
            body: { project: { name, description, status } },
          });
          await client.invalidateQueries({
            predicate: (query) =>
              query.queryKey[0] === me?.organization.id &&
              query.queryKey[1] === me?.user.id &&
              typeof query.queryKey[2] === "string" &&
              (query.queryKey[2].startsWith("projects") ||
                query.queryKey[2] === "me/overview" ||
                query.queryKey[2].startsWith("organizational-units/") ||
                query.queryKey[2].startsWith("users/")),
          });
          done();
        } catch (reason) {
          setError(
            reason instanceof Error ? reason.message : "Project update failed",
          );
        } finally {
          setPending(false);
        }
      }}
    >
      <label className="block text-xs">
        Name
        <input
          aria-label="Name"
          required
          maxLength={120}
          className="workspace-input mt-2"
          value={name}
          onChange={(event) => setName(event.target.value)}
          disabled={pending}
        />
      </label>
      <label className="block text-xs">
        Description
        <textarea
          aria-label="Description"
          maxLength={5000}
          className="workspace-input mt-2"
          value={description}
          onChange={(event) => setDescription(event.target.value)}
          disabled={pending}
        />
      </label>
      <label className="block text-xs">
        Status
        <select
          aria-label="Status"
          className="workspace-input mt-2"
          value={status}
          onChange={(event) => setStatus(event.target.value)}
          disabled={pending}
        >
          {["active", "planned", "archived"].map((value) => (
            <option key={value}>{value}</option>
          ))}
        </select>
      </label>
      {error && (
        <p role="alert" className="text-xs text-danger">
          {error}
        </p>
      )}
      <div className="flex items-center justify-between gap-3">
        <p className="text-[10px] text-muted-foreground">
          Updates project metadata only.
        </p>
        <Button type="submit" disabled={pending}>
          {pending ? <Pending label="Saving…" /> : "Save changes"}
        </Button>
      </div>
    </form>
  );
}

export function ProjectDetail({ id }: { id: string }) {
  const [offset, setOffset] = useState(0);
  const query = useWorkspaceQuery<Project>(
    `projects/${id}?limit=25&offset=${offset}`,
  );
  const dialog = useRef<HTMLDialogElement>(null);
  const [editing, setEditing] = useState(false);
  if (query.isPending) return <Skeleton label="Loading project" />;
  if (query.error)
    return <ErrorState error={query.error} retry={query.refetch} />;
  const project = query.data.data;
  return (
    <>
      <PageHeading title={project.name} description={project.description}>
        <div className="flex items-center gap-3">
          <Badge className="text-muted-foreground">{project.status}</Badge>
          {project.can_edit && (
            <Button
              variant="outline"
              onClick={() => {
                setEditing(true);
                dialog.current?.showModal();
              }}
            >
              <Pencil />
              Edit project
            </Button>
          )}
        </div>
      </PageHeading>
      <div className="mb-5 grid gap-5 lg:grid-cols-2">
        <Panel title="Ownership & scope">
          <div className="space-y-4 p-4">
            <div>
              <p className="scope-label mb-2">Project owner / lead</p>
              {project.leads.map((person) => (
                <p key={person.id} className="text-xs">
                  <PersonName person={person} />
                </p>
              ))}
            </div>
            <div className="flex items-center justify-between gap-3 border-t border-border pt-3 text-xs">
              <span className="text-muted-foreground">My membership</span>
              <span>{humanize(project.my_role ?? "Scoped observer")}</span>
            </div>
            <div className="border-t border-border pt-3">
              <p className="scope-label mb-2">Explicit project grants</p>
              {project.role_assignments?.map((grant, index) => (
                <p key={index} className="mt-1 text-[11px]">
                  <PersonName person={grant.user} />
                  <span className="ml-2 text-muted-foreground">
                    {humanize(grant.role)}
                  </span>
                </p>
              ))}
            </div>
            <p className="border-t border-border pt-3 text-[10px] leading-relaxed text-muted-foreground">
              Project participation is separate from line management. Editing
              requires an explicit project grant; no financial approval
              authority is granted here.
            </p>
          </div>
        </Panel>
        <Panel title="Participating teams">
          <div className="flex flex-wrap gap-2 p-4">
            {project.teams.map((team) => (
              <Link
                key={team.id}
                href={`/organization/${team.id}`}
                className="rounded-md border border-border px-3 py-2 text-xs hover:bg-muted"
              >
                {team.name}
                <span className="ml-2 font-mono text-[9px] text-muted-foreground">
                  {team.unit_type}
                </span>
              </Link>
            ))}
          </div>
        </Panel>
      </div>
      <Panel title={`Contributors · ${project.contributor_count}`}>
        <PeopleTable people={project.members ?? []} context="project" />
        {!!project.members_meta && project.members_meta.total > 25 && (
          <div className="flex justify-end gap-2 border-t border-border p-3">
            <Button
              variant="ghost"
              disabled={!offset}
              onClick={() => setOffset(Math.max(0, offset - 25))}
            >
              Previous contributors
            </Button>
            <Button
              variant="ghost"
              disabled={offset + 25 >= project.members_meta.total}
              onClick={() => setOffset(offset + 25)}
            >
              Next contributors
            </Button>
          </div>
        )}
      </Panel>
      <div className="mt-5">
        <Panel title="Project spending">
          <EmptyState
            title="Spending analytics are coming soon"
            description="Project costs, funding, and AI usage will appear when those services are implemented."
          />
        </Panel>
      </div>
      <dialog
        ref={dialog}
        aria-label="Edit project metadata"
        className="identity-dialog"
        onClose={() => setEditing(false)}
      >
        <div className="flex items-center justify-between border-b border-border px-5 py-3">
          <h2 className="text-sm font-medium">Edit project</h2>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Close project editor"
            onClick={() => dialog.current?.close()}
          >
            <X />
          </Button>
        </div>
        {editing && (
          <EditProject project={project} done={() => dialog.current?.close()} />
        )}
      </dialog>
    </>
  );
}
