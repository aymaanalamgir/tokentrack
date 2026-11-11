module Api
  module V1
    class RequestsController < BaseController
      rescue_from Finance::Forbidden do |error|
        render_error(:request_forbidden, error.message.presence || "This request action is outside your authority", :forbidden)
      end
      rescue_from Finance::Invalid, Analytics::Invalid do |error|
        render_error(:invalid_request_operation, error.message, :unprocessable_content)
      end
      rescue_from Finance::Conflict, ActiveRecord::StaleObjectError do |error|
        render_error(:request_conflict, error.message, :conflict)
      end
      rescue_from ActiveRecord::StatementInvalid do
        render_error(:request_integrity_conflict, "The request conflicts with current financial state. Reload before retrying.", :conflict)
      end

      def index
        render_data(Requests::Report.new(current_user, params.except(:controller, :action).to_unsafe_h).call)
      end

      def show
        render_data(Requests::Report.new(current_user).find(params[:id]))
      end

      def create
        body = request_body
        request = Requests::CreateService.new(current_user).call(**body.symbolize_keys)
        render_data(Requests::Report.new(current_user).find(request.id), status: :created)
      end

      %w[approve reject cancel escalate].each do |decision|
        define_method(decision) do
          body = action_body
          request = Requests::DecisionService.new(current_user).public_send(decision, id: params[:id], operation_key: body.fetch("operation_key"), comment: body.fetch("comment"))
          render_data(Requests::Report.new(current_user).find(request.id))
        end
      end

      private

      def request_body
        raise Finance::Invalid, "Request body must be a JSON object under request" unless params[:request].is_a?(ActionController::Parameters)
        values = params.require(:request).to_unsafe_h
        base = %w[request_type month requested_amount reason request_key]
        optional = %w[project_id unit_id source_account_id]
        raise Finance::Invalid, "Unexpected or missing request fields" unless (values.keys - base - optional).empty? && (base - values.keys).empty?
        raise Finance::Invalid, "Request field values must be strings" unless values.values.all? { |value| value.is_a?(String) }
        optional.each { |key| raise Finance::Invalid, "Invalid UUID" if values[key].present? && !Analytics::Scope::UUID.match?(values[key]) }
        values
      end

      def action_body
        raise Finance::Invalid, "Action body must be a JSON object under request_action" unless params[:request_action].is_a?(ActionController::Parameters)
        values = params.require(:request_action).to_unsafe_h
        raise Finance::Invalid, "Action requires exactly operation_key and comment" unless values.keys.sort == %w[comment operation_key]
        raise Finance::Invalid, "Action field values must be strings" unless values.values.all? { |value| value.is_a?(String) }
        values
      end
    end
  end
end
