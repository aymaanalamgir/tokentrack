module Api
  module V1
    class HealthController < ApplicationController
      def show
        response.headers["Cache-Control"] = "no-store"
        ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") }
        render json: { service: "core-api", status: "ok", database: "connected" }
      rescue ActiveRecord::ActiveRecordError, PG::Error
        render json: { service: "core-api", status: "error", database: "disconnected" }, status: :service_unavailable
      end
    end
  end
end
