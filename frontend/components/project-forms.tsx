"use client";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Plus, X } from "lucide-react";
import { useWorkspaceQuery } from "@/lib/use-workspace-query";
import { useProjectMutation } from "@/lib/use-project-mutation";
import { useSession } from "./session-provider";
import type { Person, Project } from "@/lib/workspace-types";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import { EmptyState, ErrorState, Pending } from "./workspace-ui";

export type ProjectMutation = ReturnType<typeof useProjectMutation>;

export function ProjectDialog({
  open,
  close,
  title,
  busy = false,
  children,
}: {
  open: boolean;
  close: () => void;
  title: string;
  busy?: boolean;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (open && !ref.current?.open) ref.current?.showModal();
    if (!open && ref.current?.open) ref.current?.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      aria-label={title}
      className="identity-dialog"
      onClose={close}
      onCancel={(event) => {
        if (busy) event.preventDefault();
      }}
      onClick={(event) => {
        if (event.currentTarget === event.target && !busy) close();
      }}
    >
      <div className="flex items-center justify-between border-b border-border px-5 py-3">
        <h2 className="text-sm font-medium">{title}</h2>
        <Button
          variant="ghost"
          size="icon"
          disabled={busy}
          aria-label={`Close ${title.toLowerCase()}`}
          onClick={close}
        >
          <X />
        </Button>
      </div>
      {open && children}
    </dialog>
  );
}

export function EmployeePicker({
  path,
  selected,
  select,
  disabled,
}: {
  path: string;
  selected: Person | null;
  select: (person: Person) => void;
  disabled: boolean;
}) {
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(search), 200);
    return () => clearTimeout(timer);
  }, [search]);
  const query = useWorkspaceQuery<Person[]>(
    `${path}${path.includes("?") ? "&" : "?"}${new URLSearchParams({ q: debounced, limit: "10" })}`,
  );
  return (
    <div className="space-y-2">
      <label className="block text-xs">
        Find an employee
        <input
          aria-label="Find an employee"
          className="workspace-input mt-2"
          placeholder="Search by name or title…"
          value={search}
          disabled={disabled}
          onChange={(event) => setSearch(event.target.value)}
        />
      </label>
      {selected && (
        <p className="text-[10px] text-success">Selected: {selected.name}</p>
      )}
      {query.isPending ? (
        <Pending label="Finding eligible employees…" />
      ) : query.error ? (
        <ErrorState error={query.error} retry={query.refetch} />
      ) : (
        <>
          <div className="max-h-56 divide-y divide-border overflow-auto rounded border border-border">
            {query.data.data.map((person) => (
              <button
                type="button"
                aria-label={`Select ${person.name}`}
                aria-pressed={selected?.id === person.id}
                disabled={disabled}
                key={person.id}
                onClick={() => select(person)}
                className={`flex w-full items-center justify-between gap-2 px-3 py-2.5 text-left hover:bg-muted ${selected?.id === person.id ? "bg-muted" : ""}`}
              >
                <div>
                  <p className="text-xs font-medium">{person.name}</p>
                  <p className="mt-1 text-[10px] text-muted-foreground">
                    {person.job_title} ·{" "}
                    {person.primary_team?.name ?? "No home team"}
                  </p>
                </div>
                {selected?.id === person.id && <Badge>SELECTED</Badge>}
              </button>
            ))}
            {!query.data.data.length && (
              <EmptyState title="No eligible employees match" />
            )}
          </div>
          <p className="text-[10px] text-muted-foreground">
            Showing up to 10 of {query.data.meta?.total ?? 0} eligible people.
            Refine your search.
          </p>
        </>
      )}
    </div>
  );
}

export function MutationError({ mutation }: { mutation: ProjectMutation }) {
  return mutation.error ? (
    <p
      role="alert"
      className="rounded border border-danger/30 px-3 py-2 text-xs text-danger"
    >
      {mutation.error}
    </p>
  ) : null;
}

