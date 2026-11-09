"use client";
import Link from "next/link";
import { useSession } from "./session-provider";
import { PageHeading, Panel, EmptyState, humanize } from "./workspace-ui";
import { SystemStatus } from "./system-status";
import { Badge } from "./ui/badge";

const descriptions: Record<string, string> = {
  analytics:
    "AI usage and cost analytics will be introduced after ingestion and pricing.",
  budgets: "Budget accounts and allocations are planned for a later slice.",
  requests: "Funding requests and delegated approvals are not implemented yet.",
};
export function PlannedWorkspace({ section }: { section: string }) {
  const { me } = useSession();
  if (!me) return null;
  return (
    <>
      <PageHeading
        title={humanize(section)}
        description={`${me.organization.name} / ${me.user.name}`}
      />
      {section === "settings" ? (
        <>
          <Panel title="Workspace settings">
            <div className="space-y-3 p-4 text-xs">
              <p>
                Environment:{" "}
                <Badge className="ml-2 text-muted-foreground">LOCAL DEMO</Badge>
              </p>
              <p className="text-muted-foreground">
                Identity is managed by a server-side demo session. Organization
                administration is not enabled.
              </p>
              <Link href="/profile" className="entity-link inline-block">
                Review my profile and access →
              </Link>
            </div>
          </Panel>
          <div className="mt-6">
            <SystemStatus />
          </div>
        </>
      ) : (
        <Panel title="Planned capability">
          <EmptyState title="Coming soon" description={descriptions[section]} />
          <p className="border-t border-border px-4 py-3 text-[10px] text-muted-foreground">
            Current scope: {humanize(me.access.persona)}. This placeholder
            grants no usage, budget, or approval permissions.
          </p>
        </Panel>
      )}
    </>
  );
}
