module Agents
  class LedgerCosts
    def initialize(scope)=(@scope=scope;@connection=ApplicationRecord.connection)
    def call(cohort)
      return {} if cohort.empty?
      pairs=cohort.map{|r|[r['source'],r['run_id']]}.uniq
      values=pairs.map{|source,run|"(#{@connection.quote(source)},#{@connection.quote(run)})"}.join(',')
      sql=<<~SQL
        WITH RECURSIVE wanted(source,run_id) AS (VALUES #{values}), roots AS (
          SELECT t.id,r.payload->>'source' source,r.payload->>'agent_run_id' run_id FROM business.priced_usage_receipts r
          JOIN business.financial_transactions t ON t.id=r.financial_transaction_id JOIN wanted w ON w.source=r.payload->>'source' AND w.run_id=r.payload->>'agent_run_id'
          WHERE r.status='posted' AND #{@scope.sql('r')} AND r.occurred_at>=#{@connection.quote(@scope.start)} AND r.occurred_at<#{@connection.quote(@scope.finish)}
        ), family(root_id,id) AS (SELECT id,id FROM roots UNION ALL SELECT f.root_id,t.id FROM family f JOIN business.financial_transactions t ON t.original_transaction_id=f.id)
        SELECT roots.source,roots.run_id,COALESCE(SUM(e.expense_delta),0) net_expenditure FROM roots JOIN family f ON f.root_id=roots.id JOIN business.ledger_entries e ON e.financial_transaction_id=f.id GROUP BY roots.source,roots.run_id
      SQL
      @connection.select_all(sql).to_a.to_h{|row|[[row['source'],row['run_id']],Finance::Money.string(row['net_expenditure'])]}
    end
  end
end
