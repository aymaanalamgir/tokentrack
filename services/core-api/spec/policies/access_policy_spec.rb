require "rails_helper"

RSpec.describe AccessPolicy do
  it "grants leadership organization read without implicit project editing" do
    policy = described_class.new(person("olivia"))
    expect(policy.users.count).to eq(64)
    expect(policy.projects.count).to eq(5)
    expect(policy.management_profile?(person("casey"))).to be(true)
    expect(policy.edit_project?(project)).to be(false)
  end

  it "grants managers their team, reporting descendants, and authorized units" do
    policy = described_class.new(person("ellis"))
    expect(policy.managed_unit_ids).to include(team("platform").id, team("infrastructure").id)
    expect(policy.management_profile?(person("jordan"))).to be(true)
    expect(policy.team_roster?(team("platform"))).to be(true)
    expect(policy.team_roster?(team("finance"))).to be(false)
    expect(policy.management_profile?(person("casey"))).to be(false)
  end

  it "combines scoped manager and project lead grants without widening team authority" do
    policy = described_class.new(person("marcus"))
    expect(policy.manager?).to be(true)
    expect(policy.project_lead?).to be(true)
    expect(policy.edit_project?(project("developer-productivity"))).to be(true)
    expect(policy.edit_project?(project)).to be(false)
    expect(policy.management_profile?(person("sofia"))).to be(false)
  end

  it "lets project leads coordinate projects without managerial privileges" do
    policy = described_class.new(person("priya"))
    expect(policy.project?(project)).to be(true)
    expect(policy.edit_project?(project)).to be(true)
    expect(policy.management_profile?(person("jordan"))).to be(false)
    expect(policy.team_roster?(team("platform"))).to be(false)
  end

  it "does not promote project membership labels into permission grants" do
    jordan = person("jordan")
    ProjectMembership.find_by!(user: jordan, project: project).update!(project_role: "owner")
    policy = described_class.new(jordan)
    expect(policy.edit_project?(project)).to be(false)
    expect(policy.manager?).to be(false)
  end

  it "gives employees self access and limited colleague metadata" do
    jordan = person("jordan")
    policy = described_class.new(jordan)
    expect(policy.management_profile?(jordan)).to be(true)
    expect(policy.management_profile?(person("marcus"))).to be(false)
    expect(policy.profile?(person("marcus"))).to be(true)
    expect(policy.own_access?(person("marcus"))).to be(false)
    expect(policy.access_summary[:navigation].map { |n| n[:href] }).not_to include("/teams")
  end

  it "denies all resources from another tenant" do
    policy = described_class.new(person("olivia"))
    other = org("northstar-labs")
    expect(policy.organization?(other)).to be(false)
    expect(policy.profile?(other.users.first)).to be(false)
    expect(policy.project?(other.projects.first)).to be(false)
    expect(policy.team_roster?(other.organizational_units.first)).to be(false)
  end

  it "does not return an unrelated directory record without any relevant relationship" do
    hidden = User.create!(organization: org, name: "Isolated Demo Person", email: "isolated@aperture.example", job_title: "Analyst", job_function: "Finance")
    expect(described_class.new(person("jordan")).users).not_to include(hidden)
    expect(described_class.new(person("marcus")).users).not_to include(hidden)
  end
end
