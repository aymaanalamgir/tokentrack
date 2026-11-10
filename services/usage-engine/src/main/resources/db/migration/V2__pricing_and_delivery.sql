CREATE TABLE usage.model_pricing_rates (
 id uuid PRIMARY KEY, provider varchar(64) NOT NULL, model varchar(200) NOT NULL,
 pricing_tier varchar(64) NOT NULL, currency char(3) NOT NULL CHECK(currency='USD'),
 input_rate_per_million numeric(18,9) NOT NULL CHECK(input_rate_per_million>=0),
 cached_input_rate_per_million numeric(18,9) NOT NULL CHECK(cached_input_rate_per_million>=0),
 output_rate_per_million numeric(18,9) NOT NULL CHECK(output_rate_per_million>=0),
 effective_from timestamptz NOT NULL, effective_until timestamptz,
 source_url varchar(2048) NOT NULL, verified_at timestamptz NOT NULL, synthetic boolean NOT NULL DEFAULT false,
 CHECK(effective_until IS NULL OR effective_until>effective_from)
);
CREATE INDEX model_pricing_lookup ON usage.model_pricing_rates(provider,model,currency,pricing_tier,effective_from);
CREATE FUNCTION usage.prevent_price_overlap() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.provider||'/'||NEW.model||'/'||NEW.currency||'/'||NEW.pricing_tier,51001));
 IF EXISTS(SELECT 1 FROM usage.model_pricing_rates r WHERE r.provider=NEW.provider AND r.model=NEW.model AND r.currency=NEW.currency AND r.pricing_tier=NEW.pricing_tier
 AND tstzrange(r.effective_from,r.effective_until,'[)') && tstzrange(NEW.effective_from,NEW.effective_until,'[)') AND r.id<>NEW.id)
 THEN RAISE EXCEPTION 'Overlapping pricing periods' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER pricing_periods_no_overlap BEFORE INSERT ON usage.model_pricing_rates FOR EACH ROW EXECUTE FUNCTION usage.prevent_price_overlap();
