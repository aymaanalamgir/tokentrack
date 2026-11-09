require "digest"
require "time"

module Api
  module V1
    module Internal
      # Service credential only. Deliberately independent of demo sessions and
      # browser-origin authentication; never exposed by the frontend BFF.
      class UsageReferencesController < ApplicationController
        before_action :authenticate_service!
        rescue_from ActiveRecord::ActiveRecordError do
          render json: { error: { code: "reference_data_unavailable", message: "Organizational references are temporarily unavailable" } }, status: :service_unavailable
        end
        UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

        def validate
          return invalid_request unless request.media_type == "application/json" && request.content_length.to_i <= 131_072
          entries = params[:references]
          unless entries.is_a?(Array) && entries.size.between?(1, 100)
            return invalid_request
          end
          refs = entries.map do |entry|
            return invalid_request unless entry.is_a?(ActionController::Parameters)
            row = entry.permit(:key, :organization_id, :user_id, :project_id, :occurred_at).to_h.symbolize_keys
            return invalid_request unless row[:key].to_s.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) && [:organization_id, :user_id].all? { |key| row[key].to_s.match?(UUID) } && (row[:project_id].blank? || row[:project_id].to_s.match?(UUID))
            return invalid_request unless row[:occurred_at].is_a?(String) && row[:occurred_at].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})\z/)
            begin
              row[:time] = Time.iso8601(row.fetch(:occurred_at)).utc
              return invalid_request unless row[:time].year.between?(2000, 2099)
            rescue ArgumentError, TypeError, KeyError
              return invalid_request
            end
            row
          end
          return invalid_request unless refs.map { |r| r[:key] }.uniq.size == refs.size
          render json: { data: UsageReferenceValidation.new.validate(refs), policy_version: "membership-period-v1" }
        end

        def demo_snapshot
          return head :not_found unless DemoSession.enabled?
          # Export only flagged fictional fixture identities and their recorded
          # history. IDs are exported from Rails, never reconstructed in Kotlin.
          organizations = Organization.where(demo: true).order(:id)
          users = User.where(organization_id: organizations.select(:id), demo_identity: true, status: "active").order(:id)
          homes = OrganizationalMembership.where(user_id: users.select(:id), is_primary: true).pluck(:user_id, :organizational_unit_id).to_h
          render json: { data: {
            snapshot_version: 1, policy_version: "membership-period-v1",
            organizations: organizations.map { |o| o.slice(:id, :slug) },
            users: users.map { |u| u.slice(:id, :organization_id, :job_function).merge(primary_unit_id: homes[u.id]) },
            projects: Project.where(organization_id: organizations.select(:id)).order(:id).map { |p| p.slice(:id, :organization_id, :slug, :status) },
            memberships: ProjectMembership.where(user_id: users.select(:id)).order(:id).map { |m| m.slice(:organization_id, :user_id, :project_id).merge(joined_at: m.joined_at.iso8601(6), left_at: m.left_at&.iso8601(6)) }
          } }
        end

        private

        def authenticate_service!
          response.headers["Cache-Control"] = "no-store, private"
          expected = ENV["USAGE_REFERENCE_TOKEN"].to_s
          supplied = request.headers["Authorization"].to_s.delete_prefix("Bearer ")
          unless expected.bytesize >= 32 && request.headers["Authorization"].to_s.start_with?("Bearer ") && ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(expected), Digest::SHA256.hexdigest(supplied))
            render json: { error: { code: "service_unauthorized", message: "Service authentication required" } }, status: :unauthorized
          end
        end

        def invalid_request
          render json: { error: { code: "invalid_reference_request", message: "Provide 1–100 unique keyed references with UUIDs and ISO 8601 event times (2000–2099)" } }, status: :bad_request
        end
      end
    end
  end
end
