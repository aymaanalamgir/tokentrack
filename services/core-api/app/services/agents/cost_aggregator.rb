module Agents
  # Walks the complete authorized cohort in bounded keyset pages and folds corrected ledger cost into fixed-size
  # tallies. Memory is one page (<=1000 runs) plus per-agent/bucket/model sums, so there is no cohort-size cap
  # and nothing is truncated. If the walk cannot finish it fails; it never returns a partial total.
  class CostAggregator
    BATCH=LedgerCosts::MAX_BATCH
    MAX_PAGES=5_000
    FIELDS=%i[runs costed_runs cost original success_cost failed_cost cancelled_cost incomplete_cost retried_success_cost].freeze
    Result=Struct.new(:total,:agents,:buckets,:models,:pages)
    def self.tally = FIELDS.index_with{|field|%i[runs costed_runs].include?(field) ? 0 : BigDecimal(0)}
    def initialize(scope,client:)=(@ledger=LedgerCosts.new(scope);@client=client)
    def call(payload,bucket:'day')
      result=Result.new(self.class.tally,Hash.new{|h,k|h[k]=self.class.tally},Hash.new{|h,k|h[k]=self.class.tally},Hash.new{|h,k|h[k]=Hash.new(BigDecimal(0))},0)
      cursor={after_started_at:nil,after_id:nil}
      loop do
        page=@client.call(payload.merge(cursor).merge(batch:BATCH,bucket:bucket),path:'agent-cohort')
        costs=@ledger.call(page['rows'])
        page['rows'].each do |run|
          cost=costs[[run['source'],run['run_id']]]
          [result.total,result.agents[run['agent_id']],result.buckets[run['bucket']]].each{|tally|add(tally,run,cost)}
          cost&.fetch(:models)&.each{|key,value|result.models[run['agent_id']][key]+=value}
        end
        result.pages+=1
        break unless page['next']
        raise Unavailable if result.pages>=MAX_PAGES
        cursor={after_started_at:page['next'].fetch('after_started_at'),after_id:page['next'].fetch('after_id')}
      end
      result
    end
    private
    def add(tally,run,cost)
      tally[:runs]+=1
      return unless cost
      net=cost[:net];tally[:costed_runs]+=1;tally[:cost]+=net;tally[:original]+=cost[:original]
      key={'success'=>:success_cost,'failure'=>:failed_cost,'cancelled'=>:cancelled_cost}.fetch(run['outcome'],:incomplete_cost);tally[key]+=net
      tally[:retried_success_cost]+=net if run['outcome']=='success'&&run['retried']
    end
  end
end
