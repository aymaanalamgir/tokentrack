class AddReceiptAgentRunIndex < ActiveRecord::Migration[8.1]
  # Additive lookup index for run-linked receipts so batched agent cost aggregation (Slice 9B) is an index probe
  # per run instead of a receipts scan per batch. No receipt, transaction or ledger row is changed.
  def up
    execute <<~SQL
      CREATE INDEX receipts_agent_run_link ON business.priced_usage_receipts (organization_id,(payload->>'source'),(payload->>'agent_run_id'))
      WHERE (payload->>'agent_run_id') IS NOT NULL
    SQL
  end
  def down = execute('DROP INDEX business.receipts_agent_run_link')
end
