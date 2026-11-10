module Analytics
  class Scope
    attr_reader :policy, :filters, :start, :finish, :grain
    UUID=/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    KEYS=%w[start end granularity organization_unit_id project_id user_id provider model tool limit offset audit_start audit_end].freeze
    def initialize(policy,params)
      @policy=policy
      @filters=params.to_h.stringify_keys
      raise Invalid,'Unknown analytics filter' unless (filters.keys-KEYS).empty?
      @grain=filters.fetch('granularity','day')
      raise Invalid,'Granularity must be day, week or month' unless %w[day week month].include?(grain)
      @start=parse_time(filters['start'] || (Time.now.utc-30.days).iso8601)
      @finish=parse_time(filters['end'] || (Time.now.utc+1.day).iso8601)
      raise Invalid,'Choose an increasing range of at most 366 days' unless start<finish && finish-start<=366.days
      %w[organization_unit_id project_id user_id].each do |key|
        next unless filters[key]
        raise Invalid,'Invalid identifier' unless UUID.match?(filters[key])
      end
      %w[provider model tool].each { |key| raise Invalid,'Invalid filter' if filters[key] && !filters[key].match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/@+-]{0,199}\z/) }
      raise ActiveRecord::RecordNotFound if filters['project_id'] && !policy.projects.exists?(id:filters['project_id'])
      # Directory visibility alone never authorizes private analytics.
      if filters['user_id']
        user=User.where(organization_id:policy.organization_id).find(filters['user_id'])
        raise ActiveRecord::RecordNotFound unless policy.organization_viewer? || policy.managed_user_ids.include?(user.id) || ProjectMembership.where(organization_id:policy.organization_id,project_id:led_projects,user_id:user.id).exists?
      end
      if filters['organization_unit_id']
        unit=OrganizationalUnit.where(organization_id:policy.organization_id).find(filters['organization_unit_id'])
        raise ActiveRecord::RecordNotFound unless policy.organization_viewer? || policy.managed_unit_ids.include?(unit.id)
      end
      limit;offset
      raise Invalid,'Scope too large; choose a narrower reporting scope' if scope_users.size>200 || led_projects.size>100 || (filter_users && filter_users.size>200)
    end
    def parse_time(text)
      raise Invalid,'Use explicit ISO-8601 UTC dates' unless text.is_a?(String) && text.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z\z/)
      value=Time.iso8601(text).utc
      raise Invalid,'Dates must be within 2000–2099' unless value.year.between?(2000,2099)
      value
    rescue ArgumentError
      raise Invalid,'Invalid timestamp'
    end
    def led_projects = @led_projects ||= policy.grants.select{|g|g.role=='project_lead'}.map(&:project_id)
    def scope_users = policy.organization_viewer? ? [] : policy.managed_user_ids
    def filter_users
      return @filter_users if defined?(@filter_users)
      @filter_users=if filters['organization_unit_id']
        ids=Hierarchy.unit_ids(policy.organization_id,[filters['organization_unit_id']])
        OrganizationalMembership.where(organization_id:policy.organization_id,organizational_unit_id:ids,is_primary:true).distinct.pluck(:user_id)
      end
    end
    def payload(from=start,to=finish)
      {organization_id:policy.organization_id,all_users:policy.organization_viewer?,scope_users:scope_users,scope_projects:led_projects,filter_users:filter_users,start:from.iso8601,end:to.iso8601,granularity:grain,project_id:filters['project_id'],user_id:filters['user_id'],provider:filters['provider'],model:filters['model'],tool:filters['tool']}
    end
    def sql(alias_name='r')
      c=ApplicationRecord.connection
      q=->(v){c.quote(v)}
      list=->(column,values){values.empty? ? 'FALSE' : "#{column} IN (#{values.map(&q).join(',')})"}
      clauses=["#{alias_name}.organization_id=#{q.call(policy.organization_id)}"]
      clauses << "(#{list.call("#{alias_name}.user_id",scope_users)} OR #{list.call("#{alias_name}.project_id",led_projects)})" unless policy.organization_viewer?
      clauses << list.call("#{alias_name}.user_id",filter_users) if filter_users
      %w[project_id user_id].each{|key|clauses << "#{alias_name}.#{key}=#{q.call(filters[key])}" if filters[key]}
      %w[provider model tool].each{|key|clauses << "#{alias_name}.payload->>'#{key}'=#{q.call(filters[key])}" if filters[key]}
      clauses.join(' AND ')
    end
    def limit = integer('limit',25,1..100)
    def offset = integer('offset',0,0..100_000)
    def integer(key,default,range)
      text=filters.fetch(key,default.to_s).to_s
      raise Invalid,'Invalid pagination' unless text.match?(/\A\d+\z/) && range.cover?(text.to_i)
      text.to_i
    end
  end
end
