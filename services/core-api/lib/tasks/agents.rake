namespace :agents do
  # Slice 9B scenario H: one explicit, idempotent correction of an agent-linked demo charge through the existing
  # Finance::Operations boundary. Local trusted demo operation only; the stable key makes repeats a no-op.
  task demo_correction: :environment do
    raise 'Demo corrections require demo mode outside production' if Rails.env.production?||ENV['DEMO_AUTH_ENABLED']!='true'
    source=ENV.fetch('SOURCE','demo-agent-insights-v1');run=ENV.fetch('RUN_ID','ins-docs-indexer-20261126-000')
    receipt=PricedUsageReceipt.where(status:'posted').where("payload->>'source'=? AND payload->>'agent_run_id'=?",source,run).order(:occurred_at,:id).first or raise "No posted receipt for #{source}/#{run}; import, price and deliver the scenario first"
    actor=RoleAssignment.where(organization_id:receipt.organization_id,role:'financial_operator').order(:id).first&.user or raise 'Run finance:demo_setup first'
    transactions=Finance::Operations.new(actor).correct(original_id:receipt.financial_transaction_id,amount:ENV.fetch('AMOUNT','0.008'),key:"slice9b-agent-correction/#{source}/#{run}",reason:'Slice 9B synthetic agent-cost correction')
    puts JSON.pretty_generate(run_id:run,original_transaction_id:receipt.financial_transaction_id,original_amount:Finance::Money.string(receipt.amount),transactions:transactions.map{|t|{id:t.id,kind:t.kind,amount:Finance::Money.string(t.amount)}})
  end
end
