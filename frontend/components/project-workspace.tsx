"use client";
import { useState } from "react";
import Link from "next/link";
import {
  Archive,
  ArrowRightLeft,
  ChevronDown,
  LockKeyhole,
  Pencil,
  Plus,
  RefreshCw,
  Trash2,
} from "lucide-react";
import { useWorkspaceQuery } from "@/lib/use-workspace-query";
import { useProjectMutation } from "@/lib/use-project-mutation";
import type {
  Person,
  Project,
  ProjectGroup,
  ProjectMembership,
} from "@/lib/workspace-types";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import {
  EmployeePicker,
  MutationError,
  ProjectDialog,
  ProjectForm,
} from "./project-forms";
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

const roles = ["owner", "lead", "contributor", "reviewer"];

function ProjectContributors({ project }: { project: Project }) {
  const [search, setSearch] = useState("");
  const [state, setState] = useState("active");
  const [offset, setOffset] = useState(0);
  const [action, setAction] = useState<"add" | "role" | "remove" | null>(null);
  const [person, setPerson] = useState<Person | null>(null);
  const [selected, setSelected] = useState<ProjectMembership | null>(null);
  const [role, setRole] = useState("contributor");
  const mutation = useProjectMutation();
  const actualState = project.permissions.history ? state : "active";
  const query = useWorkspaceQuery<ProjectMembership[]>(
    `projects/${project.id}/memberships?${new URLSearchParams({ q: search, state: actualState, limit: "20", offset: String(offset) })}`,
  );
  const close = () => {
    if (!mutation.pending) {
      setAction(null);
      setPerson(null);
      setSelected(null);
    }
  };
  const title =
    action === "add"
      ? "Add contributor"
      : action === "role"
        ? "Edit contributor role"
        : "Remove contributor";
  return (
    <>
      <Panel
        title={`Contributors · ${project.contributor_count}`}
        action={
          project.permissions.members_manage && (
            <Button
              variant="ghost"
              className="mr-2 h-7 text-[10px]"
              onClick={() => {
                mutation.clearError();
                setAction("add");
                setRole("contributor");
              }}
            >
              <Plus />
              Add contributor
            </Button>
          )
        }
      >
        <div className="flex flex-wrap items-center gap-2 border-b border-border p-3">
          <input
            aria-label="Find contributors"
            className="workspace-input max-w-xs"
            placeholder="Search name or job function…"
            value={search}
            onChange={(event) => {
              setSearch(event.target.value);
              setOffset(0);
            }}
          />
          {project.permissions.history && (
            <select
              aria-label="Membership history"
              className="workspace-input w-auto!"
              value={state}
              onChange={(event) => {
                setState(event.target.value);
                setOffset(0);
              }}
            >
              <option value="active">Current members</option>
              <option value="past">Past members</option>
              <option value="all">All periods</option>
            </select>
          )}
          {query.isFetching && <Pending label="Updating contributors" />}
        </div>
        {query.isPending ? (
          <div className="p-4">
            <Skeleton label="Loading contributors" />
          </div>
        ) : query.error ? (
          <ErrorState error={query.error} retry={query.refetch} />
        ) : (
          <>
            {!query.data.data.length ? (
              <EmptyState title="No matching contributors" />
            ) : (
              <div className="overflow-x-auto">
                <table className="workspace-table">
                  <thead>
                    <tr>
                      <th>Employee</th>
                      <th>Home team</th>
                      <th>Project role</th>
                      <th>Membership</th>
                      {project.permissions.members_manage && <th>Actions</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {query.data.data.map((membership) => (
                      <tr key={membership.id}>
                        <td>
                          <PersonName person={membership.user} />
                          <p className="mt-1 text-[10px] text-muted-foreground">
                            {membership.user.job_function}
                          </p>
                        </td>
                        <td>
                          {membership.user.primary_team?.name ?? "Unassigned"}
                        </td>
                        <td>
                          <div className="flex flex-wrap gap-1">
                            <Badge>{membership.project_role}</Badge>
                            {membership.administrator && (
                              <Badge className="text-success">
                                ADMIN GRANT
                              </Badge>
                            )}
                          </div>
                        </td>
                        <td>
                          <Badge className="text-muted-foreground">
                            {membership.status}
                          </Badge>
                          <p className="mt-1.5 font-mono text-[9px] text-muted-foreground">
                            Joined{" "}
                            {new Date(
                              membership.joined_at,
                            ).toLocaleDateString()}
                            {membership.left_at
                              ? ` · Left ${new Date(membership.left_at).toLocaleDateString()}`
                              : ""}
                          </p>
                        </td>
                        {project.permissions.members_manage && (
                          <td>
                            <div className="flex items-center gap-1">
                              {membership.can_update && (
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  aria-label={`Edit role for ${membership.user.name}`}
                                  disabled={mutation.pending}
                                  onClick={() => {
                                    setSelected(membership);
                                    setRole(membership.project_role);
                                    mutation.clearError();
                                    setAction("role");
                                  }}
                                >
                                  <Pencil />
                                </Button>
                              )}
                              {membership.can_remove ? (
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  aria-label={`Remove ${membership.user.name}`}
                                  disabled={mutation.pending}
                                  onClick={() => {
                                    setSelected(membership);
                                    mutation.clearError();
                                    setAction("remove");
                                  }}
                                >
                                  <Trash2 />
                                </Button>
                              ) : (
                                membership.status === "active" &&
                                membership.administrator && (
                                  <span className="inline-flex items-center gap-1 text-[9px] text-muted-foreground">
                                    <LockKeyhole size={10} />
                                    Last admin
                                  </span>
                                )
                              )}
                            </div>
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <div className="flex items-center justify-between gap-2 border-t border-border p-3 text-[10px] text-muted-foreground">
              <span>
                {query.data.meta?.total ?? 0}{" "}
                {actualState === "active"
                  ? "current memberships"
                  : "membership periods"}
              </span>
              <div className="flex gap-2">
                <Button
                  variant="ghost"
                  disabled={!offset}
                  onClick={() => setOffset(Math.max(0, offset - 20))}
                >
                  Previous members
                </Button>
                <Button
                  variant="ghost"
                  disabled={offset + 20 >= (query.data.meta?.total ?? 0)}
                  onClick={() => setOffset(offset + 20)}
                >
                  Next members
                </Button>
              </div>
            </div>
          </>
        )}
      </Panel>
      <ProjectDialog
        open={!!action}
        close={close}
        title={title}
        busy={mutation.pending}
      >
        <form
          className="space-y-4 p-5"
          onSubmit={async (event) => {
            event.preventDefault();
            const result =
              action === "add"
                ? await mutation.run(
                    `projects/${project.id}/memberships`,
                    "POST",
                    { membership: { user_id: person?.id, project_role: role } },
                    "Contributor assigned",
                  )
                : action === "role"
                  ? await mutation.run(
                      `projects/${project.id}/memberships/${selected?.id}`,
                      "PATCH",
                      { membership: { project_role: role } },
                      "Contributor role updated",
                    )
                  : await mutation.run(
                      `projects/${project.id}/memberships/${selected?.id}`,
                      "DELETE",
                      {},
                      "Contributor removed",
                    );
            if (result) {
              setAction(null);
              setPerson(null);
              setSelected(null);
            }
          }}
        >
          {action === "add" && (
            <EmployeePicker
              path={`projects/${project.id}/eligible-users`}
              selected={person}
              select={setPerson}
              disabled={mutation.pending}
            />
          )}
          {action === "role" && (
            <p className="text-sm">{selected?.user.name}</p>
          )}
          {action === "remove" ? (
            <p className="text-xs leading-relaxed text-muted-foreground">
              Remove{" "}
              <strong className="text-foreground">{selected?.user.name}</strong>{" "}
              from this project? This ends their membership and revokes any
              project administration. The history is retained and they may
              rejoin later.
            </p>
          ) : (
            <>
              <label className="block text-xs">
                Collaboration role
                <select
                  aria-label="Collaboration role"
                  className="workspace-input mt-2"
                  value={role}
                  disabled={mutation.pending}
                  onChange={(event) => setRole(event.target.value)}
                >
                  {roles.map((value) => (
                    <option key={value}>{value}</option>
                  ))}
                </select>
              </label>
              <p className="text-[10px] leading-relaxed text-muted-foreground">
                Owner and Lead are collaboration labels. They do not grant
                administration; use Transfer ownership to change authority.
              </p>
            </>
          )}
          <MutationError mutation={mutation} />
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={close}
              disabled={mutation.pending}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={mutation.pending || (action === "add" && !person)}
            >
              {mutation.pending ? (
                <Pending label="Saving…" />
              ) : action === "remove" ? (
                "Confirm removal"
              ) : action === "add" ? (
                "Assign contributor"
              ) : (
                "Save role"
              )}
            </Button>
          </div>
        </form>
      </ProjectDialog>
    </>
  );
}

function TeamBucket({
  project,
  group,
}: {
  project: Project;
  group: ProjectGroup;
}) {
  const [open, setOpen] = useState(false);
  const [offset, setOffset] = useState(0);
  const members = useWorkspaceQuery<ProjectMembership[]>(
    `projects/${project.id}/memberships?${new URLSearchParams({ team: group.unit.id, limit: "10", offset: String(offset) })}`,
    open,
  );
  return (
    <details
      className="border-b border-border last:border-b-0"
      onToggle={(event) => setOpen(event.currentTarget.open)}
    >
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3 text-xs">
        <span className="font-medium">{group.unit.name}</span>
        <span className="flex items-center gap-3 font-mono text-[10px] text-muted-foreground">
          {group.member_count} contributors
          <ChevronDown size={12} />
        </span>
      </summary>
      {open && (
        <div className="border-t border-border bg-muted/20 px-4 py-3">
          {members.isPending ? (
            <Pending label="Loading team contributors…" />
          ) : members.error ? (
            <ErrorState error={members.error} retry={members.refetch} />
          ) : (
            <>
              <div className="space-y-3">
                {members.data?.data.map((member) => (
                  <div
                    key={member.id}
                    className="flex flex-wrap items-center justify-between gap-2 text-xs"
                  >
                    <div>
                      <PersonName person={member.user} />
                      <p className="mt-1 text-[10px] text-muted-foreground">
                        {member.user.job_title}
                      </p>
                    </div>
                    <div className="flex gap-1">
                      <Badge>{member.project_role}</Badge>
                      {member.administrator && (
                        <Badge className="text-success">ADMIN GRANT</Badge>
                      )}
                    </div>
                  </div>
                ))}
              </div>
              {group.member_count > 10 && (
                <div className="mt-3 flex justify-end gap-2">
                  <Button
                    variant="ghost"
                    disabled={!offset}
                    onClick={() => setOffset(Math.max(0, offset - 10))}
                  >
                    Previous group
                  </Button>
                  <Button
                    variant="ghost"
                    disabled={offset + 10 >= group.member_count}
                    onClick={() => setOffset(offset + 10)}
                  >
                    Next group
                  </Button>
                </div>
              )}
            </>
          )}
        </div>
      )}
    </details>
  );
}

export function ProjectWorkspace({ id }: { id: string }) {
  const query = useWorkspaceQuery<Project>(`projects/${id}`);
  const groups = useWorkspaceQuery<ProjectGroup[]>(
    `projects/${id}/team-groups`,
  );
  const [dialog, setDialog] = useState<
    "edit" | "transfer" | "lifecycle" | null
  >(null);
  const [target, setTarget] = useState<Person | null>(null);
  const [nextStatus, setNextStatus] = useState("");
  const mutation = useProjectMutation();
  if (query.isPending) return <Skeleton label="Loading project" />;
  if (query.error)
    return <ErrorState error={query.error} retry={query.refetch} />;
  const project = query.data.data;
  const close = () => {
    if (!mutation.pending) {
      setDialog(null);
      setTarget(null);
    }
  };
  return (
    <>
      <PageHeading title={project.name} description={project.description}>
        <div className="flex flex-wrap items-center gap-2">
          <Badge className="text-muted-foreground">{project.status}</Badge>
          {project.permissions.edit && (
            <Button
              variant="outline"
              onClick={() => {
                mutation.clearError();
                setDialog("edit");
              }}
            >
              <Pencil />
              Edit project
            </Button>
          )}
          {project.permissions.lifecycle_manage && (
            <>
              <Button
                variant="outline"
                onClick={() => {
                  setNextStatus(
                    project.status === "archived"
                      ? project.restore_status
                      : "archived",
                  );
                  mutation.clearError();
                  setDialog("lifecycle");
                }}
              >
                <Archive />
                {project.status === "archived"
                  ? "Restore project"
                  : "Archive project"}
              </Button>
              {project.status !== "archived" && (
                <Button
                  variant="ghost"
                  onClick={() => {
                    setNextStatus(
                      project.status === "planned" ? "active" : "planned",
                    );
                    mutation.clearError();
                    setDialog("lifecycle");
                  }}
                >
                  {project.status === "planned"
                    ? "Activate project"
                    : "Move to planned"}
                </Button>
              )}
            </>
          )}
        </div>
      </PageHeading>
      <div className="mb-5 flex flex-wrap items-center gap-4 rounded-md border border-border bg-surface px-4 py-3 text-[11px]">
        <span>
          <strong className="font-mono">{project.contributor_count}</strong>{" "}
          contributors
        </span>
        <span>
          <strong className="font-mono">{project.teams.length}</strong> home
          teams
        </span>
        <span className="text-muted-foreground">
          My role: {humanize(project.my_role ?? "scoped observer")}
        </span>
        <Button
          variant="ghost"
          className="ml-auto h-6 text-[10px]"
          onClick={() => void query.refetch()}
          disabled={query.isFetching}
        >
          <RefreshCw />
          Refresh project
        </Button>
      </div>
      <div className="mb-5 grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)]">
        <Panel
          title="Project coordination"
          action={
            project.permissions.ownership_transfer && (
              <Button
                variant="ghost"
                className="mr-2 h-7 text-[10px]"
                onClick={() => {
                  mutation.clearError();
                  setDialog("transfer");
                }}
              >
                <ArrowRightLeft />
                Transfer ownership
              </Button>
            )
          }
        >
          <div className="space-y-4 p-4">
            <div>
              <p className="scope-label mb-2">Authorized administration</p>
              {project.administrators.map((admin) => (
                <p key={admin.id} className="mt-1 text-xs">
                  <PersonName person={admin} />
                </p>
              ))}
            </div>
            <div className="border-t border-border pt-3">
              <p className="scope-label mb-2">Collaboration owners / leads</p>
              {project.leads.map((lead) => (
                <p key={lead.id} className="mt-1 text-xs">
                  <PersonName person={lead} />
                </p>
              ))}
            </div>
            <p className="border-t border-border pt-3 text-[10px] leading-relaxed text-muted-foreground">
              Project coordination is separate from reporting management.
              Collaboration labels grant no system or financial authority.
              {project.status === "archived"
                ? " Archived projects preserve history and must be restored before staffing or editing."
                : ""}
            </p>
          </div>
        </Panel>
        <Panel title="Cross-functional team">
          <p className="border-b border-border px-4 py-3 text-[10px] text-muted-foreground">
            Grouped by each contributor’s primary home team. Expand a group to
            inspect project relationships.
          </p>
          {groups.isPending ? (
            <div className="p-4">
              <Pending label="Loading participating teams…" />
            </div>
          ) : groups.error ? (
            <ErrorState error={groups.error} retry={groups.refetch} />
          ) : groups.data.data.length ? (
            groups.data.data.map((group) => (
              <TeamBucket key={group.unit.id} project={project} group={group} />
            ))
          ) : (
            <EmptyState title="No active contributors" />
          )}
        </Panel>
      </div>
      <ProjectContributors project={project} />
      <div className="mt-5 flex flex-wrap items-center justify-between gap-2 rounded-md border border-dashed border-border px-4 py-3 text-[11px] text-muted-foreground">
        <span>Project AI spending and efficiency</span>
        <Badge>COMING SOON</Badge>
      </div>
      <ProjectDialog
        open={!!dialog}
        close={close}
        title={
          dialog === "edit"
            ? "Edit project metadata"
            : dialog === "transfer"
              ? "Transfer project ownership"
              : "Change project lifecycle"
        }
        busy={mutation.pending}
      >
        {dialog === "edit" ? (
          <ProjectForm
            project={project}
            mutation={mutation}
            onSaved={() => setDialog(null)}
          />
        ) : (
          <form
            className="space-y-4 p-5"
            onSubmit={async (event) => {
              event.preventDefault();
              const result =
                dialog === "transfer"
                  ? await mutation.run(
                      `projects/${id}/transfer-ownership`,
                      "POST",
                      { user_id: target?.id },
                      "Project ownership transferred",
                    )
                  : await mutation.run(
                      `projects/${id}`,
                      "PATCH",
                      { project: { status: nextStatus } },
                      nextStatus === "archived"
                        ? "Project archived"
                        : "Project lifecycle updated",
                    );
              if (result) {
                setDialog(null);
                setTarget(null);
              }
            }}
          >
            {dialog === "transfer" ? (
              <>
                <EmployeePicker
                  path={`projects/${id}/eligible-users?include_members=true`}
                  selected={target}
                  select={setTarget}
                  disabled={mutation.pending}
                />
                <p className="text-xs leading-relaxed text-muted-foreground">
                  The selected person receives an explicit project
                  administration grant. All previous project administration
                  grants are revoked, and previous collaboration leads remain
                  contributors. Reporting relationships stay unchanged.
                </p>
              </>
            ) : (
              <p className="text-xs leading-relaxed text-muted-foreground">
                Change this project from <strong>{project.status}</strong> to{" "}
                <strong>{nextStatus}</strong>? Archiving preserves its ID and
                memberships. Archived projects are read-only until restored.
              </p>
            )}
            <MutationError mutation={mutation} />
            <div className="flex justify-end gap-2">
              <Button
                type="button"
                variant="outline"
                disabled={mutation.pending}
                onClick={close}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={
                  mutation.pending || (dialog === "transfer" && !target)
                }
              >
                {mutation.pending ? (
                  <Pending label="Applying change…" />
                ) : dialog === "transfer" ? (
                  "Confirm transfer"
                ) : (
                  "Confirm status change"
                )}
              </Button>
            </div>
          </form>
        )}
      </ProjectDialog>
      <Link
        href="/projects"
        className="entity-link mt-5 inline-block text-[10px] text-muted-foreground"
      >
        ← Back to projects
      </Link>
    </>
  );
}
