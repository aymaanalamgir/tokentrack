namespace :demo do
  desc "Destructively reset only flagged demo organizations and their sessions, then reseed"
  task reset: :environment do
    DemoData.reset!
    puts "Reset and reseeded the two fictional demo organizations."
  end
end