export function CreateProjectAction() {
  const { me } = useSession();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const mutation = useProjectMutation();
  if (!me?.access.capabilities.includes("projects.create.organization"))
    return null;
  return (
    <>
      <Button
        onClick={() => {
          mutation.clearError();
          setOpen(true);
        }}
      >
        <Plus />
        Create project
      </Button>
      <ProjectDialog
        open={open}
        close={() => {
          if (!mutation.pending) setOpen(false);
        }}
        title="Create project"
        busy={mutation.pending}
      >
        <ProjectForm
          mutation={mutation}
          create
          onSaved={(project) => {
            setOpen(false);
            router.push(`/projects/${project.id}`);
          }}
        />
      </ProjectDialog>
    </>
  );
}

export function ProjectForm({
  project,
  create = false,
  mutation,
  onSaved,
}: {
  project?: Project;
  create?: boolean;
  mutation: ProjectMutation;
  onSaved: (project: Project) => void;
}) {
  const [name, setName] = useState(project?.name ?? "");
  const [slug, setSlug] = useState("");
  const [description, setDescription] = useState(project?.description ?? "");
  const [status, setStatus] = useState("planned");
  const [chooseLead, setChooseLead] = useState(false);
  const [lead, setLead] = useState<Person | null>(null);
  return (
    <form
      className="space-y-4 p-5"
      onSubmit={async (event) => {
        event.preventDefault();
        const attributes = create
          ? {
              name,
              slug,
              description,
              status,
              ...(lead ? { initial_lead_id: lead.id } : {}),
            }
          : { name, description };
        const saved = await mutation.run<Project>(
          create ? "projects" : `projects/${project?.id}`,
          create ? "POST" : "PATCH",
          { project: attributes },
          create ? "Project created" : "Project information updated",
        );
        if (saved) onSaved(saved);
      }}
    >
      <label className="block text-xs">
        Project name
        <input
          aria-label="Project name"
          className="workspace-input mt-2"
          required
          maxLength={120}
          value={name}
          disabled={mutation.pending}
          onChange={(event) => setName(event.target.value)}
        />
      </label>
      {create && (
        <label className="block text-xs">
          Slug <span className="text-muted-foreground">(optional)</span>
          <input
            aria-label="Project slug"
            className="workspace-input mt-2 font-mono"
            placeholder="Generated from the project name"
            pattern="[a-z0-9]+(-[a-z0-9]+)*"
            value={slug}
            disabled={mutation.pending}
            onChange={(event) => setSlug(event.target.value)}
          />
        </label>
      )}
      <label className="block text-xs">
        Description
        <textarea
          aria-label="Description"
          className="workspace-input mt-2"
          maxLength={5000}
          value={description}
          disabled={mutation.pending}
          onChange={(event) => setDescription(event.target.value)}
        />
      </label>
      {create && (
        <>
          <label className="block text-xs">
            Initial status
            <select
              aria-label="Initial status"
              className="workspace-input mt-2"
              value={status}
              disabled={mutation.pending}
              onChange={(event) => setStatus(event.target.value)}
            >
              <option value="planned">Planned</option>
              <option value="active">Active</option>
            </select>
          </label>
          <label className="flex items-center gap-2 text-xs">
            <input
              type="checkbox"
              checked={chooseLead}
              disabled={mutation.pending}
              onChange={(event) => {
                setChooseLead(event.target.checked);
                if (!event.target.checked) setLead(null);
              }}
            />
            Assign a different initial lead
          </label>
          {chooseLead && (
            <EmployeePicker
              path="projects/eligible-users"
              selected={lead}
              select={setLead}
              disabled={mutation.pending}
            />
          )}
          <p className="text-[10px] leading-relaxed text-muted-foreground">
            The initial lead receives an explicit project administration grant.
            With no selection, you become the lead. If you choose someone else,
            you remain a reviewer.
          </p>
        </>
      )}
      <MutationError mutation={mutation} />
      <div className="flex justify-end">
        <Button
          type="submit"
          disabled={mutation.pending || (chooseLead && !lead)}
        >
          {mutation.pending ? (
            <Pending label={create ? "Creating…" : "Saving…"} />
          ) : create ? (
            "Create project"
          ) : (
            "Save changes"
          )}
        </Button>
      </div>
    </form>
  );
}
