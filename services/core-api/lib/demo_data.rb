require "digest"

# Local fictional demo organizations. The companies themselves (Alset, Northline Financial, Memento AI) are
# defined in demo/enterprise/companies-v1.json and expanded by EnterpriseDemo; this module owns the stable ID
# scheme and the guarded seed/reset entry points.
module DemoData
  module_function

  def uuid(key)
    hex = Digest::SHA256.hexdigest("tokentrack-demo-2/#{key}")[0, 32]
    [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
  end

  # COMPANIES limits seeding to a comma-separated list of company slugs (the test suite seeds the two smaller
  # companies only); by default every company in the spec is seeded.
  def companies = ENV["DEMO_COMPANIES"].to_s.split(",").map(&:strip).reject(&:empty?).presence

  def seed!(only: companies)
    raise "Demo seeds require DEMO_AUTH_ENABLED=true in development/test" unless DemoSession.enabled?
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(47290210)")
      EnterpriseDemo.seed!(only: only)
    end
  end

  # Destructively removes flagged demo organizations and reseeds them. Refuses once any append-only history
  # (requests, spending controls, ledger transactions) exists, so financial records are never rewritten.
  def reset!(only: companies)
    raise "Demo reset is disabled" unless DemoSession.enabled?
    ApplicationRecord.transaction do
      ids = Organization.where(demo: true).pluck(:id)
      if FinancialRequest.table_exists? && FinancialRequest.where(organization_id: ids).exists?
        raise "Demo reset is disabled for organizations with append-only request history"
      end
      if (SpendingLimit.table_exists? && SpendingLimit.where(organization_id: ids).exists?) || (AllowanceDelegation.table_exists? && AllowanceDelegation.where(organization_id: ids).exists?)
        raise "Demo reset is disabled for organizations with spending-control history"
      end
      if FinancialTransaction.table_exists? && FinancialTransaction.where(organization_id: ids).exists?
        raise "Demo reset is disabled for organizations with append-only financial history"
      end
      [DemoSession, RoleAssignment, ProjectMembership, ReportingRelationship, OrganizationalMembership, Project, User, OrganizationalUnit].each { |model| model.where(organization_id: ids).delete_all }
      Organization.where(id: ids).delete_all
      seed!(only: only)
    end
  end
end
