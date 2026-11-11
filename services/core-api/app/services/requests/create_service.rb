module Requests
  class CreateService
    def initialize(actor) = @actor = actor

    def call(request_type:, month:, requested_amount:, reason:, request_key:, project_id: nil, unit_id: nil, source_account_id: nil)
      date = Budgets::Controls.month(month)
      Budgets::Controls.key(request_key)
      amount = Finance::Money.parse(requested_amount)
      raise Finance::Invalid, "Requested amount must be positive" unless amount.positive?
      raise Finance::Invalid, "A reason of 1–500 characters is required" unless reason.is_a?(String) && reason.length.between?(1, 500)
      raise Finance::Invalid, "Invalid request type" unless FinancialRequest::TYPES.include?(request_type)

      ApplicationRecord.transaction do
        Finance::Money.lock("financial_request/create/#{@actor.organization_id}/#{@actor.id}/#{request_key}")
        actor = User.find(@actor.id)
        raise Finance::Forbidden, "An active employee is required" unless actor.status == "active"
        payload = {
          request_type: request_type, month: date.to_s, requested_amount: Finance::Money.string(amount),
          reason: reason, project_id: project_id, unit_id: unit_id, source_account_id: source_account_id
        }
        fingerprint = Finance::Money.fingerprint(payload)
        prior = FinancialRequest.find_by(organization_id: actor.organization_id, requester_id: actor.id, request_key: request_key)
        if prior
          raise Finance::Conflict, "Request key conflicts with its original payload" unless prior.request_fingerprint == fingerprint
          next prior
        end

        attributes = base_attributes(actor, request_type, date, amount, reason, request_key, fingerprint)
        enrich!(attributes, actor, project_id, unit_id, source_account_id)
        request = FinancialRequest.new(attributes)
        route = ApprovalRouter.new(request).route
        request.assigned_approver = route.approver
        request.routing_reason = route.reason
        request.save!
        append_event(request, actor, "created", nil, "pending", "Request created", "request/#{request.id}/created")
        append_event(request, actor, "submitted", "pending", "pending", reason, "request/#{request.id}/submitted", route: route.reason, assigned_approver_id: route.approver&.id)
        request
      end
    end

    private

    def base_attributes(actor, type, date, amount, reason, key, fingerprint)
      { organization_id: actor.organization_id, requester: actor, request_type: type, month_start: date,
        currency: "USD", requested_amount: amount, reason: reason, status: "pending", submitted_at: Time.current,
        request_key: key, request_fingerprint: fingerprint, routing_reason: "Routing pending" }
    end

    def enrich!(attributes, actor, project_id, unit_id, source_account_id)
      case attributes[:request_type]
      when "personal_allowance"
        raise Finance::Invalid, "Personal requests do not accept project, team, or source fields" if [project_id, unit_id, source_account_id].any?(&:present?)
        root = SpendingLimit.includes(:current_revision).find_by!(organization_id: actor.organization_id, user_id: actor.id, month_start: attributes[:month_start], currency: "USD")
        raise Finance::Invalid, "This allowance is not active" unless root.status == "active"
        periods = BudgetPeriod.where(organization_id: actor.organization_id, month_start: attributes[:month_start])
        raise Finance::Invalid, "This accounting month is closed" if periods.exists? && !periods.where(status: "open").exists?
        current = root.current_revision
        raise Finance::Invalid, "Requested ceiling must exceed the current ceiling" unless attributes[:requested_amount] > current.limit_amount
        attributes.merge!(target_user: actor, current_amount_snapshot: current.limit_amount, allowance_revision_snapshot: current)
      when "project_funding"
        project = Project.where(organization_id: actor.organization_id).find(project_id)
        raise Finance::Forbidden, "An explicit project-lead grant is required" unless AccessPolicy.new(actor).project_administrator?(project)
        raise Finance::Invalid, "Archived projects cannot request funding" if project.archived?
        target = BudgetAccount.find_by!(organization_id: actor.organization_id, project_id: project.id, purpose: "project", currency: "USD")
        source, source_period, target_period = funding_periods(actor, source_account_id, target, attributes[:month_start])
        attributes.merge!(target_project: project, target_budget_account: target, source_budget_account: source,
          current_amount_snapshot: target_period.funding, source_available_snapshot: source_period.available)
      when "team_funding"
        unit = OrganizationalUnit.where(organization_id: actor.organization_id).find(unit_id)
        raise Finance::Forbidden, "An explicit manager grant for this team is required" unless AccessPolicy.new(actor).managed_unit_ids.include?(unit.id)
        target = BudgetAccount.find_by!(organization_id: actor.organization_id, organizational_unit_id: unit.id, purpose: "unit", currency: "USD")
        source, source_period, target_period = funding_periods(actor, source_account_id, target, attributes[:month_start])
        attributes.merge!(target_unit: unit, target_budget_account: target, source_budget_account: source,
          current_amount_snapshot: target_period.funding, source_available_snapshot: source_period.available)
      end
    end

    def funding_periods(actor, source_id, target, month)
      source = BudgetAccount.where(organization_id: actor.organization_id, status: "active", currency: "USD").find(source_id)
      raise Finance::Invalid, "Funding source and target must differ" if source.id == target.id
      raise Finance::Invalid, "Funding target is inactive" unless target.status == "active"
      source_period = source.budget_periods.find_by!(month_start: month, currency: "USD")
      target_period = target.budget_periods.find_by!(month_start: month, currency: "USD")
      raise Finance::Invalid, "This accounting month is closed" unless source_period.status == "open" && target_period.status == "open"
      [source, source_period, target_period]
    end

    def append_event(request, actor, type, previous, current, reason, key, metadata = {})
      RequestEvent.create!(organization_id: request.organization_id, financial_request: request, actor: actor,
        event_type: type, previous_status: previous, new_status: current, reason: reason,
        operation_key: key, operation_fingerprint: Finance::Money.fingerprint(type: type, reason: reason, actor_id: actor.id), metadata: metadata)
    end
  end
end
