export type AgentMetric={runs:number;successful_runs:number;failed_runs:number;cancelled_runs:number;incomplete_runs:number;retried_runs:number;attempts:number;retries:number;average_retries:string;average_duration_seconds:string;retry_rate_percent:string|null;input_tokens:number|string;output_tokens:number|string;cached_input_tokens:number|string;usage_events:number;priced_events:number;unpriced_events:number;pending_delivery:number;corrected_modeled_cost:string;cost_per_success?:string|null;average_successful_run_cost?:string|null;cost_completeness?:string;synthetic_runs?:number};
export type AgentRow=AgentMetric&{id:string;agent_key:string;name:string;workflow_type:string};
export type Attempt={attempt_id:string;attempt_number:number;started_at:string;completed_at:string|null;status:string;error_category:string|null};
export type Run=Pick<AgentMetric,'input_tokens'|'output_tokens'|'cached_input_tokens'|'usage_events'|'priced_events'|'unpriced_events'|'pending_delivery'>&{id:string;agent_id:string;agent_key:string;agent_name:string;workflow_type:string;source:string;run_id:string;user_id:string;user_name?:string;project_id:string|null;project_name?:string;started_at:string;completed_at:string|null;status:string;outcome:string;outcome_source?:string;attempts:number;retries:number;duration_seconds:string|null;corrected_modeled_cost:string;attempt_records:Attempt[]};
export type AgentReport={schema_version:1;currency:'USD';totals:AgentMetric;timeseries:(AgentMetric&{bucket:string})[];agents:AgentRow[];runs:{rows:Run[];total:number;limit:number;offset:number};context:{scope:string;scope_key:string;start:string;end:string;available_range?:{start:string|null;end:string|null};projects:{id:string;name:string}[];money_basis:string}};

// ---- Slice 9B: efficiency comparisons and explainable insights -------------------------------------------
export type AgentTab='overview'|'efficiency'|'insights'|'executions';
export const AGENT_TABS:AgentTab[]=['overview','efficiency','insights','executions'];
export type Period={start:string;end:string};
export type PeriodMetric={runs:number;successful_runs:number;failed_runs:number;cancelled_runs:number;incomplete_runs:number;retried_runs:number;retries:number;concluded_runs:number;linked_runs:number;synthetic_runs:number;usage_events:number|string;priced_events:number|string;unpriced_events:number|string;pending_delivery:number|string;success_rate_percent:string|null;retry_rate_percent:string|null;input_tokens_per_run:string|null;output_tokens_per_run:string|null;total_tokens_per_run:string|null;median_duration_seconds:string|null;average_duration_seconds:string|null;pricing_coverage_percent:string|null;corrected_modeled_cost:string;original_modeled_cost:string;adjustments:string;cost_per_success:string|null;cost_per_run:string|null;failed_run_cost:string;failed_run_cost_share_percent:string|null;cost_completeness:'complete'|'partial_unpriced_or_unposted'|'no_linked_usage'};
export type Change={baseline:string|null;current:string|null;delta:string|null;percent_change:string|null};
export type Factor=Change&{metric:string;label:string;unit:string;attribution?:string};
export type Decomposition={basis:string;cost:Change;exact:{method:string;volume_effect:string;per_run_cost_effect:string;baseline_cost_per_run:string|null;current_cost_per_run:string|null};associated_factors:Factor[];model_mix:{model:string;pricing_model:string|null;baseline_token_share_percent:string|null;current_token_share_percent:string|null;baseline_cost:string|null;current_cost:string|null;rate_schedule_changed:boolean}[];note:string};
export type AgentComparison={id:string;agent_key:string;name:string;workflow_type:string;baseline:PeriodMetric;current:PeriodMetric;evidence_state:string;evidence_reason:string;cost_change:Change;decomposition:Decomposition|null};
export type Insight={id:string;type:string;agent_id:string;agent_name:string;agent_key:string;workflow_type:string;severity:'critical'|'warning'|'info';status:string;metric:string;unit:string;baseline:string|null;current:string|null;absolute_change:string|null;percent_change:string|null;finding:string;suggested_action:string;limitation:string|null;evidence_quality:string;evidence_quality_label:string;quality_reason:string;sample_size:{baseline_runs:number;current_runs:number;basis:string};financial_coverage:{baseline:string;current:string};evidence:Record<string,unknown>;associated:Factor[];drilldown:Record<string,string>;time_window:Period;comparison_window:Period};
export type TrendRow=PeriodMetric&{bucket:string;period:'baseline'|'current'};
export type InsightReport={schema_version:1;analysis_version:number;currency:'USD';compare:string;current_period:Period;comparison_period:Period;partial_current_period:boolean;comparison_basis:string;trend_bucket:string;scope:{persona:string;scope_key:string;projects:{id:string;name:string}[];workflow_types:string[];available_range:{start:string|null;end:string|null}};summary:{findings:number;total_findings:number;requiring_attention:number;by_severity:Record<string,number>;agents_analyzed:number;agents_without_comparison:number;baseline:PeriodMetric;current:PeriodMetric;cost_per_success_change:Change;cost_change:Change};insights:Insight[];agents:AgentComparison[];trend:TrendRow[];coverage:Record<'baseline'|'current',{cost_completeness:string;telemetry:string;unpriced_events:number|string;pending_delivery:number|string;pricing_coverage_percent:string|null;runs:number}>;thresholds:Record<string,string|number>;limitations:string[];money_basis:string};

