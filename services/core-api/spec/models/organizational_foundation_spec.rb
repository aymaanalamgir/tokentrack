require "rails_helper"

RSpec.describe "Organizational foundation", type: :model do
  it "seeds both structures idempotently with stable identifiers" do
    counts = [Organization, User, OrganizationalUnit, ReportingRelationship, Project, ProjectMembership, RoleAssignment].map(&:count)
    ids = User.order(:id).pluck(:id)
    DemoData.seed!
    expect([Organization, User, OrganizationalUnit, ReportingRelationship, Project, ProjectMembership, RoleAssignment].map(&:count)).to eq(counts)
    expect(User.order(:id).pluck(:id)).to eq(ids)
    expect(org.users.count).to eq(64)
    expect(org("northstar-labs").users.count).to eq(10)
  end

  it "can intentionally reset demo fixtures while preserving non-demo organizations" do
    real = Organization.create!(name: "Non-demo tenant", slug: "non-demo", demo: false)
    DemoData.reset!
    expect(Organization.find(real.id)).to eq(real)
    expect(org.users.count).to eq(64)
    expect(org("northstar-labs").users.count).to eq(10)
  end

  it "supports arbitrary unit depth and rejects parent cycles" do
    root = team("engineering")
    parent = team("platform")
    5.times { |n| parent = OrganizationalUnit.create!(organization: org, parent_unit: parent, name: "Nested #{n}", unit_type: "team") }
    expect(Hierarchy.unit_ids(org.id, [root.id])).to include(parent.id)
    root.parent_unit = parent
    expect(root).not_to be_valid
    expect(root.errors[:parent_unit]).to include("would create a cycle")
  end

  it "rejects cross-tenant and self-parent assignments" do
    unit = team("engineering")
    unit.parent_unit = org("northstar-labs").organizational_units.first
    expect(unit).not_to be_valid
    unit.parent_unit = unit
    expect(unit).not_to be_valid
  end

  it "enforces tenant-bound unit parents even when model validation is bypassed" do
    expect { ApplicationRecord.transaction(requires_new: true) { team("engineering").update_columns(parent_unit_id: org("northstar-labs").organizational_units.first.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "enforces unit cycles in PostgreSQL for direct writes" do
    expect { ApplicationRecord.transaction(requires_new: true) { team("engineering").update_columns(parent_unit_id: team("platform").id) } }.to raise_error(ActiveRecord::StatementInvalid, /cycle/)
  end

  it "permits additional memberships but only one primary home team" do
    jordan = person("jordan")
    expect(jordan.organizational_memberships.count).to eq(2)
    membership = OrganizationalMembership.new(organization: org, user: jordan, organizational_unit: team("design"), is_primary: true)
    expect(membership).not_to be_valid
    expect { ApplicationRecord.transaction(requires_new: true) { membership.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects cross-organization home and project memberships" do
    outsider = person("sam", "northstar-labs")
    expect(OrganizationalMembership.new(organization: org, user: outsider, organizational_unit: team("platform"))).not_to be_valid
    expect(ProjectMembership.new(organization: org, user: outsider, project: project)).not_to be_valid
    expect { ApplicationRecord.transaction(requires_new: true) { ProjectMembership.create!(organization: org, user_id: outsider.id, project: project, project_role: "contributor").save!(validate: false) } }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "enforces project membership tenant constraints without validations" do
    membership = ProjectMembership.new(organization: org, user: person("sam", "northstar-labs"), project: project, project_role: "contributor")
    expect { ApplicationRecord.transaction(requires_new: true) { membership.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "prevents reporting to self, descendants, or another tenant" do
    olivia = person("olivia")
    expect(ReportingRelationship.new(organization: org, manager: olivia, report: olivia)).not_to be_valid
    expect(ReportingRelationship.new(organization: org, manager: person("jordan"), report: olivia)).not_to be_valid
    expect(ReportingRelationship.new(organization: org, manager: person("sam", "northstar-labs"), report: olivia)).not_to be_valid
  end

  it "enforces reporting cycles in PostgreSQL" do
    relationship = ReportingRelationship.new(organization: org, manager: person("jordan"), report: person("olivia"))
    expect { ApplicationRecord.transaction(requires_new: true) { relationship.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /cycle/)
  end

  it "validates explicit role scopes and tenant ownership" do
    grant = RoleAssignment.new(organization: org, user: person("jordan"), role: "team_manager", scope_type: "unit")
    expect(grant).not_to be_valid
    grant.organizational_unit = org("northstar-labs").organizational_units.first
    expect(grant).not_to be_valid
    grant.organizational_unit = team("platform")
    expect(grant).to be_valid
    grant.scope_type = "organization"
    expect(grant).not_to be_valid
  end

  it "enforces role/scope combinations at the database boundary" do
    grant = RoleAssignment.new(organization: org, user: person("jordan"), role: "organization_viewer", scope_type: "project", project: project)
    expect { ApplicationRecord.transaction(requires_new: true) { grant.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /valid_role_and_explicit_scope/)
  end

  it "enforces role grant tenant boundaries without model validation" do
    grant = RoleAssignment.new(organization: org, user: person("sam", "northstar-labs"), role: "project_lead", scope_type: "project", project: project)
    expect(grant).not_to be_valid
    expect { ApplicationRecord.transaction(requires_new: true) { grant.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "counts department descendants once even for overlapping memberships" do
    leader = person("olivia")
    before = WorkspacePresenter.new(AccessPolicy.new(leader)).unit(team("engineering"))
    OrganizationalMembership.create!(organization: org, user: person("jordan"), organizational_unit: team("infrastructure"), is_primary: false)
    after = WorkspacePresenter.new(AccessPolicy.new(leader)).unit(team("engineering"))
    expect(after[:subtree_member_count]).to eq(before[:subtree_member_count])
    expect(after[:subtree_member_count]).to be > after[:member_count]
  end

  it "keeps job titles independent from grants" do
    user = person("jordan")
    user.update!(job_title: "Chief Financial Officer", job_function: "Finance")
    expect(AccessPolicy.new(user).organization_viewer?).to be(false)
    expect(AccessPolicy.new(user).persona).to eq("employee")
  end
end
