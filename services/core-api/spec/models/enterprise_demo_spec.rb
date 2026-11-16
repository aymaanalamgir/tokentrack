require "rails_helper"

RSpec.describe EnterpriseDemo do
  let(:spec) { EnterpriseDemo.spec }
  before { skip "enterprise spec not mounted at #{EnterpriseDemo::SPEC_PATH}" unless File.exist?(EnterpriseDemo::SPEC_PATH) }

  it "expands each company into a coherent hierarchy with sensible spans of control" do
    sizes = spec["companies"].to_h do |company|
      people = EnterpriseDemo.people(spec, company)
      refs = people.map { |p| p[:ref] }
      expect(refs.uniq.size).to eq(refs.size)
      expect(people.map { |p| p[:name] }.uniq.size).to eq(people.size)
      leaders = people.reject { |p| p[:manager] }
      expect(leaders.size).to eq(1)
      expect(people.filter_map { |p| p[:manager] } - refs).to be_empty
      spans = people.filter_map { |p| p[:manager] }.tally.values
      expect(spans.max).to be <= 16
      people.each do |p| # every chain reaches the leader without cycles
        seen = []; ref = p[:ref]
        while (manager = people.find { |x| x[:ref] == ref }[:manager]) do expect(seen).not_to include(manager); seen << manager; ref = manager end
      end
      expect(company["personas"].values - refs).to be_empty
      [company["slug"], people.size]
    end
    expect(sizes).to eq("alset" => 1100, "northline-financial" => 260, "memento-ai" => 30)
    expect(EnterpriseDemo.people(spec, EnterpriseDemo.company(spec, "alset")).map { |p| p[:office] }.uniq).to match_array(["Austin", "Palo Alto", "Toronto", "Berlin", "Shanghai"])
  end

  it "seeds, reseeds idempotently and funds Memento AI only through financial operations" do
    result = EnterpriseDemo.seed!(spec, only: ["memento-ai"]).first
    expect(result).to include(people: 30, projects: 6, offices: 1)
    org = Organization.find_by!(slug: "memento-ai")
    expect(User.where(organization: org, demo_identity: true).pluck(:name)).to match_array(["Noor Haddad", "Jonah Whitfield", "Ines Kowalski", "Theo Brennan"])
    expect(ReportingRelationship.where(organization: org).count).to eq(29)
    noor = User.find_by!(organization: org, name: "Noor Haddad")
    expect(AccessPolicy.new(noor)).to be_financial_operator.and(be_organization_viewer)
    expect(AccessPolicy.new(User.find_by!(organization: org, name: "Theo Brennan"))).not_to be_financial_operator
    epoch = EnterpriseDemo.epoch(spec)
    expect(OrganizationalMembership.where(organization: org).pluck(:created_at).uniq).to eq([epoch])
    expect(ProjectMembership.where(organization: org).minimum(:joined_at)).to eq(epoch)
    graph = Project.find_by!(organization: org, slug: "meeting-knowledge-graph")
    expect(ProjectMembership.where(project: graph).minimum(:joined_at)).to be >= Time.utc(2026, 2, 1)
    counts = [User, OrganizationalUnit, ReportingRelationship, Project, ProjectMembership, RoleAssignment].map { |m| m.where(organization: org).count }
    joins = ProjectMembership.where(organization: org).order(:id).pluck(:joined_at, :left_at)
    EnterpriseDemo.seed!(spec, only: ["memento-ai"])
    expect([User, OrganizationalUnit, ReportingRelationship, Project, ProjectMembership, RoleAssignment].map { |m| m.where(organization: org).count }).to eq(counts)
    expect(ProjectMembership.where(organization: org).order(:id).pluck(:joined_at, :left_at)).to eq(joins)

    funding = EnterpriseDemo.fund!(spec, profile: "smoke", only: ["memento-ai"]).first
    expect(funding[:months].size).to eq(12)
    transactions = FinancialTransaction.where(organization: org)
    expect(transactions.where(kind: "funding").count).to eq(12)
    expect(transactions.where.not(kind: %w[funding transfer])).to be_empty
    expect(LedgerEntry.joins(:financial_transaction).where(financial_transactions: { organization_id: org.id }).sum(:expense_delta)).to eq(0)
    funded = LedgerEntry.joins(:financial_transaction).where(financial_transactions: { organization_id: org.id }).sum(:funding_delta)
    expect(funded).to eq(transactions.where(kind: "funding").sum(:amount))
    BudgetPeriod.where(organization: org).find_each { |period| expect(period.funding - period.expenditure).to be >= 0 }
    expect { EnterpriseDemo.fund!(spec, profile: "smoke", only: ["memento-ai"]) }.not_to change(FinancialTransaction, :count)
    expect { EnterpriseDemo.fund!(spec, profile: "demo", only: ["memento-ai"]) }.to raise_error(Finance::Conflict, /another profile/)
  end

  it "gives the Northline scenario personas the explicit structure the access and approval workflows rely on" do
    expect(person("employee").name).to eq("Hana Takeda")
    expect(person("employee").manager_relationships.sole.manager).to eq(person("manager"))
    expect(person("manager").manager_relationships.sole.manager).to eq(person("director"))
    expect(ReportingRelationship.where(manager: person("project_lead"))).to be_empty
    expect(OrganizationalMembership.where(user: person("employee"), is_primary: false).sole.organizational_unit).to eq(team("data-engineering"))
    expect(ProjectMembership.where(project: project, user: [person("employee"), person("colleague")]).count).to eq(2)
    expect(RoleAssignment.where(user: person("project_lead"), role: %w[project_creator project_lead]).pluck(:role)).to match_array(%w[project_creator project_lead])
    expect(RoleAssignment.where(user: person("manager"), role: "project_lead").sole.project).to eq(project("real-time-payments"))
  end
end

RSpec.describe "Enterprise demo snapshot export", type: :request do
  before { skip "enterprise spec not mounted" unless File.exist?(EnterpriseDemo::SPEC_PATH) }
  def snapshot(query = "") = get("/api/v1/internal/usage-references/demo-snapshot#{query}", headers: { "Authorization" => "Bearer #{ENV.fetch('USAGE_REFERENCE_TOKEN')}" })

  it "exports every demo tenant by default and named tenants with fixture references" do
    snapshot
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "organizations").map { |o| o["slug"] }).to match_array(%w[northline-financial memento-ai])
    snapshot("?organizations=memento-ai")
    data = json.fetch("data")
    expect(data["organizations"].map { |o| o["slug"] }).to eq(["memento-ai"])
    expect(data["users"].size).to eq(30)
    expect(data["users"].map { |u| u["office"] }.uniq).to eq(["New York"])
    expect(data["organizations"].first["references"]).to include("member:ai-ml:0" => EnterpriseDemo.person_id("memento-ai", "member:ai-ml:0"))
    snapshot("?organizations=unknown-company"); expect(response).to have_http_status(:bad_request)
    snapshot("?organizations=Bad;Slug"); expect(response).to have_http_status(:bad_request)
  end
end