const RUN_KEYS=['start','end','agent_id','run_id','project_id','user_id','workflow_type','status','outcome','retried','limit','offset'];
const INSIGHT_KEYS=['start','end','compare','agent_id','project_id','user_id','workflow_type','insight_type','severity','evidence_quality'];
function pick(search:URLSearchParams,keys:string[]){const out=new URLSearchParams();for(const key of keys){const value=search.get(key);if(value)out.set(key,value);}return out;}
export function agentTab(search:URLSearchParams):AgentTab{const tab=search.get('tab');return AGENT_TABS.includes(tab as AgentTab)?tab as AgentTab:'overview';}
/** Rails rejects unknown filters, so each endpoint only receives the parameters it owns; `tab` is client-only. */
export function agentsPath(search:URLSearchParams){const q=pick(search,RUN_KEYS).toString();return 'agents'+(q?'?'+q:'');}
export function insightsPath(search:URLSearchParams){const q=pick(search,INSIGHT_KEYS);if(q.has('start')!==q.has('end')){q.delete('start');q.delete('end');}const text=q.toString();return 'agents/insights'+(text?'?'+text:'');}
/** Display-only rounding of decimal strings; authoritative values stay exact strings from Rails. */
export function metricLabel(value:string|number|null|undefined,unit:string){
  if(value===null||value===undefined||value==='')return 'N/A';
  const n=Number(value);
  if(unit==='percent')return n.toFixed(1)+'%';
  if(unit==='seconds')return n.toFixed(1)+'s';
  if(unit==='usd'){const negative=String(value).startsWith('-');return (negative?'-':'')+'$'+Math.abs(n).toFixed(4);}
  return Math.round(n).toLocaleString('en-US');
}
/** Signed change text. A missing or zero baseline yields "no baseline", never an infinite percentage. */
export function changeLabel(change:Pick<Change,'delta'|'percent_change'>|null|undefined,unit:string){
  if(!change||change.delta===null||change.delta===undefined)return 'no comparison';
  const delta=Number(change.delta);const sign=delta>0?'+':'';
  if(unit==='percent')return `${sign}${delta.toFixed(1)} pts`;
  if(change.percent_change===null||change.percent_change===undefined)return delta===0?'no change':'no baseline';
  return `${Number(change.percent_change)>0?'+':''}${Number(change.percent_change).toFixed(1)}%`;
}
export function metricChange(baseline:string|number|null|undefined,current:string|number|null|undefined):Change{
  if(baseline===null||baseline===undefined||current===null||current===undefined)return {baseline:baseline==null?null:String(baseline),current:current==null?null:String(current),delta:null,percent_change:null};
  const b=Number(baseline);const c=Number(current);return {baseline:String(baseline),current:String(current),delta:String(c-b),percent_change:b===0?null:String((c-b)*100/Math.abs(b))};
}
export function supportingRunsHref(drilldown:Record<string,string>){const q=new URLSearchParams({tab:'executions',...drilldown});return '/agents?'+q.toString();}
export const EVIDENCE_STATE_LABEL:Record<string,string>={sufficient:'Sufficient evidence',limited_sample:'Limited sample',insufficient_data:'Insufficient data',unsupported_comparison:'Unsupported comparison',no_data:'No data',incomplete_cost_data:'Incomplete cost data'};
export const INSIGHT_TYPE_LABEL:Record<string,string>={retry_increase:'Retry increase',success_rate_decline:'Success-rate decline',cost_per_success_increase:'Cost per success',input_token_spike:'Input tokens',output_token_spike:'Output tokens',duration_increase:'Duration',model_cost_concentration:'Model cost concentration',failed_run_spend:'Failed-run spend',pricing_coverage_gap:'Pricing coverage'};
