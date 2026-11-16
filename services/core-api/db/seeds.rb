summary = DemoData.seed!
puts "Seeded fictional organizations: #{summary.map { |s| "#{s[:slug]} (#{s[:people]} people)" }.join(', ')}."
