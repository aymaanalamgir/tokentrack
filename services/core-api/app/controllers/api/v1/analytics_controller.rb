module Api
  module V1
    class AnalyticsController < BaseController
      rescue_from Analytics::Invalid do |error|
        render_error(:invalid_analytics_filter,error.message,:bad_request)
      end
      rescue_from Analytics::Unavailable do
        render_error(:usage_analytics_unavailable,'Usage analytics is unavailable. Retry shortly; no estimated totals are substituted.',:service_unavailable)
      end
      def show
        raise Analytics::Invalid,'Filters must be scalar strings' unless Analytics::Scope::KEYS.all? { |key| !params.key?(key) || params[key].is_a?(String) }
        filters=params.permit(*Analytics::Scope::KEYS).to_h
        unknown=params.keys-%w[controller action] - Analytics::Scope::KEYS
        raise Analytics::Invalid,'Unknown analytics filter' if unknown.any?
        render_data(Analytics::Report.new(policy,filters).call)
      end
    end
  end
end
