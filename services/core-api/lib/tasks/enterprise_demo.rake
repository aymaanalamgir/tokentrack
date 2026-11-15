namespace :enterprise_demo do
  only = -> { ENV["COMPANY"].presence&.split(",") }
  guard = -> { abort "Local demo only" unless DemoSession.enabled? }

  desc "Seed the fictional enterprise companies (Alset, Northline Financial, Memento AI) from demo/enterprise/companies-v1.json"
  task seed: :environment do
    guard.call
    puts JSON.pretty_generate(EnterpriseDemo.seed!(only: only.call))
  end

  desc "Create monthly funded accounts for the enterprise companies via Finance::Operations (PROFILE=demo|smoke)"
  task fund: :environment do
    guard.call
    puts JSON.pretty_generate(EnterpriseDemo.fund!(profile: ENV.fetch("PROFILE", "demo"), only: only.call))
  end

  desc "Create a few personal controls, a delegation and requests for the enterprise companies"
  task controls: :environment do
    guard.call
    puts JSON.pretty_generate(EnterpriseDemo.controls!(only: only.call))
  end

  desc "Print enterprise company counts"
  task summary: :environment do
    puts JSON.pretty_generate(EnterpriseDemo.summary)
  end
end
