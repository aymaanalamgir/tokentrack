"use client";
import { useState } from "react";
import { useWorkspaceQuery } from "@/lib/use-workspace-query";
import type { Person } from "@/lib/workspace-types";
import { Button } from "@/components/ui/button";
import {
  ErrorState,
  PageHeading,
  Panel,
  Pending,
  PeopleTable,
  Skeleton,
} from "@/components/workspace-ui";

export default function PeopleDirectory() {
  const [search, setSearch] = useState("");
  const [offset, setOffset] = useState(0);
  const query = useWorkspaceQuery<Person[]>(
    `users?${new URLSearchParams({ q: search, limit: "25", offset: String(offset) })}`,
  );
  return (
    <>
      <PageHeading
        title="People"
        description="Directory metadata and management profiles within your authorized scope."
      />
      <div className="mb-4 flex items-center gap-3">
        <input
          aria-label="Find people"
          className="workspace-input max-w-sm"
          placeholder="Find a person…"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setOffset(0);
          }}
        />
        {query.isFetching && <Pending label="Updating people" />}
      </div>
      {query.isPending ? (
        <Skeleton label="Loading people" />
      ) : query.error ? (
        <ErrorState error={query.error} retry={query.refetch} />
      ) : (
        <Panel title={`${query.data.meta?.total ?? 0} visible people`}>
          <PeopleTable people={query.data.data} />
          <div className="flex items-center justify-between border-t border-border p-3 text-[10px] text-muted-foreground">
            <span>Private fields require explicit management authority.</span>
            <div className="flex gap-2">
              <Button
                variant="ghost"
                disabled={!offset}
                onClick={() => setOffset(Math.max(0, offset - 25))}
              >
                Previous
              </Button>
              <Button
                variant="ghost"
                disabled={offset + 25 >= (query.data.meta?.total ?? 0)}
                onClick={() => setOffset(offset + 25)}
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
