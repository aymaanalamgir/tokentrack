# In-memory stand-in for the Kotlin usage engine. It honours the cohort paging contract (window, keyset cursor,
# bounded batch) so Rails aggregation is exercised against real PostgreSQL ledger rows without a network call.
class AgentUsageFake
  attr_reader :calls
  attr_accessor :runs,:insights,:report
  def initialize;@calls=[];@runs=[];@insights=nil;@report=nil end
  def call(payload,path:'agent-analytics')
    @calls<<[path,payload]
    case path
    when 'agent-cohort'
      raise ArgumentError,'unbounded batch' unless (1..1000).cover?(payload[:batch])
      rows=runs.select{|r|r['started_at']>=payload[:start]&&r['started_at']<payload[:end]}.sort_by{|r|[r['started_at'],r['run_id']]}
      rows=rows.select{|r|([r['started_at'],r['run_id']]<=>[payload[:after_started_at],payload[:after_id]])==1} if payload[:after_id]
      page=rows.first(payload[:batch])
      {'schema_version'=>1,'rows'=>page.map{|r|r.slice('source','run_id','agent_id','outcome','retried').merge('bucket'=>r['started_at'][0,10])},'next'=>page.size<payload[:batch] ? nil : {'after_started_at'=>page.last['started_at'],'after_id'=>page.last['run_id']}}
    when 'agent-insights' then insights.deep_dup
    else report.deep_dup
    end
  end
end
module AgentInsightHelpers
  THRESHOLDS={'min_runs'=>20,'min_runs_limited'=>8,'retry_rate_increase_points'=>'10','success_rate_decrease_points'=>'10','tokens_per_run_increase_percent'=>'30','duration_increase_percent'=>'30','cost_per_success_increase_percent'=>'25','model_cost_share_percent'=>'70','failed_run_cost_share_percent'=>'20','critical_multiplier'=>'2'}.freeze
  def metric_side(runs:,successes:runs,failed:0,retried:0,events:runs,unpriced:0,pending:0)
    {'runs'=>runs,'successful_runs'=>successes,'failed_runs'=>failed,'cancelled_runs'=>0,'incomplete_runs'=>runs-successes-failed,'retried_runs'=>retried,'retries'=>retried,'attempts'=>runs+retried,'concluded_runs'=>successes+failed,
     'success_rate_percent'=>runs.zero? ? nil : (successes*100.0/[successes+failed,1].max).round(4).to_s,'retry_rate_percent'=>runs.zero? ? nil : (retried*100.0/runs).round(4).to_s,'input_tokens_per_run'=>'1000','output_tokens_per_run'=>'100',
     'usage_events'=>events,'priced_events'=>events-unpriced,'unpriced_events'=>unpriced,'pending_delivery'=>pending,'pricing_coverage_percent'=>events.zero? ? nil : ((events-unpriced)*100.0/events).round(4).to_s,'linked_runs'=>runs,'synthetic_runs'=>0}
  end
  def insight_agent(id,name,baseline,current,state:'sufficient',models:[])
    {'id'=>id,'agent_key'=>name.parameterize,'name'=>name,'workflow_type'=>'code-review','baseline'=>baseline,'current'=>current,'evidence_state'=>state,'evidence_reason'=>"#{current['runs']} current and #{baseline['runs']} comparison runs.",'models'=>models}
  end
  def insights_response(agents,operational:[],visible:true)
    sum=->(period){keys=%w[runs successful_runs failed_runs usage_events priced_events unpriced_events pending_delivery synthetic_runs];agents.map{|a|a[period]}.each_with_object(Hash.new(0)){|side,total|keys.each{|k|total[k]+=side[k].to_i}}}
    {'schema_version'=>1,'analysis_version'=>1,'compare'=>'previous_period','current_period'=>{'start'=>'2026-11-15T00:00:00Z','end'=>'2026-12-01T00:00:00Z'},'comparison_period'=>{'start'=>'2026-11-01T00:00:00Z','end'=>'2026-11-15T00:00:00Z'},
     'partial_current_period'=>false,'comparison_basis'=>'equal_length_preceding_period','trend_bucket'=>'day','available_range'=>{'start'=>'2026-11-01T00:00:00Z','end'=>'2026-11-30T00:00:00Z'},'agent_visible'=>visible,'thresholds'=>THRESHOLDS,
     'totals'=>{'baseline'=>sum.call('baseline'),'current'=>sum.call('current')},'trend'=>[],'agents'=>agents,'insights'=>operational}
  end
end
RSpec.configure{|config|config.include AgentInsightHelpers}
