export type Metric = { events:number; priced_events:number; unpriced_events:number; input_tokens:string|number; output_tokens:string|number; cached_input_tokens:string|number; active_users:number; net_expenditure:string; original_expenditure:string; adjustments:string; };
export type Breakdown = Metric & {id:string|null;name?:string;job_function?:string;home_unit_id?:string;active_projects?:number;attributed_projects?:number;cost_share_percent?:string|null;provider?:string;model?:string;pricing_model?:string;pricing_provider?:string;billing_basis?:string;bucket?:string};
export type Comparison = {recorded_coverage:string;finance_change:{current:string;previous:string;delta:string;percent_change:string|null;basis:string};token_components:Record<string,{current:number;previous:number;delta:number}>;state:string;percent_change:string|null;current_tokens:number;previous_tokens:number;delta_tokens:number;current_start:string;current_end:string;previous_start:string;previous_end:string;contributors:Record<string,{id:string|string[];label:string;tokens:number;previous_tokens:number;delta_tokens:number}[]>};
export type Account = {id:string;name:string;purpose:string;funding:string;expenditure:string;remaining:string;utilization_percent:string|null;over_budget:boolean};
export type AnalyticsReport = {schema_version:1;currency:string;summary:Metric & {total_tokens:number;pricing_coverage_percent:string|null;unsupported_profiles:number;missing_rates:number;pending_delivery:number;unresolved_charge_owner:number};timeseries:Breakdown[];employees:Breakdown[];teams:Breakdown[];projects:Breakdown[];models:Breakdown[];tools:Breakdown[];accounts:Account[]|null;budget:{funding:string;expenditure:string;remaining:string;utilization_percent:string|null}|null;comparisons:Record<string,Comparison>;transactions:{rows:{transaction_id:string;kind:string;user_id:string;project_id:string|null;occurred_at:string;posted_at:string;month_start:string;expense_delta:string}[];total:number;limit:number;offset:number};context:{scope:string;organization_id:string;identity_id:string;scope_key:string;start:string;end:string;granularity:string;available_range:{start:string|null;end:string|null};units:{id:string;name:string;parent_id:string|null;type:string}[];projects:{id:string;name:string}[];people:{id:string;name:string}[];financial_label:string;team_basis:string}};
// Decimal strings are rounded for presentation with integer arithmetic only.
export function money(value:string,places=4) {
  const negative=value.startsWith('-');const [whole,fraction='']=value.replace(/^-/, '').split('.');
  const digits=(fraction+'0'.repeat(places+1)).slice(0,places+1);
  let scaled=BigInt(whole||'0')*10n**BigInt(places)+BigInt(digits.slice(0,places)||'0');
  if(Number(digits[places])>=5)scaled+=1n;
  const s=scaled.toString().padStart(places+1,'0');
  return `${negative&&scaled!==0n?'-':''}$${BigInt(s.slice(0,-places)||'0').toLocaleString('en-US')}.${s.slice(-places)}`;
}
export function count(value:number|string) {return Number(value).toLocaleString('en-US');}
export function tokens(row:Metric) {return Number(row.input_tokens)+Number(row.output_tokens);}
export function dateLabel(value:string) {return value.slice(0,10);}
export function presetRange(preset:string,anchor:string):[string,string] {
  const end=new Date(anchor);end.setUTCHours(0,0,0,0);const start=new Date(end);
  if(preset==='month'){start.setUTCDate(1);end.setUTCMonth(end.getUTCMonth()+1,1);}
  else if(preset==='previous'){end.setUTCDate(1);start.setUTCMonth(end.getUTCMonth()-1,1);}
  else start.setUTCDate(start.getUTCDate()-Number(preset));
  return [start.toISOString(),end.toISOString()];
}
