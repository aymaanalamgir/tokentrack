module Requests
  class ApprovalRouter
    Result = Data.define(:approver, :reason, :eligible_approver_ids, :escalated)

    def initialize(financial_request)
      @request = financial_request
    end

    def route(force_financial: false)
      if @request.request_type == "personal_allowance" && !force_financial
        managers = eligible_managers
        if managers.any?
          cap = AccessPolicy.new(managers.first).allowance_maximum(@request.target_user, @request.month_start)
          return Result.new(managers.first, "Delegated direct manager authority covers the requested final ceiling (maximum #{Finance::Money.string(cap)} USD)", managers.map(&:id), false)
        end
      end
      operators = eligible_financial_operators
      reason = if @request.request_type == "personal_allowance"
        "Financial operator review is required because no active non-self manager delegation covers the requested final ceiling"
      else
        "Funding transfers require explicit organization financial-operator authority"
      end
      reason += "; awaiting an eligible financial operator" if operators.empty?
      Result.new(operators.first, reason, operators.map(&:id), force_financial)
    end

    def approval_authorized?(actor)
      return false unless actor.status == "active" && actor.organization_id == @request.organization_id && actor.id != @request.requester_id
      policy = AccessPolicy.new(actor)
      return true if policy.financial_operator?
      @request.request_type == "personal_allowance" && policy.manage_allowance?(@request.target_user, @request.requested_amount, @request.month_start)
    end

    def escalation_authorized?(actor)
      return false unless @request.request_type == "personal_allowance" && actor.id != @request.requester_id
      eligible_managers.any? { |manager| manager.id == actor.id }
    end

    private

    def eligible_managers
      return [] unless @request.target_user
      ids = ReportingRelationship.where(
        organization_id: @request.organization_id,
        report_id: @request.target_user_id,
        relationship_type: "line_manager"
      ).pluck(:manager_id)
      User.where(organization_id: @request.organization_id, id: ids, status: "active")
        .where.not(id: @request.requester_id).order(:name, :id).select do |manager|
          AccessPolicy.new(manager).manage_allowance?(@request.target_user, @request.requested_amount, @request.month_start)
        end
    end

    def eligible_financial_operators
      ids = RoleAssignment.where(
        organization_id: @request.organization_id,
        role: "financial_operator",
        scope_type: "organization"
      ).select(:user_id)
      User.where(organization_id: @request.organization_id, id: ids, status: "active")
        .where.not(id: @request.requester_id).order(:name, :id).to_a
    end
  end
end
