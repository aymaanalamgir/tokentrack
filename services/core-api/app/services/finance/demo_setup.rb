module Finance
  class DemoSetup
    def call(months)
      raise Forbidden, "Demo financial setup requires local fictional demo mode" unless DemoSession.enabled?
      result = []
      Organization.where(demo: true, slug: %w[northstar-labs aperture-technologies]).order(:id).each do |organization|
        key = organization.slug == "northstar-labs" ? "maya" : "olivia"
        actor = User.find(DemoData.uuid("#{organization.slug}/person/#{key}"))
        ApplicationRecord.transaction do
          RoleAssignment.find_or_create_by!(organization: organization, user: actor, role: "financial_operator", scope_type: "organization")
          first_month = months.map { |month| Money.month(month) }.min
          raise Invalid, "At least one month is required" unless first_month
          effective = Time.utc(first_month.year,first_month.month,1)
          accounts = []
          accounts << account(organization, "reserve", organization, effective)
          accounts << account(organization, "unassigned", organization, effective)
          organization.organizational_units.order(:id).each { |unit| accounts << account(organization, "unit", unit, effective) }
          organization.projects.where.not(status: "archived").order(:id).each { |project| accounts << account(organization, "project", project, effective) }
          operations = Operations.new(actor)
          months.each do |month|
            accounts.each do |record|
              BudgetPeriod.find_or_create_by!(id: DemoData.uuid("financial/period/#{record.id}/#{month}")) { |period| period.assign_attributes(organization: organization, budget_account: record, month_start: Money.month(month), currency: "USD", status: "open") }
            end
            reserve = accounts.find { |a| a.purpose == "reserve" }
            operations.fund(account: reserve.id, month: month, amount: "100000", key: "demo-funding/#{month}", reason: "Fictional organizational funding")
            { "unit" => "50000", "project" => "20000", "unassigned" => "20000" }.each do |purpose,pool|
              targets = accounts.select { |a| a.purpose == purpose }.sort_by(&:id)
              shares(pool,targets.size).zip(targets).each do |share,target|
                operations.transfer(from: reserve.id, to: target.id, month: month, amount: Money.string(share), key: "demo-allocation/#{month}/#{target.id}", reason: "Fictional budget allocation")
              end
            end
          end
          result << { organization_id: organization.id, actor_id: actor.id, accounts: accounts.map { |a| { id: a.id, purpose: a.purpose, name: a.name } }, months: months }
        end
      end
      result
    end
    private
    def account(organization,purpose,owner,effective)
      id = DemoData.uuid("financial/account/#{purpose}/#{owner.id}")
      BudgetAccount.find_or_create_by!(id: id) do |record|
        record.assign_attributes(organization: organization, name: "#{owner.name} #{purpose} AI budget", purpose: purpose, currency: "USD", effective_from: effective, status: "active",
          organizational_unit_id: purpose == "unit" ? owner.id : nil, project_id: purpose == "project" ? owner.id : nil)
      end
    end
    def shares(total,count)
      return [] if count.zero?
      units = (BigDecimal(total)*10**15).to_i
      quotient,remainder = units.divmod(count)
      count.times.map { |index| BigDecimal((quotient+(index<remainder ? 1 : 0)).to_s)/BigDecimal("1000000000000000") }
    end
  end
end
