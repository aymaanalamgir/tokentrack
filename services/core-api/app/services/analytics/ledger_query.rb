module Analytics
  class LedgerQuery
    def initialize(scope)
      @scope=scope
      @connection=ApplicationRecord.connection
    end
    def cte(from=@scope.start,to=@scope.finish,activity:true)
      range=activity ? "AND r.occurred_at>=#{@connection.quote(from)} AND r.occurred_at<#{@connection.quote(to)}" : ''
      <<~SQL
        WITH RECURSIVE roots AS (
          SELECT t.id,r.id AS receipt_id,r.user_id,r.project_id,r.occurred_at,r.payload,t.home_unit_id FROM business.priced_usage_receipts r
          JOIN business.financial_transactions t ON t.id=r.financial_transaction_id WHERE r.status='posted' AND #{@scope.sql} #{range}
        ), family(root_id,id) AS (
          SELECT id,id FROM roots UNION ALL
          SELECT f.root_id,t.id FROM family f JOIN business.financial_transactions t ON t.original_transaction_id=f.id
        ), expenses AS (
          SELECT r.*,t.id AS transaction_id,t.kind,t.created_at AS posted_at,t.month_start,e.budget_period_id,e.expense_delta,e.funding_delta,
            CASE WHEN t.kind='usage_charge' THEN e.expense_delta ELSE 0 END AS original,
            CASE WHEN t.kind<>'usage_charge' THEN e.expense_delta ELSE 0 END AS adjustment
          FROM roots r JOIN family f ON f.root_id=r.id JOIN business.financial_transactions t ON t.id=f.id JOIN business.ledger_entries e ON e.financial_transaction_id=t.id
        )
      SQL
    end
    def rows(sql) = @connection.select_all(sql).to_a
    def totals(from=@scope.start,to=@scope.finish)
      row=rows(cte(from,to)+"SELECT COALESCE(SUM(original),0) AS original_expenditure,COALESCE(SUM(adjustment),0) AS adjustments,COALESCE(SUM(expense_delta),0) AS net_expenditure FROM expenses").first
      row.transform_values{|v|Finance::Money.string(v)}
    end
    def groups(expression, group_by=expression)
      rows(cte+"SELECT #{expression},SUM(original) AS original_expenditure,SUM(adjustment) AS adjustments,SUM(expense_delta) AS net_expenditure FROM expenses GROUP BY #{group_by}").map{|r|r.transform_values.with_index{|v,_|v.is_a?(BigDecimal) ? Finance::Money.string(v) : v}}
    end
    def timeseries
      groups("date_trunc('#{@scope.grain}',occurred_at)::text AS bucket", "bucket").map { |row| row.merge("bucket"=>row["bucket"][0,10]+"T00:00:00Z") }
    end
    def transactions
      from=@scope.filters['audit_start'] ? @scope.parse_time(@scope.filters['audit_start']) : @scope.start
      to=@scope.filters['audit_end'] ? @scope.parse_time(@scope.filters['audit_end']) : @scope.finish
      raise Invalid,'Invalid posting-time range' unless from<to && to-from<=366.days
      base=cte(activity:false)+"SELECT transaction_id,kind,user_id,project_id,home_unit_id,occurred_at,posted_at,month_start,expense_delta FROM expenses WHERE posted_at>=#{@connection.quote(from)} AND posted_at<#{@connection.quote(to)}"
      count=rows("SELECT COUNT(*) AS n FROM (#{base}) q").first['n'].to_i
      records=rows(base+" ORDER BY posted_at DESC,transaction_id LIMIT #{@scope.limit} OFFSET #{@scope.offset}").map{|r|r.merge('expense_delta'=>Finance::Money.string(r['expense_delta']))}
      {rows:records,total:count,limit:@scope.limit,offset:@scope.offset,date_basis:'posting_time'}
    end
  end
end
