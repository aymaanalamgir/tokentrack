module Api
  module V1
    module Internal
      class PricedUsageEventsController < ApplicationController
        include InternalServiceAuthentication
        before_action -> { authenticate_internal_service!("USAGE_FINANCIAL_TOKEN") }
        rescue_from ActiveRecord::ActiveRecordError do
          render json: { error: { code: "financial_store_unavailable", message: "Financial posting is temporarily unavailable" } }, status: :service_unavailable
        end
        rescue_from Finance::Invalid, ActiveRecord::RecordInvalid, JSON::ParserError do
          render json: { error: { code: "invalid_priced_event", message: "Payload does not satisfy the priced usage v1 contract" } }, status: :unprocessable_content
        end
        rescue_from Finance::Conflict, ActiveRecord::RecordNotUnique do
          render json: { error: { code: "financial_source_conflict", message: "Financial source conflicts with its original payload" } }, status: :conflict
        end
        rescue_from ActiveRecord::RecordNotFound do
          render json: { error: { code: "invalid_business_reference", message: "Financial references must belong to the stated organization" } }, status: :unprocessable_content
        end
        def create
          result = Finance::PricedUsagePosting.new.call(read_json)
          render json: result, status: result[:status] == "posted" ? (result[:duplicate] ? :ok : :created) : :accepted
        end
        def reconcile
          payload = read_json
          ids = payload["priced_event_ids"]
          raise Finance::Invalid unless payload.keys == ["priced_event_ids"] && ids.is_a?(Array) && ids.size.between?(1,100) && ids.all? { |id| id.is_a?(String) && Finance::PricedEventContract::UUID.match?(id) }
          render json: { schema_version: 1, data: Finance::Reconciliation.new.receipts(ids.map(&:downcase)), integrity: Finance::Reconciliation.new.integrity }
        end
        private
        def read_json
          raise Finance::Invalid unless request.media_type == "application/json" && request.content_length.to_i <= 65_536
          body = request.raw_post
          raise Finance::Invalid if body.bytesize > 65_536
          JSON.parse(body)
        end
      end
    end
  end
end
