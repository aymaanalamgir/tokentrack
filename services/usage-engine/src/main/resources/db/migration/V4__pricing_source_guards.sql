CREATE UNIQUE INDEX usage_event_tenant_identity ON usage.usage_events(organization_id,id);
ALTER TABLE usage.priced_usage_events ADD CONSTRAINT priced_usage_tenant_reference FOREIGN KEY(organization_id,usage_event_id) REFERENCES usage.usage_events(organization_id,id) ON DELETE RESTRICT;
CREATE FUNCTION usage.validate_priced_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e usage.usage_events; r usage.model_pricing_rates; m usage.pricing_model_mappings;
BEGIN
 SELECT * INTO e FROM usage.usage_events WHERE id=NEW.usage_event_id;
 SELECT * INTO r FROM usage.model_pricing_rates WHERE id=NEW.pricing_rate_id;
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
CREATE TRIGGER priced_source_integrity BEFORE INSERT ON usage.priced_usage_events FOR EACH ROW EXECUTE FUNCTION usage.validate_priced_snapshot();
CREATE FUNCTION usage.validate_outbox_source() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE p.id=NEW.priced_usage_event_id
   AND NEW.payload->>'priced_event_id'=p.id::text AND NEW.payload->>'usage_event_id'=e.id::text AND NEW.payload->>'organization_id'=e.organization_id::text
   AND NEW.payload->>'user_id'=e.user_id::text AND (NEW.payload->>'project_id')::uuid IS NOT DISTINCT FROM e.project_id
   AND NEW.payload->>'provider'=e.provider AND NEW.payload->>'model'=e.model AND NEW.payload->>'source'=e.source AND NEW.payload->>'source_event_id'=e.event_id AND NEW.payload->>'usage_fingerprint'=e.payload_fingerprint
   AND NEW.payload->>'pricing_rate_id'=p.pricing_rate_id::text AND NEW.payload->>'pricing_mapping_id'=p.pricing_mapping_id::text
   AND NEW.payload->>'currency'=p.currency AND jsonb_typeof(NEW.payload->'amount')='string' AND (NEW.payload->>'amount')::numeric=p.total_cost
   AND (NEW.payload->>'input_cost')::numeric=p.input_cost AND (NEW.payload->>'cached_input_cost')::numeric=p.cached_input_cost AND (NEW.payload->>'output_cost')::numeric=p.output_cost)
 THEN RAISE EXCEPTION 'Outbox must preserve the priced financial source' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER outbox_source_integrity BEFORE INSERT ON usage.delivery_outbox FOR EACH ROW EXECUTE FUNCTION usage.validate_outbox_source();
