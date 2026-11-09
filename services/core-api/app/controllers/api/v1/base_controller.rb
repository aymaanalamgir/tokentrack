module Api
  module V1
    class BaseController < ApplicationController
      before_action :no_store
      before_action :verify_mutation_origin
      before_action :authenticate!
      rescue_from ActiveRecord::RecordNotFound do
        render_error(:not_found, "Resource not found in your authorized scope", :not_found)
      end
      rescue_from ActiveRecord::RecordInvalid do |error|
        render_error(:invalid_record, error.record.errors.full_messages.join(", "), :unprocessable_content)
      end
      rescue_from ActionController::ParameterMissing do
        render_error(:invalid_request, "Required request parameters are missing", :bad_request)
      end

      private

      def no_store
        response.headers["Cache-Control"] = "no-store, private"
      end

      def current_session
        return @current_session if defined?(@current_session)
        @current_session = DemoSession.resolve(request.cookies[DemoSession::COOKIE])
      end

      def current_user = current_session&.user
      def policy = @policy ||= AccessPolicy.new(current_user)
      def presenter = @presenter ||= WorkspacePresenter.new(policy)

      def authenticate!
        unless current_user&.status == "active" && current_user.demo_identity && current_user.organization.demo
          render_error(:unauthenticated, "Choose a demo identity to continue", :unauthorized)
        end
      end

      def verify_mutation_origin
        return if request.get? || request.head?
        unless request.headers["Origin"] == ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000") && request.media_type == "application/json"
          render_error(:invalid_origin, "A same-origin JSON request is required", :forbidden)
        end
      end

      def authorize!(allowed)
        return true if allowed
        render_error(:forbidden, "This action is outside your access scope", :forbidden)
        false
      end

      def render_data(data, meta: nil, status: :ok)
        render json: { data: data, meta: meta }.compact, status: status
      end

      def render_error(code, message, status)
        render json: { error: { code: code, message: message } }, status: status
      end

      def page(relation)
        limit = params.fetch(:limit, 50).to_i.clamp(1, 100)
        offset = params.fetch(:offset, 0).to_i.clamp(0, 1_000_000)
        [relation.limit(limit).offset(offset), { total: relation.count, limit: limit, offset: offset }]
      end
    end
  end
end
