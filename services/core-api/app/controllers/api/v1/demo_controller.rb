module Api
  module V1
    class DemoController < BaseController
      skip_before_action :authenticate!
      before_action :demo_enabled!

      def identities
        people = User.joins(:organization).where(demo_identity: true, status: "active", organizations: { demo: true }).includes(:organization, :role_assignments, organizational_memberships: :organizational_unit).order("organizations.name", :name)
        render_data(people.map do |person|
          { id: person.id, name: person.name, job_title: person.job_title, organization: person.organization.slice(:id, :name, :slug), persona: AccessPolicy.new(person).persona, primary_team: person.organizational_memberships.find(&:is_primary?)&.organizational_unit&.name }
        end)
      end

      def create
        person = User.joins(:organization).where(demo_identity: true, status: "active", organizations: { demo: true }).find(params.require(:user_id))
        token = SecureRandom.urlsafe_base64(48)
        DemoSession.transaction do
          current_session&.destroy!
          DemoSession.where(expires_at: ...Time.current).delete_all
          DemoSession.create!(user: person, organization: person.organization, token_digest: Digest::SHA256.hexdigest(token), expires_at: DemoSession::LIFETIME.from_now)
        end
        response.set_cookie(DemoSession::COOKIE, value: token, httponly: true, same_site: :lax, path: "/", max_age: DemoSession::LIFETIME.to_i, secure: request.ssl?)
        render_data({ user_id: person.id, organization_id: person.organization_id }, status: :created)
      end

      def destroy
        current_session&.destroy!
        response.delete_cookie(DemoSession::COOKIE, path: "/", httponly: true, same_site: :lax)
        render_data({ signed_out: true })
      end

      private

      def demo_enabled!
        render_error(:demo_disabled, "Demo authentication is disabled", :not_found) unless DemoSession.enabled?
      end
    end
  end
end
