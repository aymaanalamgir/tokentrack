module Finance
  class PricedEventContract
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    UUID_FIELDS = %w[priced_event_id usage_event_id organization_id user_id project_id pricing_rate_id pricing_mapping_id].freeze
    DECIMAL_FIELDS = %w[amount input_cost cached_input_cost output_cost input_rate cached_input_rate output_rate].freeze
    TIME_FIELDS = %w[occurred_at rate_effective_from rate_effective_until rate_verified_at].freeze
    TEXT_FIELDS = %w[source source_event_id usage_fingerprint provider model pricing_provider pricing_model pricing_tier billing_basis currency rate_source_url tool agent_run_id workflow_type].freeze
    INTEGER_FIELDS = %w[schema_version calculation_version input_tokens cached_input_tokens output_tokens].freeze
    FIELDS = (UUID_FIELDS + DECIMAL_FIELDS + TIME_FIELDS + TEXT_FIELDS + INTEGER_FIELDS).freeze

    def self.normalize(input)
      raise Invalid, "Provide exactly the priced-usage-event v1 fields" unless input.is_a?(Hash) && input.keys.sort == FIELDS.sort
      row = input.dup
      UUID_FIELDS.each do |field|
        next if field == "project_id" && row[field].nil?
        raise Invalid, "Invalid #{field}" unless row[field].is_a?(String) && UUID.match?(row[field])
        row[field] = row[field].downcase
      end
      DECIMAL_FIELDS.each { |field| row[field] = Money.string(Money.parse(row[field], scale: field.end_with?("rate") ? 9 : 15)) }
      TIME_FIELDS.each do |field|
        next if field == "rate_effective_until" && row[field].nil?
        raise Invalid, "Invalid #{field}" unless row[field].is_a?(String) && row[field].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/)
        time = Time.iso8601(row[field]).utc
        raise Invalid, "Event times must be UTC years 2000–2099" unless time.year.between?(2000,2099)
        row[field] = time.iso8601(6)
      end
      INTEGER_FIELDS.each { |field| raise Invalid, "#{field} must be an integer" unless row[field].is_a?(Integer) && row[field].between?(0,1_000_000_000_000) }
      raise Invalid, "Unsupported contract/calculation version" unless row["schema_version"] == 1 && row["calculation_version"] == 1
      raise Invalid, "Invalid token categories" unless row["cached_input_tokens"] <= row["input_tokens"] && row["input_tokens"] + row["output_tokens"] > 0
      raise Invalid, "Unsupported currency/profile" unless row["currency"] == "USD" && row["pricing_tier"] == "standard_text_cache_read" && %w[synthetic_standard_cache_read attested_standard_cache_read].include?(row["billing_basis"])
      TEXT_FIELDS.each { |field| next if %w[agent_run_id workflow_type].include?(field) && row[field].nil?; raise Invalid, "Invalid #{field}" unless row[field].is_a?(String) && row[field].bytesize.between?(1,field == "rate_source_url" ? 2048 : 200) }
      %w[source provider pricing_provider].each { |field| raise Invalid, "Invalid #{field}" unless row[field].match?(/\A[a-z0-9][a-z0-9._-]{0,63}\z/) }
      %w[model pricing_model].each { |field| raise Invalid, "Invalid #{field}" unless row[field].match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/@+-]{0,199}\z/) }
      %w[agent_run_id workflow_type].each { |field| raise Invalid, "Invalid #{field}" unless row[field].nil? || row[field].match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,127}\z/) }
      raise Invalid, "Invalid tool" unless row["tool"].match?(/\A[a-z0-9][a-z0-9._-]{0,127}\z/)
      raise Invalid, "Invalid source event identity" unless row["source_event_id"].match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/-]{0,127}\z/) && row["usage_fingerprint"].match?(/\A[0-9a-f]{64}\z/)
      raise Invalid, "Cost components must add to the supplied amount" unless %w[input_cost cached_input_cost output_cost].sum { |field| BigDecimal(row[field]) } == BigDecimal(row["amount"])
      occurred = Time.iso8601(row["occurred_at"])
      raise Invalid, "Rate interval does not cover event time" unless Time.iso8601(row["rate_effective_from"]) <= occurred && (row["rate_effective_until"].nil? || occurred < Time.iso8601(row["rate_effective_until"]))
      row
    rescue ArgumentError
      raise Invalid, "Invalid timestamp or decimal"
    end
  end
end
