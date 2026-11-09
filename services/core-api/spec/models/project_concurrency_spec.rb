require "rails_helper"

RSpec.describe "Concurrent project authority", type: :model do
  self.use_transactional_tests = false

  it "serializes ownership changes and rejects the waiting revoked administrator" do
    actor = person("priya")
    record = ProjectManagement.new(actor).create(name: "Concurrent transfer spec", status: "planned")
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = %w[jordan sofia].map do |key|
      target_id = person(key).id
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            ProjectManagement.new(User.find(actor.id)).transfer(Project.find(record.id), target_id)
            results << :transferred
          rescue ProjectManagement::Forbidden
            results << :revoked
          rescue => error
            results << error
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }
    expect(outcomes).to contain_exactly(:transferred, :revoked)
    expect(RoleAssignment.where(project: record, role: "project_lead").count).to eq(1)
    ApplicationRecord.connection.execute("SELECT business.check_project_administration('#{record.id}')")
  ensure
    if record
      ApplicationRecord.transaction do
        RoleAssignment.where(project_id: record.id).delete_all
        ProjectMembership.where(project_id: record.id).delete_all
        Project.where(id: record.id).delete_all
      end
    end
  end
end
