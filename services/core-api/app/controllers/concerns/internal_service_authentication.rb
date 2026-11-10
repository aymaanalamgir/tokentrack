require "digest"
module InternalServiceAuthentication
  private
  def authenticate_internal_service!(environment_key)
    response.headers["Cache-Control"] = "no-store, private"
    expected = ENV[environment_key].to_s
    header = request.headers["Authorization"].to_s
    supplied = header.delete_prefix("Bearer ")
    unless expected.bytesize >= 32 && header.start_with?("Bearer ") && ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(expected), Digest::SHA256.hexdigest(supplied))
      render json: { error: { code: "service_unauthorized", message: "Service authentication required" } }, status: :unauthorized
    end
  end
end
