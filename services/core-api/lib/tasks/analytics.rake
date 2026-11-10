namespace :analytics do
  desc 'Explicitly grant local demo managers/project leads budget READ access; no money mutation authority'
  task demo_access: :environment do
    abort 'Local demo only' unless DemoSession.enabled?
    RoleAssignment.where(role:'team_manager').joins(user: :organization).where(users:{demo_identity:true},organizations:{demo:true}).find_each do |grant|
      RoleAssignment.find_or_create_by!(organization_id:grant.organization_id,user_id:grant.user_id,role:'team_budget_reader',scope_type:'unit',organizational_unit_id:grant.organizational_unit_id)
    end
    RoleAssignment.where(role:'project_lead').joins(user: :organization).where(users:{demo_identity:true},organizations:{demo:true}).find_each do |grant|
      RoleAssignment.find_or_create_by!(organization_id:grant.organization_id,user_id:grant.user_id,role:'project_budget_reader',scope_type:'project',project_id:grant.project_id)
    end
    puts({team_read_grants:RoleAssignment.where(role:'team_budget_reader').count,project_read_grants:RoleAssignment.where(role:'project_budget_reader').count}.to_json)
  end
end
