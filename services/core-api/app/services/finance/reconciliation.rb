module Finance
  class Reconciliation
    def receipts(ids)
      records = PricedUsageReceipt.where(id: ids).includes(:financial_transaction).index_by(&:id)
      roots = records.values.filter_map(&:financial_transaction_id)
      totals = {}
      unless roots.empty?
        quoted = roots.map { |id| ApplicationRecord.connection.quote(id) }.join(",")
        rows = ApplicationRecord.connection.select_all(<<~SQL)
          WITH RECURSIVE family(root_id,id) AS (
            SELECT id,id FROM business.financial_transactions WHERE id IN (#{quoted})
            UNION ALL SELECT f.root_id,t.id FROM business.financial_transactions t JOIN family f ON t.original_transaction_id=f.id
          ) SELECT f.root_id,COALESCE(SUM(e.expense_delta),0) AS net,
            COALESCE(SUM(CASE WHEN f.id=f.root_id THEN e.expense_delta ELSE 0 END),0) AS original_ledger,
            COALESCE(SUM(CASE WHEN f.id<>f.root_id THEN e.expense_delta ELSE 0 END),0) AS adjustments
          FROM family f LEFT JOIN business.ledger_entries e ON e.financial_transaction_id=f.id GROUP BY f.root_id
        SQL
        totals = rows.index_by { |row| row["root_id"] }
      end
      ids.map do |id|
        record = records[id]
        next { priced_event_id: id, status: "missing" } unless record
        tx = record.financial_transaction
        sum = totals.fetch(tx&.id, {})
        { priced_event_id: id, usage_event_id: record.usage_event_id, posted_usage_event_id: tx&.usage_event_id, status: record.status, code: record.resolution_code, payload_fingerprint: record.payload_fingerprint,
          original_amount: Money.string(tx&.amount || record.amount), original_ledger_amount: Money.string(sum.fetch("original_ledger",0)), net_amount: Money.string(sum.fetch("net",0)),
          adjustment_delta: Money.string(sum.fetch("adjustments",0)), financial_transaction_id: record.financial_transaction_id }
      end
    end
    def expense_tree(id)
      quoted = ApplicationRecord.connection.quote(id)
      ApplicationRecord.connection.select_value(<<~SQL) || BigDecimal("0")
        WITH RECURSIVE family(id) AS (
          SELECT id FROM business.financial_transactions WHERE id=#{quoted}
          UNION ALL SELECT t.id FROM business.financial_transactions t JOIN family f ON t.original_transaction_id=f.id
        ) SELECT COALESCE(SUM(e.expense_delta),0) FROM business.ledger_entries e JOIN family f ON f.id=e.financial_transaction_id
      SQL
    end
    def integrity
      connection = ApplicationRecord.connection
      {
        invalid_operation_entries: connection.select_value("SELECT COUNT(*) FROM (SELECT t.id FROM business.financial_transactions t LEFT JOIN business.ledger_entries e ON e.financial_transaction_id=t.id GROUP BY t.id HAVING (t.kind='funding' AND (COUNT(e.id)<>1 OR COALESCE(SUM(e.funding_delta),0)<>t.amount OR COALESCE(SUM(e.expense_delta),0)<>0)) OR (t.kind IN ('usage_charge','adjustment','reversal') AND (COUNT(e.id)<>1 OR COALESCE(SUM(e.funding_delta),0)<>0 OR COALESCE(SUM(e.expense_delta),0)<>(CASE WHEN t.kind='reversal' THEN -t.amount ELSE t.amount END)))) x").to_i,
        duplicate_expenses: connection.select_value("SELECT COUNT(*) FROM (SELECT usage_event_id FROM business.financial_transactions WHERE kind='usage_charge' GROUP BY usage_event_id HAVING COUNT(*)>1) x").to_i,
        unbalanced_transfers: connection.select_value("SELECT COUNT(*) FROM (SELECT t.id FROM business.financial_transactions t LEFT JOIN business.ledger_entries e ON e.financial_transaction_id=t.id WHERE t.kind='transfer' GROUP BY t.id HAVING COUNT(e.id)<>2 OR COALESCE(SUM(e.funding_delta),0)<>0 OR COALESCE(SUM(e.expense_delta),0)<>0) x").to_i,
        posted_receipts_missing_transactions: PricedUsageReceipt.where(status: "posted").where.not(financial_transaction_id: FinancialTransaction.where(kind: "usage_charge").select(:id)).count
      }
    end
    def report(actor, month)
      raise Forbidden, "Explicit financial operator authority is required" unless actor.status == "active" && AccessPolicy.new(actor).financial_operator?
      periods = BudgetPeriod.where(organization_id: actor.organization_id, month_start: Money.month(month)).includes(:budget_account)
      rows = periods.map do |period|
        { account_id: period.budget_account_id, name: period.budget_account.name, purpose: period.budget_account.purpose, funding: Money.string(period.funding), expenditure: Money.string(period.expenditure), available: Money.string(period.available), over_budget: period.available.negative? }
      end
      { organization_id: actor.organization_id, month: month, currency: "USD", accounts: rows, funding: Money.string(periods.sum { |p| p.funding }), net_expenditure: Money.string(periods.sum { |p| p.expenditure }), unresolved_receipts: PricedUsageReceipt.where(organization_id: actor.organization_id, status: "unresolved").count, integrity: integrity }
    end
  end
end
