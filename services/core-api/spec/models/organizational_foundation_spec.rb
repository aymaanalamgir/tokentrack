require "rails_helper"

RSpec.describe "Organizational foundation", type: :model do
  it "seeds both structures idempotently with stable identifiers" do
    counts = [Organization, User, OrganizationalUnit, ReportingRelationship, Project, ProjectMembership, RoleAssignment].map(&:count)
    ids = User.order(:id).pluck(:id)
    DemoData.seed!
    expect([Organization, User, OrganizationalUnit, ReportingRelationship, Project, ProjectMembership, RoleAssignment].map(&:count)).to eq(counts)
    expect(User.order(:id).pluck(:id)).to eq(ids)
    expect(org.users.count).to eq(260)
    expect(org("memento-ai").users.count).to eq(30)
  end

  it "restores deleted memberships at their recorded dates so generated historical events keep validating" do
    epoch = EnterpriseDemo.epoch(DemoHelpers.spec)
    id = DemoData.uuid("northline-financial/project-member/fraud-detection-engine/member:payments-core:3")
    joined = ProjectMembership.find(id).joined_at
    expect(joined).to be_between(epoch, epoch + 20.days)
    home = OrganizationalMembership.find_by!(user: person("employee"), is_primary: true)
    ProjectMembership.where(id: id).delete_all
    OrganizationalMembership.where(id: home.id).delete_all
    DemoData.seed!
    fixture = ProjectMembership.find(id)
    expect(fixture.joined_at).to eq(joined)
    restored = OrganizationalMembership.find(home.id)
    expect([restored.created_at, restored.updated_at]).to eq([epoch, epoch])
    event = { key: "k", organization_id: org.id, user_id: person("employee").id, project_id: project.id, time: Time.utc(2026, 10, 10, 13) }
    expect(UsageReferenceValidation.new.validate([event]).first).to include(valid: true)
    expect(UsageReferenceValidation.new.validate([event.merge(time: joined - 1)]).first).to include(code: "PROJECT_MEMBERSHIP_NOT_ESTABLISHED")
    # Reseeding restores declared attributes but never rewrites an existing membership's recorded start.
    fixture.update_columns(joined_at: Time.utc(2025, 11, 9, 12))
    DemoData.seed!
    expect(fixture.reload.joined_at).to eq(Time.utc(2025, 11, 9, 12))
  end

  it "can intentionally reset demo organizations while preserving non-demo organizations" do
    real = Organization.create!(name: "Non-demo tenant", slug: "non-demo", demo: false)
    DemoData.reset!
    expect(Organization.find(real.id)).to eq(real)
    expect(org.users.count).to eq(260)
    expect(org("memento-ai").users.count).to eq(30)
  end

  it "supports arbitrary unit depth and rejects parent cycles" do
    root = team("payments-engineering")
    parent = team("payments-core")
    5.times { |n| parent = OrganizationalUnit.create!(organization: org, parent_unit: parent, name: "Nested #{n}", unit_type: "team") }
    expect(Hierarchy.unit_ids(org.id, [root.id])).to include(parent.id)
    root.parent_unit = parent
    expect(root).not_to be_valid
    expect(root.errors[:parent_unit]).to include("would create a cycle")
  end

  it "rejects cross-tenant and self-parent assignments" do
    unit = team("payments-engineering")
    unit.parent_unit = org("memento-ai").organizational_units.first
    expect(unit).not_to be_valid
    unit.parent_unit = unit
    expect(unit).not_to be_valid
  end

  it "enforces tenant-bound unit parents even when model validation is bypassed" do
    expect { ApplicationRecord.transaction(requires_new: true) { team("payments-engineering").update_columns(parent_unit_id: org("memento-ai").organizational_units.first.id) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "enforces unit cycles in PostgreSQL for direct writes" do
    expect { ApplicationRecord.transaction(requires_new: true) { team("payments-engineering").update_columns(parent_unit_id: team("payments-core").id) } }.to raise_error(ActiveRecord::StatementInvalid, /cycle/)
  end

  it "permits additional memberships but only one primary home team" do
    employee = person("employee")
    expect(employee.organizational_memberships.count).to eq(2)
    membership = OrganizationalMembership.new(organization: org, user: employee, organizational_unit: team("product-design"), is_primary: true)
    expect(membership).not_to be_valid
    expect { ApplicationRecord.transaction(requires_new: true) { membership.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects cross-organization home and project memberships" do
    outsider = person("employee", "memento-ai")
    expect(OrganizationalMembership.new(organization: org, user: outsider, organizational_unit: team("payments-core"))).not_to be_valid
    expect(ProjectMembership.new(organization: org, user: outsider, project: project)).not_to be_valid
    expect { ApplicationRecord.transaction(requires_new: true) { ProjectMembership.create!(organization: org, user_id: outsider.id, project: project, project_role: "contributor").save!(validate: false) } }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "enforces project membership tenant constraints without validations" do
    membership = ProjectMembership.new(organization: org, user: person("employee", "memento-ai"), project: project, project_role: "contributor")
    expect { ApplicationRecord.transaction(requires_new: true) { membership.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "prevents reporting to self, descendants, or another tenant" do
    leader = person("leadership")
    expect(ReportingRelationship.new(organization: org, manager: leader, report: leader)).not_to be_valid
    expect(ReportingRelationship.new(organization: org, manager: person("employee"), report: leader)).not_to be_valid
    expect(ReportingRelationship.new(organization: org, manager: person("employee", "memento-ai"), report: leader)).not_to be_valid
  end

  it "enforces reporting cycles in PostgreSQL" do
    relationship = ReportingRelationship.new(organization: org, manager: person("employee"), report: person("leadership"))
    expect { ApplicationRecord.transaction(requires_new: true) { relationship.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /cycle/)
  end

  it "validates explicit role scopes and tenant ownership" do
    grant = RoleAssignment.new(organization: org, user: person("employee"), role: "team_manager", scope_type: "unit")
    expect(grant).not_to be_valid
    grant.organizational_unit = org("memento-ai").organizational_units.first
    expect(grant).not_to be_valid
    grant.organizational_unit = team("payments-core")
    expect(grant).to be_valid
    grant.scope_type = "organization"
    expect(grant).not_to be_valid
  end

  it "enforces role/scope combinations at the database boundary" do
    grant = RoleAssignment.new(organization: org, user: person("employee"), role: "organization_viewer", scope_type: "project", project: project)
    expect { ApplicationRecord.transaction(requires_new: true) { grant.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /valid_role_and_explicit_scope/)
  end

  it "enforces role grant tenant boundaries without model validation" do
    grant = RoleAssignment.new(organization: org, user: person("employee", "memento-ai"), role: "project_lead", scope_type: "project", project: project)
    expect(grant).not_to be_valid
    expect { ApplicationRecord.transaction(requires_new: true) { grant.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "counts department descendants once even for overlapping memberships" do
    leader = person("leadership")
    before = WorkspacePresenter.new(AccessPolicy.new(leader)).unit(team("payments-engineering"))
    OrganizationalMembership.create!(organization: org, user: person("employee"), organizational_unit: team("ledger-services"), is_primary: false)
    after = WorkspacePresenter.new(AccessPolicy.new(leader)).unit(team("payments-engineering"))
    expect(after[:subtree_member_count]).to eq(before[:subtree_member_count])
    expect(after[:subtree_member_count]).to be > after[:member_count]
  end

  it "keeps job titles independent from grants" do
    user = person("employee")
    user.update!(job_title: "Chief Financial Officer", job_function: "Finance")
    expect(AccessPolicy.new(user).organization_viewer?).to be(false)
    expect(AccessPolicy.new(user).persona).to eq("employee")
  end
end
