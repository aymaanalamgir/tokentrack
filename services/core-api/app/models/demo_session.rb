require "digest"

class DemoSession < ApplicationRecord
  include TenantRecord
  COOKIE = "tokentrack_demo_session".freeze
  LIFETIME = 8.hours
  belongs_to :user
  tenant_associations :user
  validates :token_digest, :expires_at, presence: true

  def self.enabled?
    (Rails.env.development? || Rails.env.test?) && ENV.fetch("DEMO_AUTH_ENABLED", "false") == "true"
  end

  def self.resolve(token)
    return unless enabled? && token.present? && token.length <= 128
    includes(user: :organization).find_by(token_digest: Digest::SHA256.hexdigest(token), expires_at: Time.current..)
  end
end
