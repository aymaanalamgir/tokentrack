module Agents
  # Presentation wording only. Every number shown is computed elsewhere; nothing here asserts a cause.
  module InsightText
    module_function
    ACTIONS={
      'retry_increase'=>'Inspect recent provider-error and timeout patterns before changing retry policy; some retries preserve successful outcomes.',
      'success_rate_decline'=>'Review the failed and cancelled runs in this period and their recorded error categories.',
      'cost_per_success_increase'=>'Review the cost-driver breakdown (volume, tokens per run, model mix, retries, success rate) before changing the workflow.',
      'input_token_spike'=>'Review prompt and context size for this workflow; confirm whether the additional input is required.',
      'output_token_spike'=>'Review response-length requirements or unnecessary output generation; shorter output is not guaranteed to preserve quality.',
      'duration_increase'=>'Inspect slow runs and their attempt history for timeouts or added steps.',
      'model_cost_concentration'=>"Evaluate whether a less expensive model can meet this workflow's quality requirements; substitution is not guaranteed to reduce end-to-end cost or preserve success.",
      'failed_run_spend'=>'Inspect recurring error categories and failed execution paths.',
      'pricing_coverage_gap'=>'Resolve unsupported pricing profiles or pending delivery before treating cost-efficiency figures for this agent as complete.'
    }.freeze
    LIMITS={
      'retry_increase'=>'Retries are recorded per attempt, but tokens and cost are linked per run, so no cost is attributed to individual retries.',
      'cost_per_success_increase'=>'Several measured factors can change together; the breakdown lists associated changes and does not single out a cause.',
      'model_cost_concentration'=>'A descriptive share of spending. It is not evidence that the model is inefficient.',
      'failed_run_spend'=>'Cost is attributed to whole logical runs. Failed attempts inside runs that later succeeded cannot be costed separately.',
      'pricing_coverage_gap'=>'Unpriced or undelivered usage has unknown cost; it is not counted as zero.'
    }.freeze
    SCENARIO_EXCLUSIONS=['Different model behaviour or output','Response quality','Success and retry rates','Latency','Provider-specific fees not in the published schedule','Changes in tokenization'].freeze
    def percent(value)=value.nil? ? 'N/A' : "#{format('%.1f',BigDecimal(value.to_s))}%"
    def money(value)=value.nil? ? 'N/A' : "$#{format('%.4f',BigDecimal(value.to_s))}"
    def signed(value,suffix)="#{BigDecimal(value.to_s).negative? ? '' : '+'}#{format('%.1f',BigDecimal(value.to_s))}#{suffix}"
    def finding(insight)
      b=insight['baseline'];c=insight['current']
      case insight['type']
      when 'retry_increase' then "Retry rate increased #{format('%.1f',BigDecimal(insight['absolute_change']))} percentage points (#{percent(b)} to #{percent(c)})."
      when 'success_rate_decline' then "Success rate fell #{format('%.1f',BigDecimal(insight['absolute_change']).abs)} percentage points (#{percent(b)} to #{percent(c)})."
      when 'cost_per_success_increase' then "Cost per successful run increased #{signed(insight['percent_change'],'%')} (#{money(b)} to #{money(c)})."
      when 'input_token_spike' then "Input tokens per run increased #{signed(insight['percent_change'],'%')} (#{BigDecimal(b).round.to_i} to #{BigDecimal(c).round.to_i})."
      when 'output_token_spike' then "Output tokens per run increased #{signed(insight['percent_change'],'%')} (#{BigDecimal(b).round.to_i} to #{BigDecimal(c).round.to_i})."
      when 'duration_increase' then "Median run duration increased #{signed(insight['percent_change'],'%')} (#{format('%.1f',BigDecimal(b))}s to #{format('%.1f',BigDecimal(c))}s)."
      when 'model_cost_concentration' then "#{insight.dig('evidence','model')} accounts for #{percent(c)} of this agent's corrected cost in the current period."
      when 'failed_run_spend' then "#{percent(c)} of known corrected cost (#{money(insight.dig('evidence','current','failed_run_cost'))}) is associated with failed runs."
      when 'pricing_coverage_gap' then "#{insight.dig('evidence','current','unpriced_events')} unpriced and #{insight.dig('evidence','current','pending_delivery')} undelivered usage events: cost visibility is incomplete (#{percent(c)} priced)."
      end
    end
    def quality_label(code)={'sufficient'=>'Sufficient evidence','limited_sample'=>'Limited sample','incomplete_cost_data'=>'Incomplete cost data','unsupported_comparison'=>'Unsupported comparison'}.fetch(code,code)
  end
end
