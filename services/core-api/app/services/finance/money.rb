require "bigdecimal"
require "digest"
require "json"
module Finance
  module Money
    module_function
    def parse(value, scale: 15)
      raise Invalid, "Amounts must be nonnegative decimal strings with at most #{scale} fractional places" unless value.is_a?(String) && value.match?(/\A(?:0|[1-9][0-9]{0,19})(?:\.[0-9]{1,#{scale}})?\z/)
      BigDecimal(value)
    end
    def string(value)
      return "0" if BigDecimal(value.to_s).zero?
      number = BigDecimal(value.to_s).to_s("F")
      number.include?(".") ? number.sub(/0+\z/, "").sub(/\.\z/, "") : number
    end
    def month(value)
      raise Invalid, "Month must be YYYY-MM in UTC" unless value.to_s.match?(/\A[0-9]{4}-(?:0[1-9]|1[0-2])\z/)
      Date.strptime(value, "%Y-%m")
    rescue Date::Error
      raise Invalid, "Invalid accounting month"
    end
    def fingerprint(payload) = Digest::SHA256.hexdigest(JSON.generate(payload.sort.to_h))
    def lock(key)
      ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{ApplicationRecord.connection.quote(key)},51005))")
    end
  end
end
