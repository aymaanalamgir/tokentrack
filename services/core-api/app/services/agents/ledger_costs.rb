module Agents
  # Corrected posted ledger expenditure for one bounded batch of runs. The batch is passed as two text arrays
  # (never a generated VALUES list) and resolved through the receipts run-link index; callers page the cohort.
  class LedgerCosts
    MAX_BATCH=1000
    def initialize(scope)=(@scope=scope;@connection=ApplicationRecord.connection)
    # => {[source,run_id]=>{net:BigDecimal,original:BigDecimal,models:{[provider,model]=>BigDecimal}}}; runs without posted cost are absent, not zero.
    def call(runs)
      pairs=runs.map{|r|[r['source'],r['run_id']]}.uniq
      return {} if pairs.empty?
      raise ArgumentError,'Ledger cost batches are bounded' if pairs.size>MAX_BATCH
      array=->(values){"ARRAY[#{values.map{|v|@connection.quote(v)}.join(',')}]::text[]"}
      sql=<<~SQL
        WITH RECURSIVE wanted(source,run_id) AS (SELECT * FROM unnest(#{array.call(pairs.map(&:first))},#{array.call(pairs.map(&:last))})), roots AS (
          SELECT t.id,w.source,w.run_id,r.payload->>'provider' provider,r.payload->>'model' model FROM wanted w
          JOIN business.priced_usage_receipts r ON r.organization_id=#{@connection.quote(@scope.policy.organization_id)} AND r.payload->>'source'=w.source AND r.payload->>'agent_run_id'=w.run_id
          JOIN business.financial_transactions t ON t.id=r.financial_transaction_id
          WHERE r.status='posted' AND #{@scope.sql('r')}
        ), family(root_id,id) AS (SELECT id,id FROM roots UNION ALL SELECT f.root_id,t.id FROM family f JOIN business.financial_transactions t ON t.original_transaction_id=f.id)
        SELECT roots.source,roots.run_id,roots.provider,roots.model,COALESCE(SUM(e.expense_delta),0) net,COALESCE(SUM(e.expense_delta) FILTER(WHERE f.id=f.root_id),0) original
        FROM roots JOIN family f ON f.root_id=roots.id JOIN business.ledger_entries e ON e.financial_transaction_id=f.id GROUP BY roots.source,roots.run_id,roots.provider,roots.model
      SQL
      @connection.select_all(sql).each_with_object({}) do |row,costs|
        entry=costs[[row['source'],row['run_id']]]||={net:BigDecimal(0),original:BigDecimal(0),models:Hash.new(BigDecimal(0))}
        net=BigDecimal(row['net'].to_s);entry[:net]+=net;entry[:original]+=BigDecimal(row['original'].to_s);entry[:models][[row['provider'],row['model']]]+=net
      end
    end
  end
end
