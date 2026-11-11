module Requests
  class Report
    UUID = Analytics::Scope::UUID

    def initialize(actor, params = {})
      @actor = actor
      @policy = AccessPolicy.new(actor)
      @params = params.stringify_keys
    end

    def call
      validate_filters!
      relation = filtered(visible.includes(:requester, :target_user, :target_project, :target_unit,
        :target_budget_account, :source_budget_account, :assigned_approver, request_events: :actor))
      limit = integer("limit", 50, 1, 100)
      offset = integer("offset", 0, 0, 100_000)
      mine = relation.where(requester_id: @actor.id).order(submitted_at: :desc)
      review = pending_review(relation).order(submitted_at: :asc)
      history = relation.where.not(status: "pending").order(resolved_at: :desc)
      {
        month: selected_month.strftime("%Y-%m"),
        my_requests: rows(mine.limit(limit).offset(offset)),
        pending_review: rows(review.limit(limit).offset(offset)),
        history: rows(history.limit(limit).offset(offset)),
        meta: { limit: limit, offset: offset, my_total: mine.count, review_total: review.count, history_total: history.count },
        options: options,
        filters: @params.slice("request_type", "status", "month", "requester_id", "project_id", "unit_id", "assigned_approver_id")
      }
    end

    def find(id)
      request = visible.includes(:requester, :target_user, :target_project, :target_unit,
        :target_budget_account, :source_budget_account, :assigned_approver, request_events: :actor).find(id)
      present(request, include_events: true)
    end

    private

    def visible
      base = FinancialRequest.where(organization_id: @actor.organization_id)
      return base if @policy.financial_operator?
      reviewed = RequestEvent.where(organization_id: @actor.organization_id, actor_id: @actor.id).select(:financial_request_id)
      base.where(requester_id: @actor.id).or(base.where(assigned_approver_id: @actor.id)).or(base.where(id: reviewed))
    end

    def pending_review(relation)
      pending = relation.where(status: "pending").where.not(requester_id: @actor.id)
      @policy.financial_operator? ? pending : pending.where(assigned_approver_id: @actor.id)
    end

    def filtered(relation)
      relation = relation.where(request_type: @params["request_type"]) if @params["request_type"].present?
      relation = relation.where(status: @params["status"]) if @params["status"].present?
      relation = relation.where(month_start: selected_month) if @params["month"].present?
      { "requester_id" => :requester_id, "project_id" => :target_project_id, "unit_id" => :target_unit_id,
        "assigned_approver_id" => :assigned_approver_id }.each do |input, column|
        relation = relation.where(column => @params[input]) if @params[input].present?
      end
      relation
    end

    def rows(relation) = relation.map { |request| present(request) }

    def present(request, include_events: false)
      router = ApprovalRouter.new(request)
      target = request.target_user || request.target_project || request.target_unit
      amount_kind = request.request_type == "personal_allowance" ? "desired_total_ceiling" : "additional_funding"
      data = {
        id: request.id, request_type: request.request_type, status: request.status,
        requester: { id: request.requester_id, name: request.requester.name },
        target: target && { id: target.id, name: target.name },
        target_account: request.target_budget_account && { id: request.target_budget_account_id, name: request.target_budget_account.name },
        source_account: request.source_budget_account && { id: request.source_budget_account_id, name: request.source_budget_account.name },
        month: request.month_start.strftime("%Y-%m"), currency: request.currency,
        amount_semantics: amount_kind,
        current_amount_snapshot: Finance::Money.string(request.current_amount_snapshot),
        source_available_snapshot: request.source_available_snapshot && Finance::Money.string(request.source_available_snapshot),
        requested_amount: Finance::Money.string(request.requested_amount),
        difference: Finance::Money.string(request.request_type == "personal_allowance" ? request.requested_amount - request.current_amount_snapshot : request.requested_amount),
        reason: request.reason, submitted_at: request.submitted_at, resolved_at: request.resolved_at,
        assigned_approver: request.assigned_approver && { id: request.assigned_approver_id, name: request.assigned_approver.name },
        routing_reason: request.routing_reason, escalated_at: request.escalated_at,
        execution: { transaction_id: request.execution_transaction_id, revision_id: request.execution_revision_id }.compact,
        capabilities: {
          approve: request.pending? && router.approval_authorized?(@actor),
          reject: request.pending? && router.approval_authorized?(@actor),
          escalate: request.pending? && router.escalation_authorized?(@actor),
          cancel: request.pending? && request.requester_id == @actor.id
        }
      }
      if include_events
        data[:events] = request.request_events.sort_by(&:created_at).map do |event|
          { id: event.id, type: event.event_type, actor: { id: event.actor_id, name: event.actor.name },
            previous_status: event.previous_status, new_status: event.new_status, reason: event.reason,
            metadata: event.metadata, created_at: event.created_at }
        end
      end
      data
    end

    def options
      month = selected_month
      led = Project.where(organization_id: @actor.organization_id, status: %w[active planned], id: @policy.grants.filter_map { |grant| grant.project_id if grant.role == "project_lead" }).order(:name)
      units = OrganizationalUnit.where(organization_id: @actor.organization_id, id: @policy.managed_unit_ids).order(:name)
      sources = if led.exists? || units.exists?
        BudgetAccount.includes(:budget_periods).where(organization_id: @actor.organization_id, status: "active", currency: "USD", purpose: %w[reserve unassigned unit]).order(:name).filter_map do |account|
          period = account.budget_periods.find { |candidate| candidate.month_start == month }
          { id: account.id, name: account.name, purpose: account.purpose, available: Finance::Money.string(period.available) } if period
        end
      else
        []
      end
      {
        allowance: allowance_option(month),
        projects: led.filter_map { |project| funding_option(project, :project, month) },
        units: units.filter_map { |unit| funding_option(unit, :unit, month) },
        sources: sources,
        requesters: @policy.financial_operator? ? User.where(organization_id: @actor.organization_id).order(:name).map { |u| { id: u.id, name: u.name } } : []
      }
    end

    def allowance_option(month)
      root = SpendingLimit.includes(:current_revision).find_by(organization_id: @actor.organization_id, user_id: @actor.id, month_start: month, currency: "USD")
      root&.current_revision && { current_ceiling: Finance::Money.string(root.current_revision.limit_amount), revision_id: root.current_revision_id }
    end

    def funding_option(record, kind, month)
      account = BudgetAccount.includes(:budget_periods).find_by(organization_id: @actor.organization_id,
        (kind == :project ? :project_id : :organizational_unit_id) => record.id, purpose: kind.to_s, currency: "USD")
      period = account&.budget_periods&.find { |candidate| candidate.month_start == month }
      return unless account && period
      { id: record.id, name: record.name, account_id: account.id, funding: Finance::Money.string(period.funding),
        expenditure: Finance::Money.string(period.expenditure), available: Finance::Money.string(period.available) }
    end

    def selected_month = @selected_month ||= Budgets::Controls.month(@params["month"].presence || Date.current.strftime("%Y-%m"))
    def integer(key, default, minimum, maximum)
      value = @params[key].presence || default.to_s
      raise Finance::Invalid, "#{key} must be an integer" unless value.to_s.match?(/\A\d+\z/)
      value.to_i.clamp(minimum, maximum)
    end
    def validate_filters!
      allowed = %w[request_type status month requester_id project_id unit_id assigned_approver_id limit offset]
      raise Finance::Invalid, "Unknown request filter" unless (@params.keys - allowed).empty?
      raise Finance::Invalid, "Request filters must be scalar strings" unless @params.values.all? { |value| value.is_a?(String) }
      raise Finance::Invalid, "Invalid request type" if @params["request_type"].present? && !FinancialRequest::TYPES.include?(@params["request_type"])
      raise Finance::Invalid, "Invalid request status" if @params["status"].present? && !FinancialRequest::STATUSES.include?(@params["status"])
      %w[requester_id project_id unit_id assigned_approver_id].each do |key|
        raise Finance::Invalid, "Invalid UUID filter" if @params[key].present? && !UUID.match?(@params[key])
      end
      selected_month if @params["month"].present?
    end
  end
end
