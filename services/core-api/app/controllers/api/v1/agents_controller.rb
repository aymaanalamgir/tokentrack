module Api
  module V1
    class AgentsController < BaseController
      rescue_from(::Agents::Invalid) do |error|
        render_error(:invalid_agent_filter,error.message,:bad_request)
      end
      rescue_from(::Agents::Unavailable) do
        render_error(:agent_analytics_unavailable,'Agent analytics is unavailable. Retry shortly; no estimated totals are substituted.',:service_unavailable)
      end
      def index = render_data(Agents::Report.new(policy,filters(Agents::Scope::KEYS)).call)
      # Slice 9B: period comparisons, deterministic findings, cost drivers. Same policy-derived population as index.
      def insights = render_data(Agents::Insights.new(policy,filters(Agents::Scope::INSIGHT_KEYS)).call)
      private
      def filters(keys)
        raise Agents::Invalid,'Filters must be scalar strings' unless keys.all?{|key|!params.key?(key)||params[key].is_a?(String)}
        unknown=params.keys-%w[controller action]-keys;raise Agents::Invalid,'Unknown agent filter' if unknown.any?
        params.permit(*keys).to_h
      end
    end
  end
end
