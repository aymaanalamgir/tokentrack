module Finance
  class PricedUsagePosting
    def call(input)
      payload = PricedEventContract.normalize(input)
      fingerprint = Money.fingerprint(payload)
      ApplicationRecord.transaction do
        Money.lock("financial_usage/#{payload.fetch('usage_event_id')}")
        receipt = PricedUsageReceipt.where(id: payload["priced_event_id"]).or(PricedUsageReceipt.where(usage_event_id: payload["usage_event_id"])).first
        if receipt
          raise Conflict, "Financial source identity conflicts with its original payload" unless receipt.id == payload["priced_event_id"] && receipt.usage_event_id == payload["usage_event_id"] && receipt.payload_fingerprint == fingerprint
          next acknowledgment(receipt, true) if receipt.status == "posted"
        else
          organization = Organization.find(payload["organization_id"])
          User.where(organization_id: organization.id).find(payload["user_id"])
          Project.where(organization_id: organization.id).find(payload["project_id"]) if payload["project_id"]
          receipt = PricedUsageReceipt.create!(id: payload["priced_event_id"], organization_id: organization.id, usage_event_id: payload["usage_event_id"], user_id: payload["user_id"], project_id: payload["project_id"], occurred_at: payload["occurred_at"], amount: payload["amount"], currency: payload["currency"], payload: payload, payload_fingerprint: fingerprint, status: "unresolved")
        end
        owner = ChargeOwnerResolver.new.call(receipt)
        unless owner[:period]
          receipt.update!(resolution_code: owner.fetch(:code))
          next acknowledgment(receipt, false)
        end
        period = BudgetPeriod.lock.find(owner.fetch(:period).id)
        raise Conflict, "Accounting period closed while resolving ownership; retry" unless period.status == "open"
        transaction = FinancialTransaction.create!(organization_id: receipt.organization_id, kind: "usage_charge", currency: receipt.currency, month_start: period.month_start, amount: receipt.amount,
          source_type: "priced_usage_event", source_id: receipt.id, request_fingerprint: fingerprint, priced_usage_receipt: receipt, usage_event_id: receipt.usage_event_id,
          user_id: receipt.user_id, project_id: receipt.project_id, home_unit_id: owner[:home_unit_id], reason: "Priced standard token usage", audit_metadata: owner[:audit])
        LedgerEntry.create!(organization_id: receipt.organization_id, financial_transaction: transaction, budget_period: period, funding_delta: 0, expense_delta: receipt.amount)
        receipt.update!(status: "posted", resolution_code: nil, financial_transaction: transaction)
        acknowledgment(receipt, false)
      end
    end

    def acknowledgment(receipt, duplicate)
      { schema_version: 1, priced_event_id: receipt.id, usage_event_id: receipt.usage_event_id, status: receipt.status, amount: Money.string(receipt.amount), currency: receipt.currency,
        financial_transaction_id: receipt.financial_transaction_id, code: receipt.resolution_code, duplicate: duplicate }
    end
  end
end
