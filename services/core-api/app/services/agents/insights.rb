module Agents
  # Slice 9B. Kotlin supplies operational facts, comparison windows, thresholds and operational findings for the
  # policy-derived population; this class adds corrected ledger cost, the cost-based findings, the cost-driver
  # breakdown and wording. Nothing is persisted and no financial record is written.
  class Insights
    ORDER={'critical'=>0,'warning'=>1,'info'=>2}.freeze
    LIMITATIONS=[
      'Findings describe measured changes between two periods. They do not establish why a change happened.',
      'Tokens and cost are linked to whole runs, not to individual attempts; cost cannot be attributed to a specific retry.',
      'Cost is corrected posted ledger expenditure. Unpriced or undelivered usage has unknown cost and is never counted as zero.',
      'Rate-only comparisons are hypothetical modeled figures, not ledger expenditure, and assume identical token counts.',
      'Demo outcomes marked synthetic are simulated operational records, not measured productivity or business results.',
      'Thresholds are documented demonstration defaults, not statistical significance tests.'
    ].freeze
    def initialize(policy,params,client:UsageClient.new);@policy=policy;@scope=Scope.new(policy,params,keys:Scope::INSIGHT_KEYS);@client=client end
    def call
      f=@scope.filters
      base=@scope.base_payload(window_start:@scope.explicit_range? ? @scope.start.iso8601 : nil,window_end:@scope.explicit_range? ? @scope.finish.iso8601 : nil)
      usage=@client.call(base.merge(compare:f['compare']||'previous_period'),path:'agent-insights')
      raise ActiveRecord::RecordNotFound unless usage['agent_visible']
      @t=usage['thresholds'];current=usage['current_period'];baseline=usage['comparison_period']
      aggregator=CostAggregator.new(@scope,client:@client)
      @cost={'current'=>aggregator.call(@scope.base_payload(window_start:current['start'],window_end:current['end']),bucket:usage['trend_bucket']),
             'baseline'=>aggregator.call(@scope.base_payload(window_start:baseline['start'],window_end:baseline['end']),bucket:usage['trend_bucket'])}
      insights=usage['insights'].map(&:dup)
      agents=usage['agents'].map do |agent|
        sides=%w[baseline current].index_with{|period|enrich(agent[period],@cost[period].agents.fetch(agent['id'],nil))}
        models=agent['models'].map{|m|m.merge('current_cost'=>model_cost('current',agent['id'],m),'baseline_cost'=>model_cost('baseline',agent['id'],m))}
        row=agent.merge(sides).merge('models'=>models,'cost_change'=>change(sides['baseline']['cost_per_success'],sides['current']['cost_per_success']),'decomposition'=>decomposition(sides['baseline'],sides['current'],models))
        insights.concat(cost_insights(row))
        row
      end
      names=agents.to_h{|a|[a['id'],a]}
      insights.each do |i|
        agent=names.fetch(i['agent_id'])
        i['id']="#{i['type'].tr('_','-')}-#{i['agent_id']}";i['agent_name']=agent['name'];i['agent_key']=agent['agent_key'];i['workflow_type']=agent['workflow_type'];i['status']='open'
        i['finding']=InsightText.finding(i);i['suggested_action']=InsightText::ACTIONS.fetch(i['type']);i['limitation']=InsightText::LIMITS[i['type']];i['evidence_quality_label']=InsightText.quality_label(i['evidence_quality'])
        i['time_window']=current;i['comparison_window']=baseline;i['financial_coverage']={'baseline'=>agent['baseline']['cost_completeness'],'current'=>agent['current']['cost_completeness']}
        i['associated']=associated(i,agent)
        i['drilldown']={'agent_id'=>i['agent_id'],'start'=>current['start'],'end'=>current['end']}.merge({'retry_increase'=>{'retried'=>'true'},'failed_run_spend'=>{'outcome'=>'failure'},'success_rate_decline'=>{'outcome'=>'failure'}}.fetch(i['type'],{}))
      end
      all=insights.sort_by{|i|[ORDER.fetch(i['severity']),i['agent_name'],i['type']]}
      shown=all.select{|i|%w[insight_type severity evidence_quality].all?{|key|f[key].nil?||i[key=='insight_type' ? 'type' : key]==f[key]}}
      totals=%w[baseline current].index_with{|period|enrich(usage['totals'][period],@cost[period].total)}
      trend=usage['trend'].map{|row|enrich(row,@cost[row['period']].buckets.fetch(row['bucket'],nil))}
      {'schema_version'=>1,'analysis_version'=>usage['analysis_version'],'currency'=>'USD','compare'=>usage['compare'],'current_period'=>current,'comparison_period'=>baseline,
       'partial_current_period'=>usage['partial_current_period'],'comparison_basis'=>usage['comparison_basis'],'trend_bucket'=>usage['trend_bucket'],
       'scope'=>{'persona'=>@policy.persona,'organization_id'=>@policy.organization_id,'identity_id'=>@policy.actor.id,'scope_key'=>@policy.access_summary[:scope_key],'filters'=>f.slice('agent_id','project_id','user_id','workflow_type','insight_type','severity','evidence_quality'),
                 'projects'=>@policy.projects.order(:name).limit(100).pluck(:id,:name).map{|id,name|{'id'=>id,'name'=>name}},'workflow_types'=>agents.map{|a|a['workflow_type']}.uniq.sort,'available_range'=>usage['available_range']},
       'summary'=>{'findings'=>shown.size,'total_findings'=>all.size,'by_severity'=>ORDER.keys.index_with{|s|shown.count{|i|i['severity']==s}},'requiring_attention'=>shown.count{|i|i['severity']!='info'},
                   'agents_analyzed'=>agents.size,'agents_without_comparison'=>agents.count{|a|!%w[sufficient limited_sample].include?(a['evidence_state'])},'baseline'=>totals['baseline'],'current'=>totals['current'],
                   'cost_per_success_change'=>change(totals['baseline']['cost_per_success'],totals['current']['cost_per_success']),'cost_change'=>change(totals['baseline']['corrected_modeled_cost'],totals['current']['corrected_modeled_cost'])},
       'insights'=>shown,'agents'=>agents,'trend'=>trend,
       'coverage'=>%w[baseline current].index_with{|period|totals[period].slice('runs','usage_events','priced_events','unpriced_events','pending_delivery','pricing_coverage_percent','cost_completeness','costed_runs','synthetic_runs').merge('telemetry'=>telemetry(totals[period]),'cohort_pages'=>@cost[period].pages)},
       'thresholds'=>@t,'limitations'=>LIMITATIONS,'money_basis'=>'Corrected posted ledger expenditure (original charges plus correction descendants), attributed to whole runs by organization, source and run ID.'}
    end
    private
    def money(value)=value.nil? ? nil : Finance::Money.string(value.round(15))
    def dec(value)=value.nil? ? nil : BigDecimal(value.to_s)
    def percent(part,whole)=whole.nil?||whole.zero? ? nil : Finance::Money.string((part*100/whole).round(4))
    def telemetry(side)=side['runs'].to_i.zero? ? 'none' : side['synthetic_runs'].to_i==side['runs'].to_i ? 'synthetic_fixture' : side['synthetic_runs'].to_i.zero? ? 'observed' : 'mixed'
    # Adds ledger-derived cost to one operational metric row. Rates and per-run token metrics stay Kotlin-owned.
    def enrich(metric,tally)
      tally||=CostAggregator.tally;runs=metric['runs'].to_i;successes=metric['successful_runs'].to_i;cost=tally[:cost]
      completeness=metric['usage_events'].to_i.zero? ? 'no_linked_usage' : metric['unpriced_events'].to_i.zero?&&metric['pending_delivery'].to_i.zero? ? 'complete' : 'partial_unpriced_or_unposted'
      metric.merge('corrected_modeled_cost'=>money(cost),'original_modeled_cost'=>money(tally[:original]),'adjustments'=>money(cost-tally[:original]),'costed_runs'=>tally[:costed_runs],
        'cost_per_success'=>successes.positive? ? money(cost/successes) : nil,'average_successful_run_cost'=>successes.positive? ? money(tally[:success_cost]/successes) : nil,'cost_per_run'=>runs.positive? ? money(cost/runs) : nil,
        'failed_run_cost'=>money(tally[:failed_cost]),'cancelled_run_cost'=>money(tally[:cancelled_cost]),'retried_success_cost'=>money(tally[:retried_success_cost]),'failed_run_cost_share_percent'=>percent(tally[:failed_cost],cost),'cost_completeness'=>completeness)
    end
    def model_cost(period,agent_id,model)=(costs=@cost[period].models[agent_id];costs.key?([model['provider'],model['model']]) ? money(costs[[model['provider'],model['model']]]) : nil)
    # Zero or missing baselines give a null percentage, never infinity; a negative baseline uses its magnitude.
    def change(baseline,current)
      b=dec(baseline);c=dec(current);return {'baseline'=>baseline,'current'=>current,'delta'=>nil,'percent_change'=>nil} if b.nil?||c.nil?
      {'baseline'=>baseline,'current'=>current,'delta'=>money(c-b),'percent_change'=>b.zero? ? nil : Finance::Money.string(((c-b)*100/b.abs).round(4))}
    end
    def complete?(agent)=%w[baseline current].all?{|p|agent[p]['cost_completeness']=='complete'}
    def insight(agent,type,metric,unit,baseline,current,severity,quality,reason,evidence,threshold)
      delta=baseline&&current ? dec(current)-dec(baseline) : nil
      {'type'=>type,'agent_id'=>agent['id'],'metric'=>metric,'unit'=>unit,'baseline'=>baseline,'current'=>current,'absolute_change'=>delta&&money(delta),
       'percent_change'=>baseline&&current&&dec(baseline).positive? ? Finance::Money.string((delta*100/dec(baseline)).round(4)) : nil,'threshold'=>threshold,'severity'=>severity,'evidence_quality'=>quality,'quality_reason'=>reason,
       'sample_size'=>{'baseline_runs'=>agent['baseline']['runs'],'current_runs'=>agent['current']['runs'],'basis'=>'runs'},'evidence'=>evidence}
    end
    def cost_insights(agent)
      b=agent['baseline'];c=agent['current'];found=[];comparable=%w[sufficient limited_sample].include?(agent['evidence_state'])
      cost_keys=%w[runs successful_runs failed_runs corrected_modeled_cost original_modeled_cost adjustments cost_per_success cost_completeness unpriced_events pending_delivery]
      # Cost per success: asserted only with a sufficient sample AND complete cost coverage in both periods.
      if comparable&&b['cost_per_success']&&c['cost_per_success']&&dec(b['cost_per_success']).positive?
        rise=(dec(c['cost_per_success'])-dec(b['cost_per_success']))*100/dec(b['cost_per_success']);limit=dec(@t['cost_per_success_increase_percent'])
        if rise>=limit
          quality=agent['evidence_state']=='limited_sample' ? 'limited_sample' : complete?(agent) ? 'sufficient' : 'incomplete_cost_data'
          reason=quality=='incomplete_cost_data' ? 'Based on known posted cost only: some linked usage is unpriced or undelivered, so the true change is unknown.' : agent['evidence_reason']
          severity=quality!='sufficient' ? 'info' : rise>=limit*dec(@t['critical_multiplier']) ? 'critical' : 'warning'
          found<<insight(agent,'cost_per_success_increase','cost_per_success','usd',b['cost_per_success'],c['cost_per_success'],severity,quality,reason,{'baseline'=>b.slice(*cost_keys),'current'=>c.slice(*cost_keys),'source'=>'Rails ledger entries for posted run-linked charges and their correction descendants, divided by explicit successes.'},{'kind'=>'percent','value'=>@t['cost_per_success_increase_percent']})
        end
      end
      # Failed-run spend: descriptive share of the current period's known cost, on a sufficient current sample.
      share=dec(c['failed_run_cost_share_percent'])
      if share&&share>=dec(@t['failed_run_cost_share_percent'])&&c['runs'].to_i>=@t['min_runs'].to_i
        quality=c['cost_completeness']=='complete' ? 'sufficient' : 'incomplete_cost_data'
        keys=%w[runs failed_runs corrected_modeled_cost failed_run_cost cancelled_run_cost retried_success_cost retried_runs]
        found<<insight(agent,'failed_run_spend','failed_run_cost_share_percent','percent',b['failed_run_cost_share_percent'],c['failed_run_cost_share_percent'],quality=='sufficient' ? 'warning' : 'info',quality,
          quality=='sufficient' ? "#{c['runs']} current runs with complete cost coverage." : 'Share of known posted cost only; some linked usage is unpriced or undelivered.',
          {'baseline'=>b.slice(*keys),'current'=>c.slice(*keys),'categories'=>{'failed_logical_runs'=>c['failed_run_cost'],'successful_runs_that_required_retries'=>c['retried_success_cost'],'failed_retry_attempts'=>nil},'source'=>'Whole-run ledger cost grouped by explicit final outcome. Failed attempts inside other runs have no attributable cost.'},{'kind'=>'share_percent','value'=>@t['failed_run_cost_share_percent']})
      end
      # Model cost concentration: descriptive only, and only where the agent actually used more than one costed model.
      costed=agent['models'].select{|m|m['current_cost']&&dec(m['current_cost']).positive?};total=costed.sum{|m|dec(m['current_cost'])}
      if costed.size>1&&c['runs'].to_i>=@t['min_runs'].to_i
        top=costed.max_by{|m|[dec(m['current_cost']),m['model']]};top_share=dec(top['current_cost'])*100/total
        if top_share>=dec(@t['model_cost_share_percent'])
          quality=c['cost_completeness']=='complete' ? 'sufficient' : 'incomplete_cost_data'
          previous=dec(top['baseline_cost']);previous_total=agent['models'].sum{|m|dec(m['baseline_cost'])||0}
          scenario=top['rate_only_scenario']&.merge('assumptions'=>['Same input tokens','Same output tokens','Same cached-input tokens'],'does_not_account_for'=>InsightText::SCENARIO_EXCLUSIONS,'not_ledger_expenditure'=>true)
          found<<insight(agent,'model_cost_concentration','model_cost_share_percent','percent',previous&&previous_total.positive? ? Finance::Money.string((previous*100/previous_total).round(4)) : nil,Finance::Money.string(top_share.round(4)),'info',quality,
            quality=='sufficient' ? "#{c['runs']} current runs with complete cost coverage." : 'Share of known posted cost only; some linked usage is unpriced or undelivered.',
            {'model'=>"#{top['provider']}/#{top['model']}",'models'=>costed.map{|m|{'model'=>"#{m['provider']}/#{m['model']}",'current_cost'=>m['current_cost'],'baseline_cost'=>m['baseline_cost'],'current_token_share_percent'=>m.dig('current','token_share_percent'),'baseline_token_share_percent'=>m.dig('baseline','token_share_percent')}},'savings_scenario'=>scenario||{'estimated_savings'=>nil,'reason'=>'Unavailable: no cheaper published schedule on the same pricing tier, or the model has mixed pricing profiles.'},'source'=>'Rails ledger cost grouped by the original provider/model recorded on each posted receipt.'},{'kind'=>'share_percent','value'=>@t['model_cost_share_percent']})
        end
      end
      if c['unpriced_events'].to_i.positive?||c['pending_delivery'].to_i.positive?
        gaps=agent['models'].filter_map{|m|cur=m['current'];next unless cur&&cur['events'].to_i>cur['priced_events'].to_i;{'model'=>"#{m['provider']}/#{m['model']}",'events'=>cur['events'],'unpriced_events'=>cur['events'].to_i-cur['priced_events'].to_i}}
        found<<insight(agent,'pricing_coverage_gap','pricing_coverage_percent','percent',b['pricing_coverage_percent'],c['pricing_coverage_percent'],'warning','incomplete_cost_data','Cost figures for this agent cover priced, delivered usage only.',
          {'baseline'=>b.slice('usage_events','priced_events','unpriced_events','pending_delivery'),'current'=>c.slice('usage_events','priced_events','unpriced_events','pending_delivery'),'unpriced_models'=>gaps,'source'=>'Canonical usage events joined to immutable pricing snapshots and delivery status.'},nil)
      end
      found
    end
    # Neutral co-observations shown beside a finding. They are facts about the same two periods, not causes.
    def associated(insight,agent)
      b=agent['baseline'];c=agent['current']
      pairs={'cost_per_success'=>['Cost per successful run','usd'],'retry_rate_percent'=>['Retry rate','percent'],'success_rate_percent'=>['Success rate','percent'],'output_tokens_per_run'=>['Output tokens per run','tokens'],'input_tokens_per_run'=>['Input tokens per run','tokens'],'runs'=>['Runs','count']}
      pairs.filter_map{|metric,(label,unit)|next if metric==insight['metric']||b[metric].nil?||c[metric].nil?;{'metric'=>metric,'label'=>label,'unit'=>unit}.merge(change(b[metric].to_s,c[metric].to_s))}
    end
    # Cost change split exactly into volume (run-count change at the baseline cost per run) and per-run change
    # (at current volume); the two sum to the ledger delta by construction. Everything else is an associated factor.
    def decomposition(b,c,models)
      return nil if b['runs'].to_i.zero?||c['runs'].to_i.zero?
      cost_b=dec(b['corrected_modeled_cost']);cost_c=dec(c['corrected_modeled_cost']);delta=cost_c-cost_b;volume=(c['runs'].to_i-b['runs'].to_i)*cost_b/b['runs'].to_i;per_run=delta-volume
      factors=[['runs','Run volume','count'],['input_tokens_per_run','Input tokens per run','tokens'],['output_tokens_per_run','Output tokens per run','tokens'],['retry_rate_percent','Retry rate','percent'],['success_rate_percent','Success rate','percent'],['failed_run_cost','Cost of failed runs','usd'],['adjustments','Financial corrections','usd']]
      mix=models.filter_map{|m|bs=m.dig('baseline','token_share_percent');cs=m.dig('current','token_share_percent');next if bs.nil?&&cs.nil?;{'model'=>"#{m['provider']}/#{m['model']}",'pricing_model'=>m['pricing_model']&&"#{m['pricing_provider']}/#{m['pricing_model']}",'baseline_token_share_percent'=>bs,'current_token_share_percent'=>cs,'baseline_cost'=>m['baseline_cost'],'current_cost'=>m['current_cost'],'rate_schedule_changed'=>m['rate_schedule_changed']}}
      {'basis'=>[b,c].all?{|s|s['cost_completeness']=='complete'} ? 'complete_corrected_ledger_cost' : 'known_posted_cost_only',
       'cost'=>change(b['corrected_modeled_cost'],c['corrected_modeled_cost']),
       'exact'=>{'method'=>'Volume effect = change in runs x baseline cost per run; per-run effect = remainder. The two sum exactly to the cost change.','volume_effect'=>money(volume),'per_run_cost_effect'=>money(per_run),'baseline_cost_per_run'=>b['cost_per_run'],'current_cost_per_run'=>c['cost_per_run']},
       'associated_factors'=>factors.map{|metric,label,unit|{'metric'=>metric,'label'=>label,'unit'=>unit,'attribution'=>'associated'}.merge(change(b[metric]&.to_s,c[metric]&.to_s))},
       'model_mix'=>mix,'note'=>'Per-run factors interact, so they are listed as associated changes rather than assigned exact dollar amounts.'}
    end
  end
end
