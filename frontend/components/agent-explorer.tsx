"use client";
import { useMemo, useState } from "react";
import { ChevronRight } from "lucide-react";
import { count, money } from "@/lib/analytics";
import type { AgentRow } from "@/lib/agents";
import { Button } from "./ui/button";
import { EmptyState, Panel, SearchInput, ShowMore, toneText, type Tone } from "./workspace-ui";

const PREVIEW = 5;
const PAGE = 10;
type Sort = "runs" | "success" | "retry" | "cost";
const pct = (n: number, d: number) => (d ? (n * 100) / d : null);
// Success rate excludes running/unknown runs, matching the server-side metric definition.
// Efficiency colour cues (display only; insight findings use the server's thresholds): success at or above 90% is
// green, 80–90% amber, below 80% red; retry rates above 10% are amber and above 20% red.
export function rateTone(successes: number, concluded: number): Tone {
  if (!concluded) return "default";
  const rate = (successes * 100) / concluded;
  return rate >= 90 ? "good" : rate >= 80 ? "warning" : "danger";
}
export function retryTone(percent: string | number | null | undefined): Tone {
  const rate = Number(percent ?? 0);
  return rate > 20 ? "danger" : rate > 10 ? "warning" : "default";
}
export function successRate(a: Pick<AgentRow, "successful_runs" | "failed_runs" | "cancelled_runs">) {
  return pct(a.successful_runs, a.successful_runs + a.failed_runs + a.cancelled_runs);
}

/**
 * Compact, searchable agent directory for the Agents overview. Shows the top agents first; "Show all" expands
 * into a paginated list. Selecting an agent opens a focused summary with links into its executions and insights.
 */
