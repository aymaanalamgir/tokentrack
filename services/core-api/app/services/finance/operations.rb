module Finance
  class Operations
    def initialize(actor) = @actor = actor

    def fund(account:, month:, amount:, key:, reason:)
      value = Money.parse(amount)
      raise Invalid, "Funding must be positive" unless value.positive?
      operate do |actor|
        account = scoped_account(account, actor)
        raise Invalid, "Initial funding enters the organizational reserve" unless account.purpose == "reserve"
        period = period_for(account, month)
        payload = { account: account.id, month: period.month_start.to_s, amount: Money.string(value), reason: reason }
        existing = idempotent(actor, "initial_funding", key, payload)
        next existing if existing
        lock_periods([period])
        tx = append(actor, "funding", period, value, "initial_funding", key, payload, reason)
        entry(tx, period, value, 0)
        tx
      end
    end

    def transfer(from:, to:, month:, amount:, key:, reason:)
      value = Money.parse(amount)
      raise Invalid, "Transfer must be positive" unless value.positive?
      operate do |actor|
        source = period_for(scoped_account(from, actor), month)
        target = period_for(scoped_account(to, actor), month)
        raise Invalid, "Transfer accounts must differ" if source.id == target.id
        payload = { from: source.id, to: target.id, amount: Money.string(value), reason: reason }
        existing = idempotent(actor, "funding_transfer", key, payload)
        next existing if existing
        lock_periods([source,target])
        raise Invalid, "Transfer exceeds the source's available allocation" if source.available < value
        tx = append(actor, "transfer", source, value, "funding_transfer", key, payload, reason)
        entry(tx, source, -value, 0)
        entry(tx, target, value, 0)
        tx
      end
    end

    def correct(original_id:, amount:, key:, reason:)
      replacement = amount.nil? ? nil : Money.parse(amount)
      operate do |actor|
        original = FinancialTransaction.where(organization_id: actor.organization_id, kind: %w[usage_charge adjustment]).find(original_id)
        payload = { original_id: original.id, amount: replacement && Money.string(replacement), reason: reason }
        previous = idempotent(actor, "expense_reversal", key, payload)
        if previous
          next previous.correction_group_id ? FinancialTransaction.where(correction_group_id: previous.correction_group_id).order(:kind).to_a : [previous]
        end
        raise Conflict, "The expense already has a reversal" if FinancialTransaction.exists?(organization_id: actor.organization_id, kind: "reversal", original_transaction_id: original.id)
        period = original.ledger_entries.first!.budget_period
        lock_periods([period], require_open: false)
        group = replacement.nil? ? nil : SecureRandom.uuid
        attrs = { original_transaction: original, correction_group_id: group, user_id: original.user_id, project_id: original.project_id, home_unit_id: original.home_unit_id }
        reversal = append(actor, "reversal", period, original.amount, "expense_reversal", key, payload, reason, **attrs)
        entry(reversal, period, 0, -original.amount)
        records = [reversal]
        unless replacement.nil?
          adjusted = append(actor, "adjustment", period, replacement, "expense_replacement", key, payload, reason, **attrs)
          entry(adjusted, period, 0, replacement)
          records << adjusted
        end
        records
      end
    end

    private

    def operate
      ApplicationRecord.transaction do
        Money.lock("financial_operator/#{@actor.organization_id}")
        actor = User.find(@actor.id)
        raise Forbidden, "Explicit financial operator authority is required" unless actor.status == "active" && AccessPolicy.new(actor).financial_operator?
        yield actor
      end
    end
    def scoped_account(id, actor) = BudgetAccount.where(organization_id: actor.organization_id).find(id)
    def period_for(account, month)
      raise Invalid, "Account is inactive" unless account.status == "active"
      account.budget_periods.find_by!(month_start: Money.month(month), currency: "USD")
    end
    def lock_periods(periods, require_open: true)
      BudgetPeriod.where(id: periods.map(&:id)).order(:id).lock.each do |period|
        raise Invalid, "Accounting period is closed" if require_open && period.status != "open"
      end
    end
    def idempotent(actor, type, key, payload)
      raise Invalid, "A stable ASCII operation key is required" unless key.to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,127}\z/)
      tx = FinancialTransaction.find_by(organization_id: actor.organization_id, source_type: type, source_id: key)
      raise Conflict, "Operation key conflicts with its original request" if tx && tx.request_fingerprint != Money.fingerprint(payload)
      tx
    end
    def append(actor, kind, period, amount, type, key, payload, reason, **extra)
      FinancialTransaction.create!({ organization_id: actor.organization_id, kind: kind, currency: "USD", month_start: period.month_start, amount: amount, source_type: type, source_id: key, request_fingerprint: Money.fingerprint(payload), actor: actor, reason: reason }.merge(extra))
    end
    def entry(tx, period, funding, expense)
      LedgerEntry.create!(organization_id: tx.organization_id, financial_transaction: tx, budget_period: period, funding_delta: funding, expense_delta: expense)
    end
  end
end
