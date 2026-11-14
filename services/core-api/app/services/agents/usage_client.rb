require 'net/http'
module Agents
  # Backend-only reads from the Kotlin usage engine. Every body carries the Rails-derived population.
  class UsageClient
    SHAPES={
      'agent-analytics'=>->(d){d['schema_version']==2&&d['totals'].is_a?(Hash)&&d['agents'].is_a?(Array)&&d.dig('runs','rows').is_a?(Array)},
      'agent-cohort'=>->(d){d['schema_version']==1&&d['rows'].is_a?(Array)&&d['rows'].size<=1000&&(d['next'].nil?||d['next'].is_a?(Hash))},
      'agent-insights'=>->(d){d['schema_version']==1&&d['agents'].is_a?(Array)&&d['insights'].is_a?(Array)&&d['thresholds'].is_a?(Hash)&&d['current_period'].is_a?(Hash)&&d['comparison_period'].is_a?(Hash)}
    }.freeze
    def call(payload,path:'agent-analytics')
      uri=URI.join(ENV.fetch('USAGE_ANALYTICS_URL','http://usage-engine:8080'),"/internal/v1/#{path}")
      request=Net::HTTP::Post.new(uri,{'Content-Type'=>'application/json','Authorization'=>"Bearer #{ENV.fetch('USAGE_ANALYTICS_TOKEN','')}"});request.body=JSON.generate(payload)
      response=Net::HTTP.start(uri.host,uri.port,open_timeout:2,read_timeout:8){|http|http.request(request)}
      raise Invalid,'Agent analytics rejected the filters' if response.code=='400'
      raise Unavailable unless response.code=='200'&&response.body.bytesize<=3_000_000
      data=JSON.parse(response.body);raise Unavailable unless SHAPES.fetch(path).call(data)
      data
    rescue IOError,SystemCallError,Timeout::Error,JSON::ParserError,SocketError
      raise Unavailable
    end
  end
end
