namespace :agents do
  # One explicit, idempotent correction of an agent-linked demo charge through the existing Finance::Operations
  # boundary. Local trusted demo operation only; the stable key makes repeats a no-op. Defaults to the earliest
  # posted agent charge in the Memento AI workload; SOURCE and RUN_ID select another.
  task demo_correction: :environment do
    raise 'Demo corrections require demo mode outside production' if Rails.env.production?||ENV['DEMO_AUTH_ENABLED']!='true'
    source=ENV.fetch('SOURCE','enterprise-memento-v1')
    scope=PricedUsageReceipt.where(status:'posted').where("payload->>'source'=? AND payload->>'agent_run_id' IS NOT NULL",source)
    scope=scope.where("payload->>'agent_run_id'=?",ENV['RUN_ID']) if ENV['RUN_ID'].present?
    receipt=scope.order(:occurred_at,:id).first or raise "No posted agent receipt for #{source}; import, price and deliver the workload first"
    run=receipt.payload['agent_run_id']
    actor=RoleAssignment.where(organization_id:receipt.organization_id,role:'financial_operator').order(:id).first&.user or raise 'Fund the demo organization first'
    transactions=Finance::Operations.new(actor).correct(original_id:receipt.financial_transaction_id,amount:ENV.fetch('AMOUNT','0.008'),key:"demo-agent-correction/#{source}/#{run}",reason:'Synthetic agent-cost correction (demo)')
    puts JSON.pretty_generate(run_id:run,original_transaction_id:receipt.financial_transaction_id,original_amount:Finance::Money.string(receipt.amount),transactions:transactions.map{|t|{id:t.id,kind:t.kind,amount:Finance::Money.string(t.amount)}})
  end
end
