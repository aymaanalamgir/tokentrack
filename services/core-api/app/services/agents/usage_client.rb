require 'net/http'
module Agents
  class UsageClient
    def call(payload)
      uri=URI.join(ENV.fetch('USAGE_ANALYTICS_URL','http://usage-engine:8080'),'/internal/v1/agent-analytics')
      request=Net::HTTP::Post.new(uri,{'Content-Type'=>'application/json','Authorization'=>"Bearer #{ENV.fetch('USAGE_ANALYTICS_TOKEN','')}"});request.body=JSON.generate(payload)
      response=Net::HTTP.start(uri.host,uri.port,open_timeout:2,read_timeout:8){|http|http.request(request)}
      raise Unavailable unless response.code=='200'&&response.body.bytesize<=3_000_000
      data=JSON.parse(response.body);raise Unavailable unless data['schema_version']==1&&data['totals'].is_a?(Hash)&&data['agents'].is_a?(Array)&&data.dig('runs','rows').is_a?(Array)&&data['cohort_runs'].is_a?(Array)
      data
    rescue IOError,SystemCallError,Timeout::Error,JSON::ParserError,SocketError
      raise Unavailable
    end
  end
end
