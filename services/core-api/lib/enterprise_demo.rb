require "digest"
require "json"

# Enterprise demo companies (Alset, Northline Financial, Memento AI) expanded deterministically from the shared
# spec in demo/enterprise/companies-v1.json, which the Kotlin workload generator also reads. Everything here is
# fictional. Records are created through the normal models and financial operations: no ledger row is inserted
# directly, and nothing existing is deleted. Re-running restores descriptive attributes but never rewrites
# membership periods or timestamps, because usage validation and charge attribution depend on them.
module EnterpriseDemo
  module_function

  SPEC_PATH = ENV.fetch("ENTERPRISE_DEMO_SPEC", "/demo/enterprise/companies-v1.json")

  def spec(path = SPEC_PATH) = JSON.parse(File.read(path))
  def slugs(spec = self.spec) = spec.fetch("companies").map { |c| c.fetch("slug") }
  def start(spec) = Time.utc(*spec.fetch("start").split("-").map(&:to_i))
  def window_end(spec) = (start(spec).to_date >> spec.fetch("months")).to_time(:utc)
  def epoch(spec) = start(spec) - spec.fetch("epoch_days_before_start").days
  def months(spec) = spec.fetch("months").times.map { |i| start(spec).to_date >> i }
  def fraction(*parts) = Digest::SHA256.hexdigest(["enterprise-demo-v1", *parts].join("/"))[0, 13].to_i(16) / 4_503_599_627_370_496.0
  def person_id(slug, ref) = DemoData.uuid("#{slug}/person/#{ref}")
  def company(spec, slug) = spec.fetch("companies").find { |c| c["slug"] == slug } || raise(ArgumentError, "Unknown enterprise company #{slug}")
  def selected(spec, only) = spec.fetch("companies").select { |c| only.blank? || only.include?(c["slug"]) }

  # Expands departments and teams into people with stable references, titles, offices and line managers.
  # Teams with more than 12 individual contributors get technical leads (one per ~10 people), so no manager has
  # an absurd span of control; department heads report to the company leader.
  def people(spec, company)
    names = NameAllocator.new(spec, company)
    depts = company.fetch("departments")
    leader = "dept:#{depts.first.fetch('key')}"
    rows = []
    add = lambda do |ref, title, function, unit, office, manager|
      rows << { ref: ref, name: names.name(ref), title: title, function: function, unit: unit, office: office, manager: manager }
    end
    depts.each do |dept|
      dept_ref = "dept:#{dept['key']}"
      head = dept["head"]
      add.call(dept_ref, head["title"], head["function"], dept["key"], dept["office"], dept_ref == leader ? nil : leader) if head
      report_to = head ? dept_ref : leader
      dept.fetch("teams").each do |team|
        office = team["office"] || dept["office"]
        size = team.fetch("size")
        if team.fetch("lead", true)
          team_ref = "team:#{team['key']}"
          add.call(team_ref, team.fetch("lead_title"), team["function"], team["key"], office, report_to)
          ics = size - 1
          sub_leads = ics > 12 ? (ics / 10.0).ceil : 0
          ics.times do |i|
            ref = "member:#{team['key']}:#{i}"
            if i < sub_leads
              add.call(ref, "Technical Lead, #{team['name']}", team["function"], team["key"], office, team_ref)
            else
              manager = sub_leads.positive? ? "member:#{team['key']}:#{(i - sub_leads) % sub_leads}" : team_ref
              add.call(ref, (i % 4).zero? ? "Senior #{team['title']}" : team["title"], team["function"], team["key"], office, manager)
            end
          end
        else
          size.times { |i| add.call("member:#{team['key']}:#{i}", team["title"], team["function"], team["key"], office, report_to) }
        end
      end
    end
    rows
  end

  class NameAllocator
    def initialize(spec, company)
      @slug = company["slug"]; @first = spec.fetch("first_names"); @last = spec.fetch("last_names")
      @fixed = company.fetch("departments").filter_map { |d| ["dept:#{d['key']}", d.dig("head", "name")] if d.dig("head", "name") }.to_h.merge(company.fetch("names", {}))
      @used = @fixed.values.to_set
    end
    def name(ref)
      return @fixed[ref] if @fixed.key?(ref)
      attempt = 0
      loop do
        f = EnterpriseDemo.fraction(@slug, "name", ref, attempt)
        candidate = "#{@first[(f * @first.size).floor]} #{@last[(EnterpriseDemo.fraction(@slug, 'surname', ref, attempt) * @last.size).floor]}"
        return candidate if @used.add?(candidate)
        attempt += 1
      end
    end
  end

  def email(name, slug) = "#{name.downcase.gsub(/[^a-z0-9]+/, '.').gsub(/\A\.|\.\z/, '')}@#{slug}.example"

  # Creates on first run; afterwards restores only descriptive attributes. Time-bearing attributes are never
  # rewritten, and memberships are never updated, so recorded history stays stable.
  def save(model, key, attributes = {}, created_at: nil, update: true, **fields)
    attributes = attributes.merge(fields)
    record = model.find_or_initialize_by(id: DemoData.uuid(key))
    if record.new_record?
      record.assign_attributes(attributes)
      record.assign_attributes(created_at: created_at, updated_at: created_at) if created_at
      record.save!
    elsif update
      record.assign_attributes(attributes.except(:created_at, :updated_at, :joined_at, :left_at))
      record.save! if record.changed?
    end
    record
  end

  def seed!(spec = self.spec, only: nil)
    raise "Enterprise demo seeds require DEMO_AUTH_ENABLED=true in development/test" unless DemoSession.enabled?
    selected(spec, only).map do |company|
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(47290211)")
        seed_company(spec, company)
      end
    end
  end

  def seed_company(spec, company)
    slug = company.fetch("slug")
    epoch = epoch(spec)
    offices = company.fetch("offices").keys
    org = save(Organization, slug, name: company.fetch("name"), slug: slug, demo: true,
      description: "#{company.fetch('description')} Offices: #{offices.join(', ')}.")
    units = {}
    company.fetch("departments").each do |dept|
      units[dept["key"]] = save(OrganizationalUnit, "#{slug}/unit/#{dept['key']}", organization: org, name: dept["name"], parent_unit: nil, unit_type: "department", description: "#{dept['name']} at #{company['name']} (#{dept['office']}).")
      dept["teams"].each do |team|
        units[team["key"]] = save(OrganizationalUnit, "#{slug}/unit/#{team['key']}", organization: org, name: team["name"], parent_unit: units.fetch(dept["key"]), unit_type: "team", description: "#{team['name']} team at #{company['name']} (#{team['office'] || dept['office']}).")
      end
    end
    personas = company.fetch("personas")
    rows = people(spec, company)
    users = {}
    rows.each do |row|
      user = save(User, "#{slug}/person/#{row[:ref]}", organization: org, name: row[:name], email: email(row[:name], slug), job_title: row[:title], job_function: row[:function],
        office: row[:office], status: "active", demo_identity: personas.value?(row[:ref]))
      users[row[:ref]] = user
      save(OrganizationalMembership, "#{slug}/home/#{row[:ref]}", { organization: org, user: user, organizational_unit: units.fetch(row[:unit]), is_primary: true, membership_type: "home_team" }, created_at: epoch, update: false)
      save(RoleAssignment, "#{slug}/employee/#{row[:ref]}", organization: org, user: user, role: "employee", scope_type: "self", organizational_unit: nil, project: nil)
    end
    rows.each do |row|
      next unless row[:manager]
      save(ReportingRelationship, "#{slug}/reporting/#{row[:ref]}", organization: org, manager: users.fetch(row[:manager]), report: users.fetch(row[:ref]), relationship_type: "line_manager")
    end
    # Explicit grants: managers manage their unit subtree; titles alone grant nothing.
    rows.each do |row|
      next unless row[:ref].start_with?("dept:", "team:")
      save(RoleAssignment, "#{slug}/manager/#{row[:unit]}", organization: org, user: users.fetch(row[:ref]), role: "team_manager", scope_type: "unit", organizational_unit: units.fetch(row[:unit]))
    end
    leader = users.fetch(personas.fetch("leadership"))
    save(RoleAssignment, "#{slug}/executive", organization: org, user: leader, role: "organization_viewer", scope_type: "organization")
    save(RoleAssignment, "#{slug}/creator", organization: org, user: leader, role: "project_creator", scope_type: "organization")
    finance = users.fetch(personas.fetch("financial_operator"))
    save(RoleAssignment, "#{slug}/finance-viewer", organization: org, user: finance, role: "organization_viewer", scope_type: "organization") unless finance == leader
    save(RoleAssignment, "#{slug}/financial-operator", organization: org, user: finance, role: "financial_operator", scope_type: "organization")
    manager_unit = rows.find { |r| r[:ref] == personas.fetch("manager") }.fetch(:unit)
    save(RoleAssignment, "#{slug}/manager-budget-reader", organization: org, user: users.fetch(personas.fetch("manager")), role: "team_budget_reader", scope_type: "unit", organizational_unit: units.fetch(manager_unit))
    members_by_unit = rows.group_by { |r| r[:unit] }
    window_end = window_end(spec)
    projects = {}
    company.fetch("projects").each do |spec_project|
      key = spec_project.fetch("key")
      begins = spec_project.fetch("start_month").zero? ? epoch : (start(spec).to_date >> spec_project["start_month"]).to_time(:utc)
      project = save(Project, "#{slug}/project/#{key}", organization: org, created_by: leader, name: spec_project.fetch("name"), slug: key, status: "active", description: "Fictional cross-functional initiative at #{company['name']}: #{spec_project['name']}.")
      projects[key] = project
      lead = users.fetch(spec_project.fetch("lead"))
      save(ProjectMembership, "#{slug}/project-member/#{key}/#{spec_project['lead']}", { organization: org, project: project, user: lead, project_role: "owner", joined_at: begins }, update: false)
      save(RoleAssignment, "#{slug}/project-lead/#{key}", organization: org, user: lead, role: "project_lead", scope_type: "project", project: project)
      save(RoleAssignment, "#{slug}/project-budget-reader/#{key}", organization: org, user: lead, role: "project_budget_reader", scope_type: "project", project: project) if spec_project["lead"] == personas["project_lead"]
      forced = company.fetch("persona_projects", []).include?(key) ? [personas.fetch("employee")] : []
      spec_project.fetch("teams").each do |team, share|
        members_by_unit.fetch(team, []).each do |row|
          ref = row[:ref]
          next if ref == spec_project["lead"]
          next unless forced.include?(ref) || fraction(slug, "project", key, ref) < share
          joined = begins + (fraction(slug, "joined", key, ref) * 20).floor.days
          left = nil
          if !forced.include?(ref) && fraction(slug, "rotation", key, ref) < 0.1
            candidate = joined + (120 + (fraction(slug, "tenure", key, ref) * 120).floor).days
            left = candidate if candidate < window_end
          end
          save(ProjectMembership, "#{slug}/project-member/#{key}/#{ref}", { organization: org, project: project, user: users.fetch(ref), joined_at: joined, left_at: left,
            project_role: fraction(slug, "role", key, ref) < 0.25 ? "reviewer" : "contributor" }, update: false)
        end
      end
      forced.each do |ref|
        next if members_by_unit.values.flatten.none? { |r| r[:ref] == ref } || ProjectMembership.exists?(id: DemoData.uuid("#{slug}/project-member/#{key}/#{ref}"))
        save(ProjectMembership, "#{slug}/project-member/#{key}/#{ref}", { organization: org, project: project, user: users.fetch(ref), joined_at: begins, project_role: "contributor" }, update: false)
      end
    end
    { slug: slug, organization_id: org.id, people: users.size, units: units.size, projects: projects.size, offices: offices.size }
  end

  # Fixture references Kotlin needs (agent owners) exported as Rails-owned IDs; Kotlin never reconstructs IDs.
  def references(spec, company)
    refs = company.fetch("agents").map { |a| a.fetch("owner") } + company.fetch("personas").values
    refs.uniq.to_h { |ref| [ref, person_id(company["slug"], ref)] }
  end

  # Monthly funded accounts through Finance::Operations. Allocations follow the spec's planning assumption
  # (budget per person by AI-intensity tier, split between home team and active projects the way the workload
  # generator assigns project activity), scaled by the profile, the budget curve and per-account factors.
  # Stable operation keys make this idempotent; a changed plan raises a conflict instead of rewriting history.
  def fund!(spec = self.spec, profile: "demo", only: nil)
    scale = spec.dig("profiles", profile, "scale") or raise ArgumentError, "Unknown profile #{profile}"
    selected(spec, only).map { |company| fund_company(spec, company, scale.to_d, profile) }
  end

  def fund_company(spec, company, scale, profile)
    slug = company["slug"]
    org = Organization.find_by!(slug: slug)
    other = FinancialTransaction.where(organization: org).where("source_id LIKE ?", "enterprise/#{slug}/%/funding/%").where.not("source_id LIKE ?", "enterprise/#{slug}/#{profile}/%").exists?
    raise Finance::Conflict, "#{slug} is already funded under another profile; use one profile per database" if other
    actor = User.find(person_id(slug, company.dig("personas", "financial_operator")))
    effective = start(spec)
    account = lambda do |purpose, owner|
      BudgetAccount.find_or_create_by!(id: DemoData.uuid("financial/account/#{purpose}/#{owner.id}")) do |record|
        record.assign_attributes(organization: org, name: "#{owner.name} #{purpose} AI budget", purpose: purpose, currency: "USD", effective_from: effective, status: "active",
          organizational_unit_id: purpose == "unit" ? owner.id : nil, project_id: purpose == "project" ? owner.id : nil)
      end
    end
    reserve = account.call("reserve", org)
    unassigned = account.call("unassigned", org)
    units = OrganizationalUnit.where(organization: org).order(:id).to_a
    projects = Project.where(organization: org).where.not(status: "archived").order(:id).to_a
    accounts = units.to_h { |u| [[:unit, u.id], account.call("unit", u)] }.merge(projects.to_h { |p| [[:project, p.id], account.call("project", p)] })
    functions = company.fetch("functions")
    budget = ->(fn) { BigDecimal((functions.dig(fn, "budget_usd") || 0).to_s) }
    share = ->(fn) { BigDecimal((functions.dig(fn, "project_share") || 0).to_s) }
    users = User.where(organization: org, status: "active").pluck(:id, :job_function).to_h
    homes = OrganizationalMembership.where(organization: org, is_primary: true).pluck(:user_id, :organizational_unit_id).to_h
    memberships = ProjectMembership.where(organization: org).pluck(:user_id, :project_id, :joined_at, :left_at)
    unit_keys = company["departments"].flat_map { |d| [d["key"]] + d["teams"].map { |t| t["key"] } }.to_h { |key| [DemoData.uuid("#{slug}/unit/#{key}"), key] }
    project_keys = projects.to_h { |p| [p.id, p.slug] }
    factor = ->(kind, id) { BigDecimal((company.dig("funding", "factors", "#{kind}:#{kind == :unit ? unit_keys[id] : project_keys[id]}") || 1).to_s) }
    curve = company.dig("funding", "budget_curve")
    operations = Finance::Operations.new(actor)
    totals = []
    months(spec).each_with_index do |date, index|
      month = date.strftime("%Y-%m")
      mid = Time.utc(date.year, date.month, 15)
      weights = Hash.new(BigDecimal(0))
      active = memberships.select { |_u, _p, joined, left| joined <= mid && (left.nil? || left > mid) }.group_by(&:first)
      users.each do |user_id, fn|
        planned = budget.call(fn)
        next if planned.zero?
        projects_now = active.fetch(user_id, []).map { |row| row[1] }
        weights[[:unit, homes[user_id]]] += planned * (projects_now.empty? ? 1 : 1 - share.call(fn))
        projects_now.each { |project_id| weights[[:project, project_id]] += planned * share.call(fn) / projects_now.size }
      end
      multiplier = BigDecimal(curve.fetch(index).to_s) * scale
      allocations = weights.filter_map do |(kind, id), weight|
        amount = (weight * multiplier * factor.call(kind, id)).round(2)
        [accounts.fetch([kind, id]), amount] if amount >= 1
      end.sort_by { |acct, _| acct.id }
      planned_total = allocations.sum { |_, amount| amount }
      unassigned_amount = [(planned_total * BigDecimal(company.dig("funding", "unassigned_share").to_s)).round(2), BigDecimal("10")].max
      allocations << [unassigned, unassigned_amount]
      funding = ((planned_total + unassigned_amount) * (1 + BigDecimal(company.dig("funding", "reserve_buffer").to_s))).round(2)
      ([reserve] + allocations.map(&:first)).each do |acct|
        BudgetPeriod.find_or_create_by!(id: DemoData.uuid("financial/period/#{acct.id}/#{month}")) { |p| p.assign_attributes(organization: org, budget_account: acct, month_start: date, currency: "USD", status: "open") }
      end
      operations.fund(account: reserve.id, month: month, amount: Finance::Money.string(funding), key: "enterprise/#{slug}/#{profile}/funding/#{month}", reason: "Fictional #{company['name']} AI budget for #{month} (#{profile} profile)")
      allocations.each do |acct, amount|
        operations.transfer(from: reserve.id, to: acct.id, month: month, amount: Finance::Money.string(amount), key: "enterprise/#{slug}/#{profile}/allocation/#{month}/#{acct.id}", reason: "Planned #{month} AI allocation")
      end
      totals << { month: month, funding: Finance::Money.string(funding), accounts: allocations.size }
    end
    { slug: slug, months: totals }
  end

  # A few personal controls and requests per company, in the final month. Idempotent by request key.
  def controls!(spec = self.spec, only: nil)
    selected(spec, only).map do |company|
      slug = company["slug"]
      org = Organization.find_by!(slug: slug)
      persona = ->(role) { User.find(person_id(slug, company.dig("personas", role))) }
      finance = persona.call("financial_operator")
      employee = persona.call("employee")
      controls = company.fetch("controls")
      last_months = months(spec).last(3)
      service = Budgets::AllowanceOperations.new(finance)
      last_months.each do |date|
        month = date.strftime("%Y-%m")
        next if SpendingLimit.exists?(organization: org, user: employee, month_start: date)
        service.revise(user_id: employee.id, month: month, amount: controls.fetch("employee_ceiling"), expected_revision: nil, request_key: "enterprise/#{slug}/ceiling/#{month}", reason: "Monthly AI spending ceiling (control, not funding)", kind: "ceiling")
        root = SpendingLimit.find_by!(organization: org, user: employee, month_start: date)
        mid = Time.utc(date.year, date.month, 15)
        active = ProjectMembership.where(organization: org, user: employee).where("joined_at<=? AND (left_at IS NULL OR left_at>?)", mid, mid).order(:project_id).pluck(:project_id)
        next if active.empty?
        # The allowance rules require the unallocated remainder to cover existing non-project spend. Try smaller
        # shares; if none fits (heavy non-project use), leave the month without sublimits rather than bypass the rule.
        [BigDecimal("0.6"), BigDecimal("0.3"), BigDecimal("0.1")].each do |share|
          portion = (BigDecimal(controls["employee_ceiling"]) * share / active.size).round(2)
          Budgets::AllowanceOperations.new(employee).revise(user_id: employee.id, month: month, allocations: active.map { |id| { project_id: id, amount: Finance::Money.string(portion) } }, expected_revision: root.reload.current_revision_id,
            request_key: "enterprise/#{slug}/sublimits/#{month}/#{share.to_s('F')}", reason: "Project sublimits within the personal ceiling; not a funding movement", kind: "reallocation")
          break
        rescue Finance::Invalid
          next
        end
      end
      manager = persona.call("manager")
      if controls["delegation_max"]
        unit = OrganizationalMembership.find_by!(user: manager, is_primary: true).organizational_unit
        service.delegate(manager_id: manager.id, unit_id: unit.id, maximum_amount: controls["delegation_max"], from_month: last_months.first.strftime("%Y-%m"), until_month: last_months.last.strftime("%Y-%m"),
          request_key: "enterprise/#{slug}/delegation", reason: "Capped allowance authority for direct reports")
      end
      reserve = BudgetAccount.find_by!(organization: org, purpose: "reserve")
      month = last_months.last.strftime("%Y-%m")
      requests = controls.fetch("requests").each_with_index.map do |request, index|
        actor = persona.call(request.fetch("by"))
        extra = {}
        extra = { project_id: Project.find_by!(organization: org, slug: request["project"]).id, source_account_id: reserve.id } if request["project"]
        extra = { unit_id: OrganizationalUnit.find(DemoData.uuid("#{slug}/unit/#{request['unit']}")).id, source_account_id: reserve.id } if request["unit"]
        Requests::CreateService.new(actor).call(request_type: request.fetch("type"), month: month, requested_amount: request.fetch("amount"), request_key: "enterprise/#{slug}/request/#{index}",
          reason: "Fictional #{company['name']} #{request['type'].tr('_', ' ')} request for #{month}", **extra)
      end
      { slug: slug, ceilings: SpendingLimit.where(organization: org).count, requests: requests.map { |r| { type: r.request_type, status: r.status, approver: r.assigned_approver&.name } } }
    end
  end

  def summary(spec = self.spec)
    selected(spec, nil).filter_map do |company|
      org = Organization.find_by(slug: company["slug"]) or next
      units = OrganizationalUnit.where(organization: org)
      { slug: org.slug, people: User.where(organization: org).count, departments: units.where(unit_type: "department").count, teams: units.where(unit_type: "team").count,
        offices: User.where(organization: org).distinct.count(:office), projects: Project.where(organization: org).count, project_memberships: ProjectMembership.where(organization: org).count,
        reporting_lines: ReportingRelationship.where(organization: org).count, demo_identities: User.where(organization: org, demo_identity: true).order(:name).pluck(:name, :job_title) }
    end
  end
end
