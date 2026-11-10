module Budgets
  module Controls
    module_function
    def utc(date) = Time.utc(date.year,date.month,date.day)
    def month(value)
      date=Finance::Money.month(value)
      raise Finance::Invalid,'Month must be within 2000–2099' unless date.year.between?(2000,2099)
      date
    end
    def key(value)
      raise Finance::Invalid,'A stable operation key is required' unless value.is_a?(String) && value.match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,127}\z/)
      value
    end
    def warning(used,ceiling,zero_state: 'zero_limit')
      used=BigDecimal(used.to_s);ceiling=BigDecimal(ceiling.to_s)
      thresholds=Rails.application.config.x.budget_thresholds || {approaching:75,high:90,reached:100}
      ratio=ceiling.positive? ? used*100/ceiling : nil
      state=if used>ceiling then 'over_budget'
      elsif ratio && ratio>=thresholds[:reached] then 'limit_reached'
      elsif ratio && ratio>=thresholds[:high] then 'high_utilization'
      elsif ratio && ratio>=thresholds[:approaching] then 'approaching_limit'
      elsif ceiling.zero? then zero_state else 'within_limit' end
      {limit:Finance::Money.string(ceiling),used:Finance::Money.string(used),remaining:Finance::Money.string(ceiling-used),utilization_percent:ratio && Finance::Money.string(ratio),overage:Finance::Money.string([used-ceiling,0].max),warning:state}
    end
    def forecast(used,month:,as_of:,coverage_incomplete:false,observed_days:0)
      used=BigDecimal(used.to_s);last=month.end_of_month
      return {status:'insufficient_data',projected:nil} unless as_of && as_of>=month && observed_days>=2
      date=[as_of,last].min;days=(date-month).to_i+1
      return {status:'insufficient_data',projected:nil} unless days.positive?
      return {status:'negative_corrections',projected:nil} if used.negative?
      projected=(used/days*last.day).round(15,BigDecimal::ROUND_HALF_EVEN)
      {status:date==last ? 'month_complete' : 'linear_estimate',projected:Finance::Money.string(projected),elapsed_days:days,days_in_month:last.day,as_of:date.to_s,coverage_incomplete:coverage_incomplete,method:'Net posted expense through as-of day / elapsed calendar days × days in month. Sparse or incomplete pricing can understate this estimate.'}
    end
  end
end
