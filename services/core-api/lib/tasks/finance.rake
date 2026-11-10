namespace :finance do
  task demo_setup: :environment do
    months = ENV.fetch("MONTHS").split(",")
    puts JSON.pretty_generate(Finance::DemoSetup.new.call(months))
  end
  task report: :environment do
    actor = User.find(ENV.fetch("ACTOR_ID"))
    puts JSON.pretty_generate(Finance::Reconciliation.new.report(actor,ENV.fetch("MONTH")))
  end
  task fund: :environment do
    tx = Finance::Operations.new(User.find(ENV.fetch("ACTOR_ID"))).fund(account: ENV.fetch("ACCOUNT_ID"),month: ENV.fetch("MONTH"),amount: ENV.fetch("AMOUNT"),key: ENV.fetch("REQUEST_KEY"),reason: ENV.fetch("REASON"))
    puts JSON.pretty_generate(id: tx.id, amount: Finance::Money.string(tx.amount))
  end
  task transfer: :environment do
    tx = Finance::Operations.new(User.find(ENV.fetch("ACTOR_ID"))).transfer(from: ENV.fetch("FROM_ACCOUNT_ID"),to: ENV.fetch("TO_ACCOUNT_ID"),month: ENV.fetch("MONTH"),amount: ENV.fetch("AMOUNT"),key: ENV.fetch("REQUEST_KEY"),reason: ENV.fetch("REASON"))
    puts JSON.pretty_generate(id: tx.id, amount: Finance::Money.string(tx.amount))
  end
  task correct: :environment do
    transactions = Finance::Operations.new(User.find(ENV.fetch("ACTOR_ID"))).correct(original_id: ENV.fetch("TRANSACTION_ID"),amount: ENV["AMOUNT"],key: ENV.fetch("REQUEST_KEY"),reason: ENV.fetch("REASON"))
    puts JSON.pretty_generate(transactions.map { |t| { id: t.id, kind: t.kind, amount: Finance::Money.string(t.amount) } })
  end
end
