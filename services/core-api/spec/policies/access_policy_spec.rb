require "rails_helper"

RSpec.describe AccessPolicy do
  it "grants leadership organization read without implicit project editing" do
    policy = described_class.new(person("leadership"))
    expect(policy.users.count).to eq(260)
    expect(policy.projects.count).to eq(7)
    expect(policy.management_profile?(person("financial_operator"))).to be(true)
    expect(policy.edit_project?(project)).to be(false)
  end

  it "grants managers their team, reporting descendants, and authorized units" do
    policy = described_class.new(person("director"))
    expect(policy.managed_unit_ids).to include(team("payments-core").id, team("ledger-services").id)
    expect(policy.management_profile?(person("employee"))).to be(true)
    expect(policy.team_roster?(team("payments-core"))).to be(true)
    expect(policy.team_roster?(team("finance"))).to be(false)
    expect(policy.management_profile?(person("financial_operator"))).to be(false)
  end

  it "combines scoped manager and project lead grants without widening team authority" do
    policy = described_class.new(person("manager"))
    expect(policy.manager?).to be(true)
    expect(policy.project_lead?).to be(true)
    expect(policy.edit_project?(project("real-time-payments"))).to be(true)
    expect(policy.edit_project?(project)).to be(false)
    expect(policy.management_profile?(person("colleague"))).to be(false)
  end

  it "lets project leads coordinate projects without managerial privileges" do
    policy = described_class.new(person("project_lead"))
    expect(policy.project?(project)).to be(true)
    expect(policy.edit_project?(project)).to be(true)
    expect(policy.management_profile?(person("employee"))).to be(false)
    expect(policy.team_roster?(team("payments-core"))).to be(false)
  end

  it "does not promote project membership labels into permission grants" do
    employee = person("employee")
    ProjectMembership.find_by!(user: employee, project: project).update!(project_role: "owner")
    policy = described_class.new(employee)
    expect(policy.edit_project?(project)).to be(false)
    expect(policy.manager?).to be(false)
  end

  it "gives employees self access and limited colleague metadata" do
    employee = person("employee")
    policy = described_class.new(employee)
    expect(policy.management_profile?(employee)).to be(true)
    expect(policy.management_profile?(person("manager"))).to be(false)
    expect(policy.profile?(person("manager"))).to be(true)
    expect(policy.own_access?(person("manager"))).to be(false)
    expect(policy.access_summary[:navigation].map { |n| n[:href] }).not_to include("/teams")
  end

  it "denies all resources from another tenant" do
    policy = described_class.new(person("leadership"))
    other = org("memento-ai")
    expect(policy.organization?(other)).to be(false)
    expect(policy.profile?(other.users.first)).to be(false)
    expect(policy.project?(other.projects.first)).to be(false)
    expect(policy.team_roster?(other.organizational_units.first)).to be(false)
  end

  it "does not return an unrelated directory record without any relevant relationship" do
    hidden = User.create!(organization: org, name: "Isolated Demo Person", email: "isolated@northline-financial.example", job_title: "Analyst", job_function: "Finance")
    expect(described_class.new(person("employee")).users).not_to include(hidden)
    expect(described_class.new(person("manager")).users).not_to include(hidden)
  end
end
