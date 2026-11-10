CREATE OR REPLACE FUNCTION usage.validate_priced_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e usage.usage_events; r usage.model_pricing_rates; m usage.pricing_model_mappings;
BEGIN
 SELECT * INTO e FROM usage.usage_events WHERE id=NEW.usage_event_id;
 SELECT * INTO r FROM usage.model_pricing_rates WHERE id=NEW.pricing_rate_id FOR SHARE;
 SELECT * INTO m FROM usage.pricing_model_mappings WHERE id=NEW.pricing_mapping_id;
 IF e.id IS NULL OR r.id IS NULL OR m.id IS NULL OR NEW.organization_id<>e.organization_id OR NEW.provider<>e.provider OR NEW.model<>e.model OR NEW.input_tokens<>e.input_tokens OR NEW.cached_input_tokens<>e.cached_input_tokens OR NEW.output_tokens<>e.output_tokens
   OR m.source<>e.source OR m.source_provider<>e.provider OR m.source_model<>e.model OR m.target_provider<>r.provider OR m.target_model<>r.model OR m.currency<>r.currency OR m.pricing_tier<>r.pricing_tier
   OR NEW.pricing_provider<>r.provider OR NEW.pricing_model<>r.model OR NEW.currency<>r.currency OR NEW.pricing_tier<>r.pricing_tier OR NEW.billing_basis<>m.billing_basis
   OR NEW.input_rate_snapshot<>r.input_rate_per_million OR NEW.cached_input_rate_snapshot<>r.cached_input_rate_per_million OR NEW.output_rate_snapshot<>r.output_rate_per_million
   OR NEW.effective_from_snapshot<>r.effective_from OR NEW.effective_until_snapshot IS DISTINCT FROM r.effective_until OR NEW.source_url_snapshot<>r.source_url OR NEW.verified_at_snapshot<>r.verified_at
   OR e.occurred_at<r.effective_from OR (r.effective_until IS NOT NULL AND e.occurred_at>=r.effective_until)
   OR m.billing_basis NOT IN('synthetic_standard_cache_read','attested_standard_cache_read') OR m.pricing_tier<>'standard_text_cache_read' OR e.input_tokens>m.max_input_tokens OR e.output_tokens>m.max_output_tokens OR e.input_tokens+e.output_tokens>m.max_context_tokens
 THEN RAISE EXCEPTION 'Priced snapshot must match its canonical source and supported schedule' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;

CREATE FUNCTION usage.guard_rate_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Pricing history cannot be deleted' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-'effective_until') IS DISTINCT FROM (to_jsonb(OLD)-'effective_until')
 THEN RAISE EXCEPTION 'Published price values and provenance are immutable' USING ERRCODE='23514'; END IF;
 IF NEW.effective_until IS NOT DISTINCT FROM OLD.effective_until THEN RETURN NEW; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.provider||'/'||NEW.model||'/'||NEW.currency||'/'||NEW.pricing_tier,51001));
 IF OLD.effective_until IS NOT NULL OR NEW.effective_until IS NULL OR NEW.effective_until<=OLD.effective_from
   OR EXISTS(SELECT 1 FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE p.pricing_rate_id=OLD.id AND e.occurred_at>=NEW.effective_until)
 THEN RAISE EXCEPTION 'Schedule closure cannot invalidate an existing priced event' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER rates_immutable ON usage.model_pricing_rates;
CREATE TRIGGER rates_immutable BEFORE UPDATE OR DELETE ON usage.model_pricing_rates FOR EACH ROW EXECUTE FUNCTION usage.guard_rate_history();
