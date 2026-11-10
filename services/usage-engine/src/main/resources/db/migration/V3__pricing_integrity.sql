ALTER TABLE usage.model_pricing_rates ADD CONSTRAINT finite_model_rates CHECK(input_rate_per_million<'Infinity'::numeric AND cached_input_rate_per_million<'Infinity'::numeric AND output_rate_per_million<'Infinity'::numeric);
ALTER TABLE usage.priced_usage_events ADD CONSTRAINT finite_priced_costs CHECK(input_cost<'Infinity'::numeric AND cached_input_cost<'Infinity'::numeric AND output_cost<'Infinity'::numeric AND total_cost<'Infinity'::numeric);
ALTER TABLE usage.priced_usage_events ADD CONSTRAINT exact_snapshot_components CHECK(
 input_cost=(input_tokens-cached_input_tokens)*input_rate_snapshot/1000000 AND
 cached_input_cost=cached_input_tokens*cached_input_rate_snapshot/1000000 AND output_cost=output_tokens*output_rate_snapshot/1000000);
CREATE TRIGGER rates_no_truncate BEFORE TRUNCATE ON usage.model_pricing_rates FOR EACH STATEMENT EXECUTE FUNCTION usage.reject_pricing_mutation();
CREATE TRIGGER mappings_no_truncate BEFORE TRUNCATE ON usage.pricing_model_mappings FOR EACH STATEMENT EXECUTE FUNCTION usage.reject_pricing_mutation();
CREATE TRIGGER priced_events_no_truncate BEFORE TRUNCATE ON usage.priced_usage_events FOR EACH STATEMENT EXECUTE FUNCTION usage.reject_pricing_mutation();
CREATE TRIGGER outbox_no_truncate BEFORE TRUNCATE ON usage.delivery_outbox FOR EACH STATEMENT EXECUTE FUNCTION usage.reject_pricing_mutation();
