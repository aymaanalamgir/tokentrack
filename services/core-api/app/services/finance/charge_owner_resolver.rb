module Finance
  class ChargeOwnerResolver
    def call(receipt)
      time = receipt.occurred_at
      home = OrganizationalMembership.where(organization_id: receipt.organization_id, user_id: receipt.user_id, is_primary: true).where("created_at<=? AND updated_at<=?", time, time).first
      audit = { home_attribution: home ? "unchanged_current_record_covers_event" : "historical_home_unknown", home_membership_id: home&.id }
      if receipt.project_id && !ProjectMembership.where(organization_id: receipt.organization_id, project_id: receipt.project_id, user_id: receipt.user_id).where("joined_at<=? AND (left_at IS NULL OR left_at>?)", time, time).exists?
        return { code: "PROJECT_HISTORY_UNRESOLVED", home_unit_id: home&.organizational_unit_id, audit: audit }
      end
      accounts = BudgetAccount.where(organization_id: receipt.organization_id, currency: receipt.currency, status: "active").where("effective_from<=? AND (effective_until IS NULL OR effective_until>?)", time, time)
      choices = []
      choices << [accounts.find_by(purpose: "project", project_id: receipt.project_id), "project"] if receipt.project_id
      choices << [accounts.find_by(purpose: "unit", organizational_unit_id: home.organizational_unit_id), "home_team"] if home
      choices << [accounts.find_by(purpose: "unassigned"), "unassigned"]
      choices.each do |account, reason|
        next unless account
        period = account.budget_periods.find_by(organization_id: receipt.organization_id, month_start: time.utc.to_date.beginning_of_month, status: "open", currency: receipt.currency)
        next unless period&.funded?
        return { period: period, home_unit_id: home&.organizational_unit_id, audit: audit.merge(charge_owner: reason) }
      end
      { code: "NO_FUNDED_CHARGE_OWNER", home_unit_id: home&.organizational_unit_id, audit: audit }
    end
  end
end
