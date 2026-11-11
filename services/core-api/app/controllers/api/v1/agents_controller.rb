module Api
  module V1
    class AgentsController < BaseController
      rescue_from(::Agents::Invalid) do |error|
        render_error(:invalid_agent_filter,error.message,:bad_request)
      end
      rescue_from(::Agents::Unavailable) do
        render_error(:agent_analytics_unavailable,'Agent analytics is unavailable. Retry shortly; no estimated totals are substituted.',:service_unavailable)
      end
      def index
        raise Agents::Invalid,'Filters must be scalar strings' unless Agents::Scope::KEYS.all?{|key|!params.key?(key)||params[key].is_a?(String)}
        unknown=params.keys-%w[controller action]-Agents::Scope::KEYS;raise Agents::Invalid,'Unknown agent filter' if unknown.any?
        render_data(Agents::Report.new(policy,params.permit(*Agents::Scope::KEYS).to_h).call)
      end
    end
  end
end
