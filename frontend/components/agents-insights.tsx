"use client";
import Link from 'next/link';
import {Fragment,useState} from 'react';
import {ChevronDown,ChevronRight} from 'lucide-react';
import {count,dateLabel,money} from '@/lib/analytics';
import {changeLabel,EVIDENCE_STATE_LABEL,INSIGHT_TYPE_LABEL,metricChange,metricLabel,supportingRunsHref} from '@/lib/agents';
import type {AgentComparison,Insight,InsightReport,PeriodMetric,TrendRow} from '@/lib/agents';
import {Badge} from './ui/badge';
import {EmptyState,Panel} from './workspace-ui';

type Filter=(values:Record<string,string>)=>void;
const selectCls='rounded-md border border-border bg-surface px-2.5 py-2 text-xs text-foreground';
const periodText=(p:{start:string;end:string})=>`${dateLabel(p.start)} → ${dateLabel(p.end)}`;
const COMPARE_LABEL:Record<string,string>={previous_period:'Previous equal period',week:'Week over week',month:'Month over month'};
const BASIS_LABEL:Record<string,string>={equal_length_preceding_period:'equal-length preceding period',complete_calendar_period:'complete calendar periods',equivalent_elapsed_portion:'equivalent elapsed portion of the previous period'};
const COVERAGE_LABEL:Record<string,string>={complete:'Complete cost coverage',partial_unpriced_or_unposted:'Partial cost: unpriced or unposted usage',no_linked_usage:'No linked usage'};

