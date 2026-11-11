module Requests
  class DecisionService
    def initialize(actor) = @actor = actor

    def approve(id:, operation_key:, comment:)
      decide(id, "approved", operation_key, comment) do |request, actor|
        router = ApprovalRouter.new(request)
        raise Finance::Forbidden, "Current approval authority is required" unless router.approval_authorized?(actor)
        if request.request_type == "personal_allowance"
          current = SpendingLimit.find_by!(organization_id: request.organization_id, user_id: request.target_user_id, month_start: request.month_start, currency: "USD").current_revision
          raise Finance::Conflict, "The allowance changed after submission; cancel and submit a current request" unless current.id == request.allowance_revision_snapshot_id
          revision = Budgets::AllowanceOperations.new(actor).revise(
            user_id: request.target_user_id, month: request.month_start.strftime("%Y-%m"), amount: Finance::Money.string(request.requested_amount),
            expected_revision: request.allowance_revision_snapshot_id, request_key: "request/#{request.id}/approve",
            reason: execution_reason(request, comment), kind: "ceiling"
          )
          request.execution_revision = revision
          ["allowance_revision_id", revision.id]
        else
          transaction = Finance::Operations.new(actor).transfer(
            from: request.source_budget_account_id, to: request.target_budget_account_id,
            month: request.month_start.strftime("%Y-%m"), amount: Finance::Money.string(request.requested_amount),
            key: "request/#{request.id}/approve", reason: execution_reason(request, comment)
          )
          request.execution_transaction = transaction
          ["financial_transaction_id", transaction.id]
        end
      end
    end

    def reject(id:, operation_key:, comment:)
      raise Finance::Invalid, "A rejection reason is required" unless comment.is_a?(String) && comment.length.between?(1, 500)
      decide(id, "rejected", operation_key, comment) do |request, actor|
        raise Finance::Forbidden, "Current approval authority is required" unless ApprovalRouter.new(request).approval_authorized?(actor)
        nil
      end
    end

    def cancel(id:, operation_key:, comment:)
      decide(id, "cancelled", operation_key, comment.presence || "Cancelled by requester") do |request, actor|
        raise Finance::Forbidden, "Only the requester can cancel a pending request" unless request.requester_id == actor.id
        nil
      end
    end

    def escalate(id:, operation_key:, comment:)
      validate_command(operation_key, comment)
      ApplicationRecord.transaction do
        request = scoped.lock.find(id)
        fingerprint = command_fingerprint("escalated", request, comment)
        return replay!(request, "escalated", operation_key, fingerprint) unless request.pending?
        router = ApprovalRouter.new(request)
        raise Finance::Forbidden, "Only an eligible delegated manager can escalate this request" unless router.escalation_authorized?(@actor)
        route = router.route(force_financial: true)
        request.update!(assigned_approver: route.approver, routing_reason: route.reason, escalated_at: Time.current)
        append_event(request, @actor, "escalated", "pending", "pending", comment.presence || route.reason, operation_key, fingerprint,
          assigned_approver_id: route.approver&.id, routing_reason: route.reason)
        request
      end
    end

    private

    def decide(id, status, key, comment)
      validate_command(key, comment)
      ApplicationRecord.transaction do
        request = scoped.lock.find(id)
        fingerprint = command_fingerprint(status, request, comment)
        return replay!(request, status, key, fingerprint) unless request.pending?
        raise Finance::Forbidden, "Self-approval is not permitted" if status != "cancelled" && request.requester_id == @actor.id
        execution = yield(request, User.find(@actor.id))
        request.status = status
        request.resolved_at = Time.current
        request.save!
        append_event(request, @actor, status, "pending", status, comment.presence || status.humanize, key, fingerprint)
        if status == "approved"
          append_event(request, @actor, "executed", "approved", "approved", "Approved business effect completed",
            "request/#{request.id}/executed", Finance::Money.fingerprint(request_id: request.id, execution: execution), { execution&.first => execution&.last }.compact)
        end
        request
      end
    end

    def scoped
      base = FinancialRequest.where(organization_id: @actor.organization_id)
      return base if AccessPolicy.new(@actor).financial_operator?
      reviewed = RequestEvent.where(organization_id: @actor.organization_id, actor_id: @actor.id).select(:financial_request_id)
      base.where(requester_id: @actor.id).or(base.where(assigned_approver_id: @actor.id)).or(base.where(id: reviewed))
    end
    def validate_command(key, comment)
      Budgets::Controls.key(key)
      raise Finance::Invalid, "Decision comments must be at most 500 characters" unless comment.is_a?(String) && comment.length <= 500
    end
    def execution_reason(request, comment) = "Approved request #{request.id}: #{comment.presence || request.reason}".first(500)
    def command_fingerprint(action, request, comment) = Finance::Money.fingerprint(action: action, request_id: request.id, actor_id: @actor.id, comment: comment)

    def replay!(request, action, key, fingerprint)
      event = request.request_events.find_by(operation_key: key)
      raise Finance::Conflict, "Request has already been finalized" unless event && event.event_type == action && event.operation_fingerprint == fingerprint
      request
    end

    def append_event(request, actor, type, previous, current, reason, key, fingerprint, metadata = {})
      RequestEvent.create!(organization_id: request.organization_id, financial_request: request, actor: actor,
        event_type: type, previous_status: previous, new_status: current, reason: reason,
        operation_key: key, operation_fingerprint: fingerprint, metadata: metadata)
    end
  end
end
