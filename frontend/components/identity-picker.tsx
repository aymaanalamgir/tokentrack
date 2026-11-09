"use client";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Check, Search, ShieldCheck } from "lucide-react";
import { api } from "@/lib/api-client";
import type { ApiResponse, Identity } from "@/lib/workspace-types";
import { useSession } from "./session-provider";
import { Badge } from "./ui/badge";
import { ErrorState, humanize, Pending, Skeleton } from "./workspace-ui";

export function IdentityPicker({ onSelected }: { onSelected?: () => void }) {
  const { me, switchIdentity, switching } = useSession();
  const [organization, setOrganization] = useState(me?.organization.id ?? "");
  const [search, setSearch] = useState("");
  const [persona, setPersona] = useState("");
  const query = useQuery({
    queryKey: ["demo-identities"],
    queryFn: ({ signal }) =>
      api<ApiResponse<Identity[]>>("demo/identities", { signal }),
    staleTime: 60000,
    retry: false,
  });
  if (query.isPending) return <Skeleton label="Loading demo identities" />;
  if (query.error)
    return <ErrorState error={query.error} retry={query.refetch} />;
  const identities = query.data.data;
  const organizations = [
    ...new Map(
      identities.map((identity) => [
        identity.organization.id,
        identity.organization,
      ]),
    ).values(),
  ];
  const selectedOrg = organization || organizations[0]?.id;
  const filtered = identities.filter(
    (identity) =>
      identity.organization.id === selectedOrg &&
      (!persona || identity.persona === persona) &&
      `${identity.name} ${identity.job_title}`
        .toLowerCase()
        .includes(search.toLowerCase()),
  );
  return (
    <div className="space-y-4">
      <div className="grid gap-2 sm:grid-cols-2">
        {organizations.map((org) => (
          <button
            key={org.id}
            disabled={switching}
            onClick={() => {
              setOrganization(org.id);
              setSearch("");
            }}
            className={`rounded-md border p-3 text-left ${selectedOrg === org.id ? "border-foreground bg-muted/50" : "border-border hover:bg-muted/30"}`}
          >
            <span className="text-xs font-medium">{org.name}</span>
            <span className="mt-1 block font-mono text-[10px] text-muted-foreground">
              {identities.filter((i) => i.organization.id === org.id).length}{" "}
              fictional people
            </span>
          </button>
        ))}
      </div>
      <div className="flex flex-wrap gap-2">
        <label className="relative min-w-32 flex-1">
          <Search
            size={13}
            className="absolute left-3 top-3 text-muted-foreground"
          />
          <input
            aria-label="Find an identity"
            className="workspace-input pl-9!"
            placeholder="Find a person or job title…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
        </label>
        <select
          aria-label="Filter personas"
          className="workspace-input w-auto!"
          value={persona}
          onChange={(event) => setPersona(event.target.value)}
        >
          <option value="">All experiences</option>
          {["leadership", "manager", "project_lead", "employee"].map((role) => (
            <option key={role} value={role}>
              {humanize(role)}
            </option>
          ))}
        </select>
      </div>
      <div className="max-h-[360px] overflow-y-auto rounded-md border border-border divide-y divide-border">
        {filtered.map((identity) => (
          <button
            key={identity.id}
            aria-label={`Continue as ${identity.name}`}
            disabled={switching}
            onClick={async () => {
              await switchIdentity(identity.id);
              onSelected?.();
            }}
            className="flex w-full items-center justify-between gap-3 px-3 py-3 text-left hover:bg-muted/50 disabled:opacity-50"
          >
            <div className="min-w-0">
              <p className="flex items-center gap-2 text-xs font-medium">
                {identity.name}
                {me?.user.id === identity.id && <Check size={12} />}
              </p>
              <p className="mt-1 truncate text-[10px] text-muted-foreground">
                {identity.job_title} · {identity.primary_team}
              </p>
            </div>
            <Badge className="shrink-0 text-muted-foreground">
              {humanize(identity.persona)}
            </Badge>
          </button>
        ))}
        {!filtered.length && (
          <p className="p-5 text-xs text-muted-foreground">
            No matching demo identities.
          </p>
        )}
      </div>
      <p className="flex items-center gap-2 text-[10px] text-muted-foreground">
        <ShieldCheck size={12} />
        Fictional identities · Permissions enforced by Rails
      </p>
    </div>
  );
}

export function DemoEntry() {
  const { switching, error, reload } = useSession();
  return (
    <div className="mx-auto max-w-2xl py-7 sm:py-12">
      <div className="mb-6">
        <Badge className="mb-3 text-muted-foreground">LOCAL DEMO</Badge>
        <h1 className="text-2xl font-medium tracking-tight">
          Enter a workspace
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Choose a fictional organization and see the workspace through
          someone’s actual access scope.
        </p>
      </div>
      {error && (
        <div
          role="alert"
          className="mb-4 rounded-md border border-danger/30 p-3 text-xs text-danger"
        >
          {error}
          <button className="ml-2 underline" onClick={reload}>
            Retry connection
          </button>
        </div>
      )}
      {switching ? (
        <div className="space-y-5">
          <Pending label="Switching identity and loading authorized data…" />
          <Skeleton />
        </div>
      ) : (
        <IdentityPicker />
      )}
    </div>
  );
}