/** Shared comparison header: windows, basis, synthetic-telemetry and cost-coverage disclosure. */
export function ComparisonBar({report,compare,workflow,filter}:{report:InsightReport;compare:string;workflow:string;filter:Filter}){
  const cov=report.coverage.current;
  return <div className="rounded-lg border border-border bg-surface p-3" data-testid="comparison-bar">
    <div className="flex flex-wrap items-center gap-2">
      <select aria-label="Comparison window" className={selectCls} value={compare} onChange={e=>filter({compare:e.target.value==='previous_period'?'':e.target.value})}>{Object.entries(COMPARE_LABEL).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select>
      <select aria-label="Workflow filter" className={selectCls} value={workflow} onChange={e=>filter({workflow_type:e.target.value})}><option value="">All workflows</option>{[...new Set([...report.scope.workflow_types,...(workflow?[workflow]:[])])].sort().map(w=><option key={w} value={w}>{w}</option>)}</select>
      <p className="text-[11px] text-muted-foreground"><span className="font-mono text-foreground" data-testid="current-period">{periodText(report.current_period)}</span> vs <span className="font-mono" data-testid="comparison-period">{periodText(report.comparison_period)}</span> · UTC, end exclusive · {BASIS_LABEL[report.comparison_basis]??report.comparison_basis}</p>
    </div>
    <div className="mt-2 flex flex-wrap gap-1.5">
      {report.partial_current_period&&<Badge className="text-muted-foreground">Partial current period</Badge>}
      {cov.telemetry!=='observed'&&cov.telemetry!=='none'&&<Badge className="text-muted-foreground" data-testid="synthetic-badge">{cov.telemetry==='mixed'?'Includes synthetic demo outcomes':'Synthetic demo outcomes — simulated, not measured telemetry'}</Badge>}
      <Badge className={cov.cost_completeness==='complete'?'text-muted-foreground':'text-danger'} data-testid="coverage-badge">{COVERAGE_LABEL[cov.cost_completeness]??cov.cost_completeness}{cov.cost_completeness==='partial_unpriced_or_unposted'?` (${count(cov.unpriced_events)} unpriced)`:''}</Badge>
    </div>
  </div>;
}

type MetricDef={key:keyof PeriodMetric;label:string;unit:string;worseWhenHigher:boolean|null};
const METRICS:MetricDef[]=[
  {key:'cost_per_success',label:'Cost per successful run',unit:'usd',worseWhenHigher:true},
  {key:'retry_rate_percent',label:'Retry rate',unit:'percent',worseWhenHigher:true},
  {key:'success_rate_percent',label:'Success rate',unit:'percent',worseWhenHigher:false},
  {key:'input_tokens_per_run',label:'Input tokens per run',unit:'tokens',worseWhenHigher:true},
  {key:'output_tokens_per_run',label:'Output tokens per run',unit:'tokens',worseWhenHigher:true},
  {key:'median_duration_seconds',label:'Median duration',unit:'seconds',worseWhenHigher:true},
];
const raw=(m:PeriodMetric,key:keyof PeriodMetric)=>m[key] as string|number|null;

/** Small-multiple bar trend. Comparison-period buckets are muted, current-period buckets use the foreground. */
function Trend({rows,def}:{rows:TrendRow[];def:MetricDef}){
  const values=rows.map(r=>raw(r,def.key)===null?null:Number(raw(r,def.key)));const max=Math.max(...values.map(v=>v??0),0);
  if(!rows.length||max===0)return <p className="p-4 text-[11px] text-muted-foreground">No {def.label.toLowerCase()} recorded in these periods.</p>;
  return <div className="flex h-24 items-end gap-px px-4 pb-3 pt-4" role="img" aria-label={`${def.label} by ${rows.length} buckets, comparison then current period`}>
    {rows.map((row,i)=><div key={row.bucket+row.period} className="flex h-full min-w-0 flex-1 items-end" title={`${row.bucket} (${row.period==='current'?'current':'comparison'}): ${metricLabel(raw(row,def.key),def.unit)} · ${row.runs} runs`}>
      <span className={`block w-full rounded-t-sm ${values[i]===null?'border-t border-dashed border-border':row.period==='current'?'bg-foreground/70':'bg-muted-foreground/30'}`} style={{height:values[i]===null?'1px':`${Math.max(2,(values[i] as number)/max*100)}%`}}/>
    </div>)}
  </div>;
}

function Decomposition({agent}:{agent:AgentComparison}){
  const d=agent.decomposition;
  if(!d)return <p className="p-4 text-[11px] text-muted-foreground">{agent.evidence_reason} A cost-driver breakdown needs runs in both periods.</p>;
  return <div className="grid gap-4 p-4 lg:grid-cols-2" data-testid="decomposition">
    <div>
      <p className="scope-label">Cost change · {d.basis==='complete_corrected_ledger_cost'?'corrected ledger cost':'known posted cost only (coverage incomplete)'}</p>
      <p className="mt-2 font-mono text-sm">{money(d.cost.baseline??'0')} → {money(d.cost.current??'0')} <span className="text-muted-foreground">({d.cost.delta?money(d.cost.delta):'N/A'})</span></p>
      <dl className="mt-3 space-y-1.5 text-xs">
        <div className="flex justify-between gap-3"><dt>Volume effect <span className="text-muted-foreground">(run-count change × baseline cost per run)</span></dt><dd className="font-mono">{money(d.exact.volume_effect)}</dd></div>
        <div className="flex justify-between gap-3"><dt>Per-run cost effect <span className="text-muted-foreground">(remainder)</span></dt><dd className="font-mono">{money(d.exact.per_run_cost_effect)}</dd></div>
      </dl>
      <p className="mt-2 text-[10px] leading-relaxed text-muted-foreground">These two amounts are exact and sum to the cost change. More runs at the same cost per run is growth, not inefficiency.</p>
      {d.model_mix.length>0&&<><p className="scope-label mt-4">Model mix (share of tokens)</p>
        <table className="workspace-table mt-1"><thead><tr><th>Model</th><th>Previous</th><th>Current</th><th>Cost</th></tr></thead><tbody>{d.model_mix.map(m=><tr key={m.model}><td>{m.model}{m.pricing_model&&m.pricing_model!==m.model&&<span className="block text-[9px] text-muted-foreground">priced as {m.pricing_model}</span>}{m.rate_schedule_changed&&<span className="block text-[9px] text-muted-foreground">rate schedule changed between periods</span>}</td><td>{metricLabel(m.baseline_token_share_percent,'percent')}</td><td>{metricLabel(m.current_token_share_percent,'percent')}</td><td className="font-mono">{m.baseline_cost===null&&m.current_cost===null?'Unpriced':`${m.baseline_cost?money(m.baseline_cost):'—'} → ${m.current_cost?money(m.current_cost):'—'}`}</td></tr>)}</tbody></table></>}
    </div>
    <div>
      <p className="scope-label">Associated changes (not exact causes)</p>
      <table className="workspace-table mt-1"><thead><tr><th>Factor</th><th>Previous</th><th>Current</th><th>Change</th></tr></thead><tbody>{d.associated_factors.map(f=><tr key={f.metric}><td>{f.label}</td><td>{metricLabel(f.baseline,f.unit)}</td><td>{metricLabel(f.current,f.unit)}</td><td>{changeLabel(f,f.unit)}</td></tr>)}</tbody></table>
      <p className="mt-2 text-[10px] leading-relaxed text-muted-foreground">{d.note}</p>
    </div>
  </div>;
}

export function EfficiencyView({report,openInsights}:{report:InsightReport;openInsights:(agentId:string)=>void}){
  const [open,setOpen]=useState<string|null>(null);const b=report.summary.baseline;const c=report.summary.current;
  const cards:[string,string,string,string][]=[['Runs',count(c.runs),`prev ${count(b.runs)}`,changeLabel(metricChange(b.runs,c.runs),'count')],...METRICS.map(m=>[m.label,metricLabel(raw(c,m.key),m.unit),`prev ${metricLabel(raw(b,m.key),m.unit)}`,changeLabel(metricChange(raw(b,m.key),raw(c,m.key)),m.unit)] as [string,string,string,string])];
  return <div className="space-y-5" data-testid="efficiency-view">
    <div className="grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-border bg-border md:grid-cols-4 xl:grid-cols-7">{cards.map(([label,value,previous,change])=><div key={label} className="min-w-0 bg-surface p-3.5"><p className="truncate text-[10px] text-muted-foreground">{label}</p><p className="my-1.5 truncate font-mono text-lg">{value}</p><p className="truncate text-[9px] text-muted-foreground">{previous} · {change}</p></div>)}</div>
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{METRICS.map(def=><Panel key={def.key} title={`${def.label} trend`} action={<span className="text-[9px] text-muted-foreground"><i className="mr-1 inline-block size-2 bg-muted-foreground/30"/>previous <i className="ml-2 mr-1 inline-block size-2 bg-foreground/70"/>current · per {report.trend_bucket}</span>}><Trend rows={report.trend} def={def}/></Panel>)}</div>
    <Panel title="Agent comparison" action={<span className="text-[9px] text-muted-foreground">{report.agents.length} agents · previous → current</span>}>
      {report.agents.length===0?<EmptyState title="No agent runs in either period" description="Choose a different date range, comparison window, or project."/>:
      <div className="overflow-x-auto"><table className="workspace-table" data-testid="agent-comparison"><thead><tr><th>Agent / workflow</th><th>Runs</th><th>Success rate</th><th>Retry rate</th><th>Tokens / run (in · out)</th><th>Cost / success</th><th>Evidence</th></tr></thead><tbody>
        {report.agents.map(a=>{const pair=(key:keyof PeriodMetric,unit:string)=>`${metricLabel(raw(a.baseline,key),unit)} → ${metricLabel(raw(a.current,key),unit)}`;const expanded=open===a.id;
          return <Fragment key={a.id}><tr>
            <td><button className="entity-link inline-flex items-center gap-1" aria-expanded={expanded} aria-label={`Cost drivers for ${a.name}`} onClick={()=>setOpen(expanded?null:a.id)}>{expanded?<ChevronDown size={11}/>:<ChevronRight size={11}/>}{a.name}</button><span className="block pl-4 text-[9px] text-muted-foreground">{a.agent_key} · <button className="underline-offset-2 hover:underline" onClick={()=>openInsights(a.id)}>findings</button></span></td>
            <td>{count(a.baseline.runs)} → {count(a.current.runs)}</td><td>{pair('success_rate_percent','percent')}</td><td>{pair('retry_rate_percent','percent')}</td>
            <td>{pair('input_tokens_per_run','tokens')}<span className="block text-[9px] text-muted-foreground">{pair('output_tokens_per_run','tokens')}</span></td>
            <td className="font-mono">{pair('cost_per_success','usd')}<span className="block text-[9px] text-muted-foreground">{a.current.cost_completeness==='complete'&&a.baseline.cost_completeness!=='partial_unpriced_or_unposted'?changeLabel(a.cost_change,'usd'):'partial cost · '+changeLabel(a.cost_change,'usd')}</span></td>
            <td><span title={a.evidence_reason}>{EVIDENCE_STATE_LABEL[a.evidence_state]??a.evidence_state}</span></td>
          </tr>{expanded&&<tr><td colSpan={7} className="!p-0"><Decomposition agent={a}/></td></tr>}</Fragment>;})}
      </tbody></table></div>}
    </Panel>
    <p className="text-[10px] leading-relaxed text-muted-foreground">{report.money_basis} Success rate excludes running/unknown runs. Tokens per run use runs with linked usage. Comparisons describe measured change, not cause.</p>
  </div>;
}

function EvidenceTable({evidence}:{evidence:Record<string,unknown>}){
  const b=evidence.baseline as Record<string,unknown>|undefined;const c=evidence.current as Record<string,unknown>|undefined;if(!b&&!c)return null;
  const keys=[...new Set([...Object.keys(b??{}),...Object.keys(c??{})])];
  const cell=(v:unknown)=>v===null||v===undefined?'—':typeof v==='object'?Object.entries(v as Record<string,unknown>).map(([k,n])=>`${k.replaceAll('_',' ')}: ${n}`).join(', ')||'—':String(v);
  return <table className="workspace-table"><thead><tr><th>Recorded value</th><th>Previous</th><th>Current</th></tr></thead><tbody>{keys.map(k=><tr key={k}><td>{k.replaceAll('_',' ')}</td><td className="font-mono">{cell(b?.[k])}</td><td className="font-mono">{cell(c?.[k])}</td></tr>)}</tbody></table>;
}
type Scenario={label?:string;recorded_pricing_model?:string;alternative_pricing_model?:string;modeled_cost_at_recorded_rates?:string;modeled_cost_at_alternative_rates?:string;modeled_difference?:string;assumptions?:string[];does_not_account_for?:string[];basis?:string;estimated_savings?:null;reason?:string};

function InsightCard({insight}:{insight:Insight}){
  const [open,setOpen]=useState(false);const scenario=insight.evidence.savings_scenario as Scenario|undefined;const categories=insight.evidence.categories as Record<string,string|null>|undefined;
  const partial=Object.values(insight.financial_coverage).includes('partial_unpriced_or_unposted');
  return <article className="border-b border-border p-4 last:border-b-0" data-testid="insight" data-type={insight.type} data-severity={insight.severity}>
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div className="min-w-0"><p className="text-xs font-medium">{insight.agent_name}<span className="ml-2 font-normal text-muted-foreground">{insight.agent_key}</span></p><p className="mt-1.5 text-sm">{insight.finding}</p></div>
      <div className="flex flex-wrap gap-1.5"><Badge className={insight.severity==='critical'?'text-danger':insight.severity==='warning'?'text-foreground':'text-muted-foreground'}>{insight.severity}</Badge><Badge className="text-muted-foreground">{INSIGHT_TYPE_LABEL[insight.type]??insight.type}</Badge></div>
    </div>
    <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-2 text-xs md:grid-cols-4">
      <div><dt className="text-[10px] text-muted-foreground">Previous</dt><dd className="font-mono">{metricLabel(insight.baseline,insight.unit)}</dd></div>
      <div><dt className="text-[10px] text-muted-foreground">Current</dt><dd className="font-mono">{metricLabel(insight.current,insight.unit)}</dd></div>
      <div><dt className="text-[10px] text-muted-foreground">Evidence</dt><dd>{count(insight.sample_size.baseline_runs)} vs {count(insight.sample_size.current_runs)} {insight.sample_size.basis}</dd></div>
      <div><dt className="text-[10px] text-muted-foreground">Period</dt><dd className="font-mono text-[11px]">{periodText(insight.time_window)}</dd></div>
    </dl>
    <p className="mt-3 text-xs"><span className="font-medium" data-testid="evidence-quality">{insight.evidence_quality_label}</span><span className="text-muted-foreground"> · {insight.quality_reason}</span>{partial&&insight.evidence_quality!=='incomplete_cost_data'&&<span className="text-muted-foreground"> Cost coverage for this agent is partial.</span>}</p>
    <p className="mt-2 text-xs"><span className="text-muted-foreground">Suggested investigation: </span>{insight.suggested_action}</p>
    <div className="mt-3 flex flex-wrap gap-3 text-[11px]"><Link className="entity-link" href={supportingRunsHref(insight.drilldown)}>View supporting runs</Link><button className="entity-link" aria-expanded={open} onClick={()=>setOpen(!open)}>{open?'Hide evidence':'Show evidence'}</button></div>
    {open&&<div className="mt-3 space-y-3 rounded-md border border-border p-3" data-testid="insight-evidence">
      <div className="overflow-x-auto"><EvidenceTable evidence={insight.evidence}/></div>
      {categories&&<ul className="space-y-1 text-xs">{Object.entries(categories).map(([k,v])=><li key={k} className="flex justify-between gap-3"><span>{k.replaceAll('_',' ')}</span><span className="font-mono">{v===null?'Unavailable — no attempt-level cost attribution':money(v)}</span></li>)}</ul>}
      {scenario&&(scenario.label?<div className="text-xs" data-testid="rate-scenario"><p className="font-medium">{scenario.label}</p><p className="mt-1 font-mono">{scenario.recorded_pricing_model} {money(scenario.modeled_cost_at_recorded_rates??'0')} → {scenario.alternative_pricing_model} {money(scenario.modeled_cost_at_alternative_rates??'0')} <span className="text-muted-foreground">(modeled difference {money(scenario.modeled_difference??'0')})</span></p><p className="mt-1 text-[10px] leading-relaxed text-muted-foreground">Assumes: {scenario.assumptions?.join(', ')}. Does not account for: {scenario.does_not_account_for?.join(', ')}. {scenario.basis} Not a forecast of savings.</p></div>:<p className="text-xs text-muted-foreground">Estimated savings: {scenario.reason}</p>)}
      {insight.associated.length>0&&<div><p className="scope-label">Also observed in the same periods (not causes)</p><ul className="mt-1 space-y-0.5 text-xs">{insight.associated.map(a=><li key={a.metric}>{a.label}: {metricLabel(a.baseline,a.unit)} → {metricLabel(a.current,a.unit)} <span className="text-muted-foreground">({changeLabel(a,a.unit)})</span></li>)}</ul></div>}
      {typeof insight.evidence.source==='string'&&<p className="text-[10px] text-muted-foreground">Source: {insight.evidence.source}</p>}
      {insight.limitation&&<p className="text-[10px] text-muted-foreground">Limitation: {insight.limitation}</p>}
    </div>}
  </article>;
}

export function InsightsView({report,search,filter}:{report:InsightReport;search:URLSearchParams;filter:Filter}){
  const sparse=report.agents.filter(a=>!['sufficient','limited_sample'].includes(a.evidence_state));const s=report.summary;const filtered=s.total_findings!==s.findings;
  return <div className="space-y-5" data-testid="insights-view">
    <Panel title="Efficiency insights" action={<span className="font-mono text-[10px] text-muted-foreground">{periodText(report.current_period)}</span>}>
      <div className="flex flex-wrap items-center gap-2 border-b border-border p-3">
        <p className="mr-auto text-xs" data-testid="insight-summary">{s.requiring_attention===0?(s.findings===0?'No findings':`${s.findings} informational finding${s.findings===1?'':'s'}`):`${s.requiring_attention} finding${s.requiring_attention===1?' requires':'s require'} attention`}<span className="text-muted-foreground"> · {s.by_severity.critical??0} critical · {s.by_severity.warning??0} warning · {s.by_severity.info??0} info{filtered?` · ${s.total_findings-s.findings} hidden by filters`:''}</span></p>
        <select aria-label="Insight type filter" className={selectCls} value={search.get('insight_type')??''} onChange={e=>filter({insight_type:e.target.value})}><option value="">All finding types</option>{Object.entries(INSIGHT_TYPE_LABEL).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select>
        <select aria-label="Severity filter" className={selectCls} value={search.get('severity')??''} onChange={e=>filter({severity:e.target.value})}><option value="">All severities</option><option value="critical">Critical</option><option value="warning">Warning</option><option value="info">Info</option></select>
        <select aria-label="Evidence quality filter" className={selectCls} value={search.get('evidence_quality')??''} onChange={e=>filter({evidence_quality:e.target.value})}><option value="">All evidence quality</option><option value="sufficient">Sufficient evidence</option><option value="limited_sample">Limited sample</option><option value="incomplete_cost_data">Incomplete cost data</option></select>
      </div>
      {report.insights.length===0?<EmptyState title={filtered?'No findings match these filters':'No findings for this scope and period'} description={filtered?'Clear a filter to see the other findings.':'Nothing crossed a documented threshold with enough evidence. TokenTrack does not generate findings to fill this list.'}/>:report.insights.map(i=><InsightCard key={i.id} insight={i}/>)}
    </Panel>
    {sparse.length>0&&<Panel title="Not compared"><ul className="divide-y divide-border" data-testid="not-compared">{sparse.map(a=><li key={a.id} className="flex flex-wrap justify-between gap-2 px-4 py-3 text-xs"><span>{a.name}<span className="ml-2 text-muted-foreground">{a.agent_key}</span></span><span className="text-muted-foreground"><span className="text-foreground">{EVIDENCE_STATE_LABEL[a.evidence_state]??a.evidence_state}</span> · {a.evidence_reason}</span></li>)}</ul></Panel>}
    <div className="rounded-lg border border-border bg-surface p-4"><p className="scope-label">How to read these findings</p><ul className="mt-2 list-disc space-y-1 pl-4 text-[11px] leading-relaxed text-muted-foreground">{report.limitations.map(l=><li key={l}>{l}</li>)}<li>Thresholds: {report.thresholds.min_runs}+ runs per period; retry rate +{report.thresholds.retry_rate_increase_points} pts; success rate −{report.thresholds.success_rate_decrease_points} pts; tokens per run +{report.thresholds.tokens_per_run_increase_percent}%; duration +{report.thresholds.duration_increase_percent}%; cost per success +{report.thresholds.cost_per_success_increase_percent}%; model cost share ≥{report.thresholds.model_cost_share_percent}%; failed-run cost share ≥{report.thresholds.failed_run_cost_share_percent}%.</li></ul></div>
  </div>;
}