export function AgentExplorer({ agents, onOpen }: { agents: AgentRow[]; onOpen: (agentId: string, tab: "executions" | "insights" | "overview") => void }) {
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<Sort>("runs");
  const [expanded, setExpanded] = useState(false);
  const [page, setPage] = useState(0);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    const key = (a: AgentRow) => (sort === "runs" ? a.runs : sort === "success" ? (successRate(a) ?? -1) : sort === "retry" ? Number(a.retry_rate_percent ?? -1) : Number(a.corrected_modeled_cost));
    return agents
      .filter((a) => !needle || `${a.name} ${a.workflow_type} ${a.agent_key}`.toLowerCase().includes(needle))
      .sort((a, b) => key(b) - key(a) || a.name.localeCompare(b.name));
  }, [agents, search, sort]);
  const visible = expanded ? rows.slice(page * PAGE, (page + 1) * PAGE) : rows.slice(0, PREVIEW);
  const selected = agents.find((a) => a.id === selectedId) ?? rows[0];
  return (
    <div className="grid gap-5 xl:grid-cols-3">
      <Panel title={`Agent explorer · ${agents.length}`} className="xl:col-span-2" action={
        <div className="flex items-center gap-2">
          <SearchInput label="Search agents" value={search} onChange={(v) => { setSearch(v); setPage(0); }} />
          <select aria-label="Sort agents" className="h-8 rounded-md border border-border bg-surface px-2 text-xs" value={sort} onChange={(e) => setSort(e.target.value as Sort)}>
            <option value="runs">Most runs</option><option value="success">Highest success</option><option value="retry">Highest retry rate</option><option value="cost">Highest cost</option>
          </select>
        </div>}>
        {rows.length === 0 ? <EmptyState title="No agents match" description="Clear the search or widen the date range." /> : (
          <ul className="divide-y divide-border" data-testid="agent-explorer">
            {visible.map((a) => {
              const rate = successRate(a);
              return (
                <li key={a.id}>
                  <button type="button" onClick={() => setSelectedId(a.id)} aria-pressed={selected?.id === a.id} aria-label={`Select ${a.name} (${a.workflow_type})`}
                    className={`grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2 px-4 py-3 text-left hover:bg-muted/40 ${selected?.id === a.id ? "bg-muted/50" : ""}`}>
                    <span className="min-w-0">
                      <span className="block truncate text-xs font-medium">{a.name}</span>
                      <span className="block truncate text-[10px] text-muted-foreground">{a.workflow_type} · {count(a.runs)} runs · <span className={toneText[retryTone(a.retry_rate_percent)]}>{a.retry_rate_percent ? Number(a.retry_rate_percent).toFixed(1) : "0.0"}% retried</span> · <span className="text-success">{money(a.corrected_modeled_cost, 2)}</span></span>
                    </span>
                    <span className="flex items-center gap-2 text-right">
                      <span><span className={`block font-mono text-sm ${toneText[rateTone(a.successful_runs, a.successful_runs + a.failed_runs + a.cancelled_runs)]}`}>{rate === null ? "N/A" : rate.toFixed(1) + "%"}</span><span className="block text-[9px] text-muted-foreground">success</span></span>
                      <ChevronRight size={13} className="text-muted-foreground" />
                    </span>
                    <span className="col-span-2 block h-1 overflow-hidden rounded bg-muted"><span className={`block h-1 rounded ${{ default: "bg-success/70", spend: "bg-success/70", good: "bg-success/70", warning: "bg-warning/80", danger: "bg-danger/80" }[rateTone(a.successful_runs, a.successful_runs + a.failed_runs + a.cancelled_runs)]}`} style={{ width: `${rate ?? 0}%` }} /></span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
        {expanded && rows.length > PAGE && (
          <div className="flex items-center justify-between border-t border-border px-4 py-2 text-[10px] text-muted-foreground">
            <span>{page * PAGE + 1}–{Math.min(rows.length, (page + 1) * PAGE)} of {rows.length}</span>
            <span className="flex gap-3"><button disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</button><button disabled={(page + 1) * PAGE >= rows.length} onClick={() => setPage(page + 1)}>Next</button></span>
          </div>
        )}
        <ShowMore total={rows.length} shown={PREVIEW} expanded={expanded} onToggle={() => { setExpanded(!expanded); setPage(0); }} noun="agents" />
      </Panel>
      {selected ? <AgentSummary agent={selected} onOpen={onOpen} /> : <Panel title="Agent"><EmptyState title="No agent runs in this range" /></Panel>}
    </div>
  );
}

function AgentSummary({ agent, onOpen }: { agent: AgentRow; onOpen: (agentId: string, tab: "executions" | "insights" | "overview") => void }) {
  const rate = successRate(agent);
  const linked = Number(agent.usage_events);
  const priced = linked ? (Number(agent.priced_events) * 100) / linked : null;
  const tokensPerRun = agent.runs ? (Number(agent.input_tokens) + Number(agent.output_tokens)) / agent.runs : 0;
  const stats: [string, string][] = [
    ["Runs", count(agent.runs)],
    ["Success rate", rate === null ? "N/A" : rate.toFixed(1) + "%"],
    ["Retried runs", `${count(agent.retried_runs)} (${agent.retry_rate_percent ? Number(agent.retry_rate_percent).toFixed(1) : "0.0"}%)`],
    ["Known cost", money(agent.corrected_modeled_cost, 2)],
    ["Tokens per run", Math.round(tokensPerRun).toLocaleString("en-US")],
    ["Avg duration", Number(agent.average_duration_seconds).toFixed(1) + "s"],
  ];
  return (
    <Panel title={agent.name} className="h-full" action={<span className="text-[10px] text-muted-foreground">Selected</span>}>
      <div className="p-4" data-testid="agent-summary">
        <p className="text-[10px] text-muted-foreground">{agent.workflow_type} · {agent.agent_key}</p>
        <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3">
          {stats.map(([label, value]) => <div key={label}><dt className="text-[10px] text-muted-foreground">{label}</dt><dd className="font-mono text-sm">{value}</dd></div>)}
        </dl>
        <div className="mt-4" aria-label={`Outcomes: ${agent.successful_runs} success, ${agent.failed_runs} failed, ${agent.cancelled_runs} cancelled, ${agent.incomplete_runs} incomplete`}>
          <div className="flex h-1.5 overflow-hidden rounded bg-muted">
            <span className="bg-success" style={{ flex: agent.successful_runs }} /><span className="bg-danger" style={{ flex: agent.failed_runs }} /><span className="bg-muted-foreground/40" style={{ flex: agent.cancelled_runs + agent.incomplete_runs }} />
          </div>
          <p className="mt-1.5 text-[10px] text-muted-foreground">{count(agent.successful_runs)} success · {count(agent.failed_runs)} failed · {count(agent.cancelled_runs + agent.incomplete_runs)} cancelled or incomplete</p>
        </div>
        <p className="mt-3 text-[10px] text-muted-foreground">{priced === null ? "No linked usage." : priced >= 100 ? "Cost coverage complete." : `Cost coverage ${priced.toFixed(1)}%: ${count(agent.unpriced_events)} unpriced events have unknown cost.`}</p>
        <div className="mt-4 flex flex-wrap gap-2">
          <Button variant="outline" onClick={() => onOpen(agent.id, "executions")}>View executions</Button>
          <Button variant="outline" onClick={() => onOpen(agent.id, "insights")}>Insights</Button>
          <Button variant="ghost" onClick={() => onOpen(agent.id, "overview")}>Focus workspace</Button>
        </div>
      </div>
    </Panel>
  );
}
