require "digest"

module DemoData
  module_function

  def uuid(key)
    hex = Digest::SHA256.hexdigest("tokentrack-demo-2/#{key}")[0, 32]
    [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
  end

  def save(model, key, attributes)
    record = model.find_or_initialize_by(id: uuid(key))
    record.update!(attributes)
    record
  end

  def seed!
    raise "Demo seeds require DEMO_AUTH_ENABLED=true in development/test" unless DemoSession.enabled?
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(47290210)")
      seed_startup
      seed_enterprise
    end
  end

  def reset!
    raise "Demo reset is disabled" unless DemoSession.enabled?
    ApplicationRecord.transaction do
      ids = Organization.where(demo: true).pluck(:id)
      [DemoSession, RoleAssignment, ProjectMembership, ReportingRelationship, OrganizationalMembership, Project, User, OrganizationalUnit].each { |model| model.where(organization_id: ids).delete_all }
      Organization.where(id: ids).delete_all
      seed!
    end
  end

  def build(slug, name, unit_specs, person_specs, project_specs, manager_keys, team_manager_keys)
    org = save(Organization, slug, name: name, slug: slug, description: "Fictional #{name} organization for local access-control exploration.", demo: true)
    units = {}
    unit_specs.each do |key, label, parent, type|
      units[key] = save(OrganizationalUnit, "#{slug}/unit/#{key}", organization: org, name: label, parent_unit: units[parent], unit_type: type, description: "#{label} at #{name}.")
    end
    people = {}
    person_specs.each do |key, label, title, function, team|
      person = save(User, "#{slug}/person/#{key}", organization: org, name: label, email: "#{key}@#{slug}.example", job_title: title, job_function: function, status: "active", demo_identity: true)
      people[key] = person
      save(OrganizationalMembership, "#{slug}/home/#{key}", organization: org, user: person, organizational_unit: units.fetch(team), is_primary: true, membership_type: "home_team")
      save(RoleAssignment, "#{slug}/employee/#{key}", organization: org, user: person, role: "employee", scope_type: "self", organizational_unit: nil, project: nil)
    end
    executive = people.values.first
    save(RoleAssignment, "#{slug}/executive", organization: org, user: executive, role: "organization_viewer", scope_type: "organization")
    team_manager_keys.each do |team, key|
      save(RoleAssignment, "#{slug}/manager/#{team}", organization: org, user: people.fetch(key), role: "team_manager", scope_type: "unit", organizational_unit: units.fetch(team))
    end
    person_specs.each do |key, _label, _title, _function, team|
      next if people[key] == executive
      manager_key = manager_keys.fetch(key) { team_manager_keys.fetch(team, person_specs.first.first) }
      manager_key = person_specs.first.first if manager_key == key
      save(ReportingRelationship, "#{slug}/reporting/#{key}", organization: org, manager: people.fetch(manager_key), report: people.fetch(key), relationship_type: "line_manager")
    end
    projects = {}
    project_specs.each do |key, label, lead, status|
      project = save(Project, "#{slug}/project/#{key}", organization: org, name: label, slug: key, status: status, description: "A fictional cross-functional initiative: #{label}.")
      projects[key] = project
      save(ProjectMembership, "#{slug}/project-member/#{key}/#{lead}", organization: org, project: project, user: people.fetch(lead), project_role: "owner")
      save(RoleAssignment, "#{slug}/project-lead/#{key}", organization: org, user: people.fetch(lead), role: "project_lead", scope_type: "project", project: project)
    end
    person_specs.each_with_index do |(key, *_), index|
      assignments = [project_specs[index % project_specs.size]]
      assignments << project_specs[(index + 1) % project_specs.size] if index % 3 == 0
      assignments.each do |project_key, _label, lead, _status|
        next if key == lead
        save(ProjectMembership, "#{slug}/project-member/#{project_key}/#{key}", organization: org, project: projects.fetch(project_key), user: people.fetch(key), project_role: index.even? ? "contributor" : "reviewer")
      end
    end
    [org, units, people, projects]
  end

  def seed_startup
    build("northstar-labs", "Northstar Labs", [
      ["leadership", "Leadership", nil, "team"], ["engineering", "Engineering", nil, "team"],
      ["product-design", "Product & Design", nil, "team"], ["operations", "Operations", nil, "team"]
    ], [
      ["maya", "Maya Chen", "Founder & CEO", "Executive", "leadership"],
      ["theo", "Theo Park", "Technical Lead", "Engineering", "engineering"],
      ["leila", "Leila Shah", "Product Manager", "Product", "product-design"],
      ["sam", "Sam Rivera", "Software Engineer", "Engineering", "engineering"],
      ["nia", "Nia Brooks", "UI/UX Designer", "Design", "product-design"],
      ["ezra", "Ezra Kim", "Software Architect", "Architecture", "engineering"],
      ["ada", "Ada Morgan", "Software Engineer", "Engineering", "engineering"],
      ["noah", "Noah Reed", "Operations Specialist", "Operations", "operations"],
      ["zoe", "Zoe Ellis", "Account Executive", "Sales", "operations"],
      ["kai", "Kai Patel", "Data Scientist", "Data Science", "engineering"]
    ], [
      ["core-product", "Core Product", "leila", "active"], ["customer-onboarding", "Customer Onboarding", "leila", "active"],
      ["internal-ai-automation", "Internal AI Automation", "theo", "planned"]
    ], { "theo" => "maya", "leila" => "maya", "noah" => "maya" }, { "engineering" => "theo", "operations" => "noah" })
  end

  def seed_enterprise
    unit_specs = [
      ["executive", "Executive Leadership", nil, "division"], ["engineering", "Engineering", nil, "department"],
      ["platform", "Platform Engineering", "engineering", "team"], ["infrastructure", "Infrastructure", "engineering", "team"],
      ["applications", "Application Engineering", "engineering", "team"], ["product", "Product", nil, "department"],
      ["product-management", "Product Management", "product", "team"], ["design", "Product Design", "product", "team"],
      ["data", "Data & AI", nil, "department"], ["marketing", "Marketing", nil, "department"],
      ["finance", "Finance", nil, "department"], ["operations", "Operations", nil, "department"]
    ]
    people = [
      ["olivia", "Olivia Chen", "Chief Technology Officer", "Executive", "executive"],
      ["marcus", "Marcus Rivera", "Engineering Manager", "Engineering Management", "platform"],
      ["priya", "Priya Shah", "Product Manager", "Product", "product-management"],
      ["jordan", "Jordan Lee", "Software Engineer", "Engineering", "platform"],
      ["sofia", "Sofia Patel", "UX Designer", "Design", "design"],
      ["ellis", "Ellis Morgan", "VP of Engineering", "Engineering Management", "engineering"],
      ["dana", "Dana Brooks", "Infrastructure Manager", "Engineering Management", "infrastructure"],
      ["imani", "Imani Reed", "Application Engineering Manager", "Engineering Management", "applications"],
      ["rowan", "Rowan Park", "Head of Product", "Product Management", "product"],
      ["alex", "Alex Kim", "Head of Data & AI", "Data Science", "data"],
      ["casey", "Casey Ellis", "Finance Director", "Finance", "finance"],
      ["riley", "Riley Chen", "People & Operations Lead", "Operations", "operations"]
    ]
    specialties = [
      ["platform", "Senior Software Engineer", "Engineering"], ["infrastructure", "Software Architect", "Architecture"],
      ["applications", "Software Engineer", "Engineering"], ["product-management", "Product Specialist", "Product"],
      ["design", "Product Designer", "Design"], ["data", "Data Scientist", "Data Science"],
      ["marketing", "Marketing Specialist", "Marketing"], ["marketing", "Account Executive", "Sales"],
      ["finance", "Finance Analyst", "Finance"], ["operations", "HR Specialist", "People Operations"]
    ]
    first_names = %w[Avery Emery Quinn Morgan Taylor Cameron Jamie Reese Skyler Finley Drew Peyton Remy Sage]
    last_names = %w[Stone Hayes Wells Blake Monroe Lane]
    52.times do |index|
      team, title, function = specialties[index % specialties.size]
      people << ["colleague-#{index + 1}", "#{first_names[index % first_names.size]} #{last_names[index / first_names.size]}", title, function, team]
    end
    org, units, users, projects = build("aperture-technologies", "Aperture Technologies", unit_specs, people, [
      ["fraud-detection", "Fraud Detection Platform", "priya", "active"],
      ["developer-productivity", "Developer Productivity", "marcus", "active"],
      ["customer-analytics", "Customer Analytics", "priya", "active"],
      ["ai-sales-assistant", "AI Sales Assistant", "colleague-7", "planned"],
      ["knowledge-automation", "Internal Knowledge Automation", "alex", "active"]
    ], { "marcus" => "ellis", "dana" => "ellis", "imani" => "ellis", "priya" => "rowan", "sofia" => "rowan", "jordan" => "marcus" }, { "engineering" => "ellis", "platform" => "marcus", "infrastructure" => "dana", "applications" => "imani", "product" => "rowan", "product-management" => "rowan", "design" => "rowan", "data" => "alex", "finance" => "casey", "operations" => "riley" })
    %w[fraud-detection customer-analytics ai-sales-assistant].each do |key|
      save(ProjectMembership, "aperture-technologies/project-member/#{key}/jordan", organization: org, project: projects.fetch(key), user: users.fetch("jordan"), project_role: "contributor")
    end
    save(OrganizationalMembership, "aperture-technologies/additional/jordan", organization: org, user: users.fetch("jordan"), organizational_unit: units.fetch("data"), is_primary: false, membership_type: "working_group")
  end
end