CREATE TABLE usage.pricing_model_mappings (
 id uuid PRIMARY KEY, source varchar(64) NOT NULL, source_provider varchar(64) NOT NULL, source_model varchar(200) NOT NULL,
 target_provider varchar(64) NOT NULL, target_model varchar(200) NOT NULL,
 pricing_tier varchar(64) NOT NULL, currency char(3) NOT NULL CHECK(currency='USD'),
 billing_basis varchar(64) NOT NULL, description varchar(500) NOT NULL,
 max_input_tokens bigint NOT NULL CHECK(max_input_tokens>0), max_output_tokens bigint NOT NULL CHECK(max_output_tokens>0),
 max_context_tokens bigint NOT NULL CHECK(max_context_tokens>0),
 UNIQUE(source,source_provider,source_model)
);
CREATE TABLE usage.priced_usage_events (
 id uuid PRIMARY KEY, usage_event_id uuid NOT NULL UNIQUE REFERENCES usage.usage_events(id) ON DELETE RESTRICT,
 organization_id uuid NOT NULL, pricing_rate_id uuid NOT NULL REFERENCES usage.model_pricing_rates(id) ON DELETE RESTRICT,
 pricing_mapping_id uuid NOT NULL REFERENCES usage.pricing_model_mappings(id) ON DELETE RESTRICT,
 provider varchar(64) NOT NULL, model varchar(200) NOT NULL, pricing_provider varchar(64) NOT NULL, pricing_model varchar(200) NOT NULL,
 pricing_tier varchar(64) NOT NULL, billing_basis varchar(64) NOT NULL, currency char(3) NOT NULL CHECK(currency='USD'),
 input_tokens bigint NOT NULL, cached_input_tokens bigint NOT NULL, output_tokens bigint NOT NULL,
 input_rate_snapshot numeric(18,9) NOT NULL, cached_input_rate_snapshot numeric(18,9) NOT NULL, output_rate_snapshot numeric(18,9) NOT NULL,
 effective_from_snapshot timestamptz NOT NULL, effective_until_snapshot timestamptz, source_url_snapshot varchar(2048) NOT NULL, verified_at_snapshot timestamptz NOT NULL,
 input_cost numeric(38,15) NOT NULL CHECK(input_cost>=0), cached_input_cost numeric(38,15) NOT NULL CHECK(cached_input_cost>=0),
 output_cost numeric(38,15) NOT NULL CHECK(output_cost>=0), total_cost numeric(38,15) NOT NULL CHECK(total_cost>=0),
 calculation_version integer NOT NULL CHECK(calculation_version=1), priced_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK(input_tokens>=0 AND output_tokens>=0 AND cached_input_tokens>=0 AND cached_input_tokens<=input_tokens),
 CHECK(input_cost+cached_input_cost+output_cost=total_cost),
 CHECK(input_rate_snapshot>=0 AND cached_input_rate_snapshot>=0 AND output_rate_snapshot>=0)
);
CREATE INDEX priced_usage_organization ON usage.priced_usage_events(organization_id,id);
CREATE TABLE usage.pricing_failures (
 usage_event_id uuid PRIMARY KEY REFERENCES usage.usage_events(id) ON DELETE RESTRICT,
 code varchar(64) NOT NULL, attempts integer NOT NULL DEFAULT 1, last_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE usage.delivery_outbox (
 id uuid PRIMARY KEY, priced_usage_event_id uuid NOT NULL UNIQUE REFERENCES usage.priced_usage_events(id) ON DELETE RESTRICT,
 payload jsonb NOT NULL, payload_fingerprint char(64) NOT NULL,
 status varchar(20) NOT NULL DEFAULT 'pending' CHECK(status IN('pending','delivering','retry','delivered','dead')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0), cycle_attempts integer NOT NULL DEFAULT 0 CHECK(cycle_attempts>=0),
 next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP, lease_token uuid, lease_until timestamptz,
 last_error_code varchar(64), last_http_status integer, acknowledged_transaction_id uuid, delivered_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CHECK((status='delivering')=(lease_token IS NOT NULL AND lease_until IS NOT NULL)),
 CHECK(status<>'delivered' OR (acknowledged_transaction_id IS NOT NULL AND delivered_at IS NOT NULL))
);
CREATE INDEX delivery_due ON usage.delivery_outbox(status,next_attempt_at);
CREATE TABLE usage.delivery_attempts (
 id uuid PRIMARY KEY, outbox_id uuid NOT NULL REFERENCES usage.delivery_outbox(id) ON DELETE RESTRICT,
 attempt_number integer NOT NULL, lease_token uuid NOT NULL UNIQUE, started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 completed_at timestamptz, outcome varchar(32) NOT NULL DEFAULT 'in_progress', error_code varchar(64), http_status integer,
 UNIQUE(outbox_id,attempt_number)
);
CREATE FUNCTION usage.reject_pricing_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Pricing history is immutable; use explicit financial corrections' USING ERRCODE='23514'; END $$;
CREATE TRIGGER rates_immutable BEFORE UPDATE OR DELETE ON usage.model_pricing_rates FOR EACH ROW EXECUTE FUNCTION usage.reject_pricing_mutation();
CREATE TRIGGER mappings_immutable BEFORE UPDATE OR DELETE ON usage.pricing_model_mappings FOR EACH ROW EXECUTE FUNCTION usage.reject_pricing_mutation();
CREATE TRIGGER priced_events_immutable BEFORE UPDATE OR DELETE ON usage.priced_usage_events FOR EACH ROW EXECUTE FUNCTION usage.reject_pricing_mutation();
CREATE FUNCTION usage.protect_outbox_payload() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR NEW.id<>OLD.id OR NEW.priced_usage_event_id<>OLD.priced_usage_event_id OR NEW.payload IS DISTINCT FROM OLD.payload OR NEW.payload_fingerprint<>OLD.payload_fingerprint OR NEW.created_at<>OLD.created_at
 THEN RAISE EXCEPTION 'Outbox financial payload is immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER outbox_payload_immutable BEFORE UPDATE OR DELETE ON usage.delivery_outbox FOR EACH ROW EXECUTE FUNCTION usage.protect_outbox_payload();
