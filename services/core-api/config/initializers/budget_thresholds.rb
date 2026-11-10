approaching=Integer(ENV.fetch('BUDGET_WARNING_APPROACHING_PERCENT','75'),10)
high=Integer(ENV.fetch('BUDGET_WARNING_HIGH_PERCENT','90'),10)
raise 'Budget thresholds must satisfy 0 < approaching < high < 100' unless approaching.positive? && approaching<high && high<100
Rails.application.config.x.budget_thresholds={approaching:approaching,high:high,reached:100}.freeze
