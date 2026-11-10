require 'rails_helper'
RSpec.describe Budgets::Controls do
  it 'uses centralized thresholds and exposes negative remaining and unfunded states' do
    expect(described_class.warning('75','100')[:warning]).to eq('approaching_limit')
    expect(described_class.warning('90','100')[:warning]).to eq('high_utilization')
    expect(described_class.warning('100','100')[:warning]).to eq('limit_reached')
    expect(described_class.warning('101','100')).to include(warning:'over_budget',remaining:'-1',overage:'1')
    expect(described_class.warning('0','0')).to include(warning:'zero_limit',utilization_percent:nil)
    expect(described_class.warning('1','0')).to include(warning:'over_budget',utilization_percent:nil)
  end
  it 'projects exact run rate using selected UTC month and handles sparse or negative observations' do
    month=Date.new(2026,11,1)
    expect(described_class.forecast('100',month:month,as_of:Date.new(2026,11,10),observed_days:3)).to include(projected:'300',elapsed_days:10,status:'linear_estimate')
    expect(described_class.forecast('100',month:month,as_of:nil,observed_days:3)[:status]).to eq('insufficient_data')
    expect(described_class.forecast('100',month:month,as_of:Date.new(2026,11,10),observed_days:1)[:projected]).to be_nil
    expect(described_class.forecast('-1',month:month,as_of:Date.new(2026,11,10),observed_days:3)[:status]).to eq('negative_corrections')
  end
end
