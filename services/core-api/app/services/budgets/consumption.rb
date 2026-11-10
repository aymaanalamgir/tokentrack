module Budgets
  class Consumption
    Scope=Struct.new(:organization_id,:start,:finish,:user_ids) do
      def sql(name='r')
        c=ApplicationRecord.connection
        condition="#{name}.organization_id=#{c.quote(organization_id)}"
        return condition unless user_ids
        ids=user_ids.map{|id|c.quote(id)}
        condition+" AND "+(ids.empty? ? 'FALSE' : "#{name}.user_id IN (#{ids.join(',')})")
      end
    end
    def initialize(organization_id,month,as_of:nil)
      @organization_id=organization_id;@month=month
      @start=Controls.utc(month)
      @finish=as_of ? [Controls.utc(as_of.next_day),Controls.utc(month.next_month)].min : Controls.utc(month.next_month)
    end
    def query(ids=nil) = Analytics::LedgerQuery.new(Scope.new(@organization_id,@start,@finish,ids))
    def batch(ids)
      query(ids).groups('user_id::text AS user_id,project_id::text AS project_id','user_id,project_id').each_with_object({}) do |row,result|
        (result[row['user_id']] ||= {})[row['project_id']]=BigDecimal(row['net_expenditure'])
      end
    end
    def by_project(user_id) = batch([user_id]).fetch(user_id,{})
    def daily(ids)
      query(ids).groups("occurred_at::date::text AS day",'day').sort_by{|r|r['day']}
    end
    def observed_days(ids)
      query(ids).rows(query(ids).cte+'SELECT COUNT(DISTINCT occurred_at::date) AS n FROM expenses').first['n'].to_i
    end
  end
end
