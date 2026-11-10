module Api
  module V1
    class BudgetsController < BaseController
      rescue_from Finance::Forbidden do |error|
        render_error(:financial_forbidden,error.message.presence||'Explicit financial authority is required',:forbidden)
      end
      rescue_from Finance::Invalid, Analytics::Invalid do |error|
        render_error(:invalid_budget_operation,error.message,:unprocessable_content)
      end
      rescue_from Finance::Conflict, ActiveRecord::StaleObjectError do |error|
        render_error(:budget_conflict,error.message,:conflict)
      end
      rescue_from ActiveRecord::StatementInvalid do
        render_error(:budget_integrity_conflict,'The operation violates spending-control integrity. Reload before retrying.',:conflict)
      end
      def show
        raise Finance::Invalid,'Budget filters must be scalar strings' unless params.except(:controller,:action).values.all?{|v|v.is_a?(String)}
        render_data(Budgets::Report.new(current_user,params.except(:controller,:action).to_unsafe_h).call)
      end
      def transfer
        body=body_for(%w[from_account_id to_account_id month amount request_key reason])
        Budgets::Controls.month(body.fetch('month'))
        tx=Finance::Operations.new(current_user).transfer(from:body.fetch('from_account_id'),to:body.fetch('to_account_id'),month:body.fetch('month'),amount:body.fetch('amount'),key:body.fetch('request_key'),reason:body.fetch('reason'))
        render_data({id:tx.id,amount:Finance::Money.string(tx.amount)},status: :ok)
      end
      def fund
        body=body_for(%w[account_id month amount request_key reason])
        Budgets::Controls.month(body.fetch('month'))
        tx=Finance::Operations.new(current_user).fund(account:body.fetch('account_id'),month:body.fetch('month'),amount:body.fetch('amount'),key:body.fetch('request_key'),reason:body.fetch('reason'))
        render_data({id:tx.id,amount:Finance::Money.string(tx.amount)},status: :ok)
      end
      def initialize_month
        body=body_for(%w[month]);date=Budgets::Controls.month(body.fetch('month'))
        raise Finance::Forbidden unless policy.financial_operator?
        rows=ApplicationRecord.transaction do
          Finance::Money.lock("financial_operator/#{current_user.organization_id}")
          fresh=User.find(current_user.id)
          raise Finance::Forbidden unless fresh.status=='active' && AccessPolicy.new(fresh).financial_operator?
          BudgetAccount.where(organization_id:fresh.organization_id,status:'active').map do |account|
            account.budget_periods.find_or_create_by!(organization_id:fresh.organization_id,month_start:date,currency:'USD'){|p|p.status='open'}
          end
        end
        render_data({periods:rows.size,month:date.strftime('%Y-%m'),funding_created:'0'})
      end
      def ceiling
        body=body_for(%w[user_id month amount expected_revision request_key reason])
        revision=Budgets::AllowanceOperations.new(current_user).revise(user_id:body.fetch('user_id'),month:body.fetch('month'),amount:body.fetch('amount'),expected_revision:body['expected_revision'],request_key:body.fetch('request_key'),reason:body.fetch('reason'),kind:'ceiling')
        render_data({revision_id:revision.id,revision_number:revision.revision_number})
      end
      def allocations
        body=body_for(%w[month allocations expected_revision request_key reason])
        revision=Budgets::AllowanceOperations.new(current_user).revise(user_id:current_user.id,month:body.fetch('month'),allocations:body.fetch('allocations'),expected_revision:body['expected_revision'],request_key:body.fetch('request_key'),reason:body.fetch('reason'),kind:'reallocation')
        render_data({revision_id:revision.id,revision_number:revision.revision_number})
      end
      def delegate
        body=body_for(%w[manager_id unit_id maximum_amount from_month until_month request_key reason])
        grant=Budgets::AllowanceOperations.new(current_user).delegate(**body.symbolize_keys)
        render_data({id:grant.id})
      end
      def revoke
        body=body_for(%w[id]);grant=Budgets::AllowanceOperations.new(current_user).revoke(body.fetch('id'))
        render_data({id:grant.id,revoked:!!grant.revoked_at})
      end
      private
      def body_for(keys)
        raise Finance::Invalid,'Budget body must be a JSON object under budget' unless params[:budget].is_a?(ActionController::Parameters)
        values=params.require(:budget).to_unsafe_h
        raise Finance::Invalid,'Unexpected or missing budget fields' unless values.keys.sort==keys.sort
        values.each do |key,value|
          next if key=='allocations'
          next if key=='expected_revision' && value.nil?
          raise Finance::Invalid,'Budget field values must be strings' unless value.is_a?(String)
          if key.end_with?('_id') || key=='id' || key=='expected_revision'
            raise Finance::Invalid,'Invalid UUID' unless Analytics::Scope::UUID.match?(value)
          end
        end
        values
      end
    end
  end
end
