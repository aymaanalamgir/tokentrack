module Agents
  class Scope
    KEYS=%w[start end agent_id run_id project_id user_id workflow_type status outcome retried limit offset].freeze
    INSIGHT_KEYS=%w[start end compare agent_id project_id user_id workflow_type insight_type severity evidence_quality].freeze
    COMPARISONS=%w[previous_period week month].freeze
    INSIGHT_TYPES=%w[retry_increase success_rate_decline cost_per_success_increase input_token_spike output_token_spike duration_increase model_cost_concentration failed_run_spend pricing_coverage_gap].freeze
    SEVERITIES=%w[critical warning info].freeze
    EVIDENCE=%w[sufficient limited_sample incomplete_cost_data].freeze
    UUID=Analytics::Scope::UUID
    attr_reader :policy,:filters,:start,:finish
    def initialize(policy,params,keys:KEYS)
      @policy=policy;@filters=params.to_h.stringify_keys
      raise Invalid,'Unknown agent filter' unless (filters.keys-keys).empty?
      raise Invalid,'Provide both start and end, or neither' if keys.equal?(INSIGHT_KEYS)&&filters.key?('start')!=filters.key?('end')
      parser=Analytics::Scope.allocate
      @start=parser.parse_time(filters['start']||(Time.now.utc-30.days).iso8601);@finish=parser.parse_time(filters['end']||(Time.now.utc+1.day).iso8601)
      raise Invalid,'Choose an increasing range of at most 366 days' unless start<finish&&finish-start<=366.days
      %w[agent_id project_id user_id].each{|key|raise Invalid,'Invalid identifier' if filters[key]&&!UUID.match?(filters[key])}
      %w[run_id workflow_type status outcome].each{|key|raise Invalid,'Invalid filter' if filters[key]&&!filters[key].match?(/\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\z/)}
      raise Invalid,'Invalid status' if filters['status']&&!%w[running completed failed cancelled].include?(filters['status'])
      raise Invalid,'Invalid outcome' if filters['outcome']&&!%w[success failure cancelled unknown].include?(filters['outcome'])
      raise Invalid,'Invalid retried filter' if filters['retried']&&!%w[true false].include?(filters['retried'])
      {'compare'=>COMPARISONS,'insight_type'=>INSIGHT_TYPES,'severity'=>SEVERITIES,'evidence_quality'=>EVIDENCE}.each{|key,allowed|raise Invalid,"Invalid #{key.tr('_',' ')}" if filters[key]&&!allowed.include?(filters[key])}
      raise ActiveRecord::RecordNotFound if filters['project_id']&&!policy.projects.exists?(id:filters['project_id'])
      if filters['user_id']
        user=User.where(organization_id:policy.organization_id).find(filters['user_id'])
        raise ActiveRecord::RecordNotFound unless policy.organization_viewer?||policy.managed_user_ids.include?(user.id)||ProjectMembership.where(organization_id:policy.organization_id,project_id:led_projects,user_id:user.id).exists?
      end
      limit;offset
    end
    def led_projects
      policy.grants.select{|g|g.role=='project_lead'}.map(&:project_id)
    end
    def scope_users
      policy.organization_viewer? ? [] : policy.managed_user_ids
    end
    def explicit_range? = filters.key?('start')
    # Tenant, permission population and entity filters shared by every Kotlin agent query. Window overridable per period.
    def base_payload(window_start:start.iso8601,window_end:finish.iso8601)
      {organization_id:policy.organization_id,all_users:policy.organization_viewer?,scope_users:scope_users,scope_projects:led_projects,filter_users:nil,start:window_start,end:window_end,
       agent_id:filters['agent_id'],run_id:filters['run_id'],project_id:filters['project_id'],user_id:filters['user_id'],workflow_type:filters['workflow_type'],status:filters['status'],outcome:filters['outcome'],
       retried:filters['retried']&.then{|value|value=='true'}}
    end
    def payload = base_payload.merge(limit:limit,offset:offset)
    def sql(alias_name='r')
      c=ApplicationRecord.connection;q=->(v){c.quote(v)};list=->(column,values){values.empty? ? 'FALSE' : "#{column} IN (#{values.map(&q).join(',')})"}
      clauses=["#{alias_name}.organization_id=#{q.call(policy.organization_id)}"]
      clauses<<"(#{list.call("#{alias_name}.user_id",scope_users)} OR #{list.call("#{alias_name}.project_id",led_projects)})" unless policy.organization_viewer?
      %w[project_id user_id].each{|key|clauses<<"#{alias_name}.#{key}=#{q.call(filters[key])}" if filters[key]}
      clauses.join(' AND ')
    end
    def limit
      integer('limit',25,1..100)
    end
    def offset
      integer('offset',0,0..100_000)
    end
    def integer(key,default,range);text=filters.fetch(key,default.to_s).to_s;raise Invalid,'Invalid pagination' unless text.match?(/\A\d+\z/)&&range.cover?(text.to_i);text.to_i end
  end
end
