SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: business; Type: SCHEMA; Schema: -; Owner: -
--

-- business schema is provisioned by Docker initialization.


--
-- Name: check_financial_operation(uuid); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.check_financial_operation(p uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE t business.financial_transactions; original business.financial_transactions; n integer; f numeric; e numeric;
BEGIN
  SELECT * INTO t FROM business.financial_transactions WHERE id=p;
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM id FROM business.budget_periods WHERE id IN(SELECT budget_period_id FROM business.ledger_entries WHERE financial_transaction_id=p) ORDER BY id FOR UPDATE;
  SELECT COUNT(*),COALESCE(SUM(funding_delta),0),COALESCE(SUM(expense_delta),0) INTO n,f,e FROM business.ledger_entries WHERE financial_transaction_id=p;
  IF EXISTS(SELECT 1 FROM business.ledger_entries l JOIN business.budget_periods b ON b.id=l.budget_period_id JOIN business.budget_accounts a ON a.id=b.budget_account_id
    WHERE l.financial_transaction_id=p AND (b.month_start<>t.month_start OR b.currency<>t.currency OR a.currency<>t.currency))
  THEN RAISE EXCEPTION 'Ledger currency and accounting month must match' USING ERRCODE='23514'; END IF;
  IF t.kind<>'usage_charge' AND NOT EXISTS(SELECT 1 FROM business.users u JOIN business.role_assignments r ON r.user_id=u.id AND r.organization_id=u.organization_id WHERE u.id=t.actor_id AND u.organization_id=t.organization_id AND u.status='active' AND r.role='financial_operator' AND r.scope_type='organization')
  THEN RAISE EXCEPTION 'Explicit financial authority is required' USING ERRCODE='23514'; END IF;
  IF t.kind='funding' THEN
    IF n<>1 OR f<>t.amount OR e<>0 OR NOT EXISTS(SELECT 1 FROM business.ledger_entries l JOIN business.budget_periods b ON b.id=l.budget_period_id JOIN business.budget_accounts a ON a.id=b.budget_account_id WHERE l.financial_transaction_id=p AND a.purpose='reserve')
    THEN RAISE EXCEPTION 'Initial funding must enter one organizational reserve' USING ERRCODE='23514'; END IF;
  ELSIF t.kind='transfer' THEN
    IF n<>2 OR f<>0 OR e<>0 OR (SELECT COUNT(DISTINCT budget_period_id) FROM business.ledger_entries WHERE financial_transaction_id=p)<>2
      OR NOT EXISTS(SELECT 1 FROM business.ledger_entries WHERE financial_transaction_id=p AND funding_delta=t.amount AND expense_delta=0)
      OR NOT EXISTS(SELECT 1 FROM business.ledger_entries WHERE financial_transaction_id=p AND funding_delta=-t.amount AND expense_delta=0)
    THEN RAISE EXCEPTION 'Transfers require equal opposite funding entries' USING ERRCODE='23514'; END IF;
    IF EXISTS(SELECT 1 FROM business.ledger_entries debit WHERE debit.financial_transaction_id=p AND debit.funding_delta<0 AND
      (SELECT COALESCE(SUM(funding_delta-expense_delta),0) FROM business.ledger_entries WHERE budget_period_id=debit.budget_period_id)<0)
    THEN RAISE EXCEPTION 'A transfer cannot overdraw its funding source' USING ERRCODE='23514'; END IF;
  ELSE
    IF n<>1 OR f<>0 OR e<>(CASE WHEN t.kind='reversal' THEN -t.amount ELSE t.amount END)
    THEN RAISE EXCEPTION 'Expense operations require one exact expense entry' USING ERRCODE='23514'; END IF;
    IF t.kind='usage_charge' THEN
      IF NOT EXISTS(SELECT 1 FROM business.priced_usage_receipts r WHERE r.id=t.priced_usage_receipt_id AND r.organization_id=t.organization_id AND r.usage_event_id=t.usage_event_id AND r.amount=t.amount AND r.financial_transaction_id=t.id AND r.status='posted') OR t.source_type<>'priced_usage_event' OR t.source_id<>t.priced_usage_receipt_id::text
      THEN RAISE EXCEPTION 'Usage charges require their matching idempotent receipt' USING ERRCODE='23514'; END IF;
    ELSE
      SELECT * INTO original FROM business.financial_transactions WHERE id=t.original_transaction_id AND organization_id=t.organization_id;
      IF NOT FOUND OR original.kind NOT IN ('usage_charge','adjustment') OR original.currency<>t.currency OR original.month_start<>t.month_start
        OR (SELECT budget_period_id FROM business.ledger_entries WHERE financial_transaction_id=p)<>(SELECT budget_period_id FROM business.ledger_entries WHERE financial_transaction_id=original.id)
      THEN RAISE EXCEPTION 'Corrections must retain the original expense account and month' USING ERRCODE='23514'; END IF;
      IF t.kind='reversal' AND t.amount<>original.amount THEN RAISE EXCEPTION 'A reversal must exactly offset its origin' USING ERRCODE='23514'; END IF;
      IF t.kind='adjustment' AND (t.correction_group_id IS NULL OR NOT EXISTS(SELECT 1 FROM business.financial_transactions r WHERE r.kind='reversal' AND r.original_transaction_id=original.id AND r.correction_group_id=t.correction_group_id AND r.write_transaction_id=t.write_transaction_id))
      THEN RAISE EXCEPTION 'Replacement requires an atomic paired reversal' USING ERRCODE='23514'; END IF;
      IF t.kind='reversal' AND t.correction_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM business.financial_transactions a WHERE a.kind='adjustment' AND a.original_transaction_id=original.id AND a.correction_group_id=t.correction_group_id AND a.write_transaction_id=t.write_transaction_id)
      THEN RAISE EXCEPTION 'Correction reversal requires its paired replacement' USING ERRCODE='23514'; END IF;
    END IF;
  END IF;
END $$;


--
-- Name: check_project_administration(uuid); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.check_project_administration(p uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p IS NULL THEN RETURN; END IF;
  PERFORM id FROM business.projects WHERE id = p FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM business.role_assignments r
    JOIN business.users u ON u.id = r.user_id AND u.status = 'active'
    JOIN business.project_memberships m ON m.project_id = r.project_id AND m.user_id = r.user_id AND m.left_at IS NULL
    WHERE r.project_id = p AND r.role = 'project_lead'
  ) THEN RAISE EXCEPTION 'A project requires an active authorized administrator' USING ERRCODE = '23514'; END IF;
  IF EXISTS (
    SELECT 1 FROM business.role_assignments r JOIN business.users u ON u.id = r.user_id
    WHERE r.project_id = p AND r.role = 'project_lead' AND (
      u.status <> 'active' OR NOT EXISTS (
        SELECT 1 FROM business.project_memberships m WHERE m.project_id = p AND m.user_id = r.user_id AND m.left_at IS NULL
      )
    )
  ) THEN RAISE EXCEPTION 'Project authority requires active participation' USING ERRCODE = '23514'; END IF;
END $$;


--
-- Name: check_reporting_cycle(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.check_reporting_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.organization_id::text, 0));
  IF EXISTS (
    WITH RECURSIVE ancestors(id) AS (
      SELECT NEW.manager_id
      UNION
      SELECT r.manager_id FROM business.reporting_relationships r JOIN ancestors a ON r.report_id = a.id
        WHERE r.organization_id = NEW.organization_id AND r.id <> NEW.id
    ) SELECT 1 FROM ancestors WHERE id = NEW.report_id
  ) THEN RAISE EXCEPTION 'Reporting relationship cycle' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;


--
-- Name: check_unit_cycle(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.check_unit_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.organization_id::text, 0));
  IF EXISTS (
    WITH RECURSIVE ancestors(id, parent_unit_id) AS (
      SELECT id, parent_unit_id FROM business.organizational_units
        WHERE id = NEW.parent_unit_id AND organization_id = NEW.organization_id
      UNION
      SELECT u.id, u.parent_unit_id FROM business.organizational_units u
        JOIN ancestors a ON u.id = a.parent_unit_id WHERE u.organization_id = NEW.organization_id
    ) SELECT 1 FROM ancestors WHERE id = NEW.id
  ) THEN RAISE EXCEPTION 'Organizational unit cycle' USING ERRCODE = '23514'; END IF;
  RETURN NEW;
END $$;


--
-- Name: financial_append_only(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.financial_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN RAISE EXCEPTION 'Financial history is append-only' USING ERRCODE='23514'; END $$;


--
-- Name: guard_financial_entry(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.guard_financial_entry() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM business.financial_transactions t WHERE t.id=NEW.financial_transaction_id AND t.organization_id=NEW.organization_id AND t.write_transaction_id=txid_current())
  THEN RAISE EXCEPTION 'Entries must be created with their immutable transaction' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;


--
-- Name: protect_budget_identity(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.protect_budget_identity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_TABLE_NAME='budget_accounts' THEN
    IF NEW.organization_id<>OLD.organization_id OR NEW.purpose<>OLD.purpose OR NEW.organizational_unit_id IS DISTINCT FROM OLD.organizational_unit_id OR NEW.project_id IS DISTINCT FROM OLD.project_id OR NEW.currency<>OLD.currency OR NEW.effective_from<>OLD.effective_from
    THEN RAISE EXCEPTION 'Historical budget ownership is immutable' USING ERRCODE='23514'; END IF;
  ELSE
    IF NEW.organization_id<>OLD.organization_id OR NEW.budget_account_id<>OLD.budget_account_id OR NEW.month_start<>OLD.month_start OR NEW.currency<>OLD.currency
    THEN RAISE EXCEPTION 'Accounting period identity is immutable' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: protect_priced_receipt(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.protect_priced_receipt() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP='DELETE' OR NEW.id<>OLD.id OR NEW.organization_id<>OLD.organization_id OR NEW.usage_event_id<>OLD.usage_event_id OR NEW.user_id<>OLD.user_id OR NEW.project_id IS DISTINCT FROM OLD.project_id OR NEW.amount<>OLD.amount OR NEW.currency<>OLD.currency OR NEW.occurred_at<>OLD.occurred_at OR NEW.payload IS DISTINCT FROM OLD.payload OR NEW.payload_fingerprint<>OLD.payload_fingerprint OR NEW.created_at<>OLD.created_at OR (OLD.status='posted' AND (NEW.status<>'posted' OR NEW.financial_transaction_id IS DISTINCT FROM OLD.financial_transaction_id))
  THEN RAISE EXCEPTION 'Receipt source and posted effect are immutable' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;


--
-- Name: validate_financial_operation(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.validate_financial_operation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_TABLE_NAME='financial_transactions' THEN PERFORM business.check_financial_operation(NEW.id);
  ELSE PERFORM business.check_financial_operation(NEW.financial_transaction_id); END IF;
  RETURN NULL;
END $$;


--
-- Name: validate_financial_source(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.validate_financial_source() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.kind='usage_charge' AND NOT EXISTS(SELECT 1 FROM business.priced_usage_receipts r WHERE r.id=NEW.priced_usage_receipt_id AND r.user_id=NEW.user_id AND r.project_id IS NOT DISTINCT FROM NEW.project_id AND NEW.actor_id IS NULL AND NEW.month_start=date_trunc('month',r.occurred_at AT TIME ZONE 'UTC')::date)
  THEN RAISE EXCEPTION 'Financial dimensions and UTC month must match the receipt' USING ERRCODE='23514'; END IF;
  IF NEW.kind IN ('reversal','adjustment') AND NOT EXISTS(SELECT 1 FROM business.financial_transactions o WHERE o.id=NEW.original_transaction_id AND o.user_id IS NOT DISTINCT FROM NEW.user_id AND o.project_id IS NOT DISTINCT FROM NEW.project_id AND o.home_unit_id IS NOT DISTINCT FROM NEW.home_unit_id)
  THEN RAISE EXCEPTION 'Corrections must preserve original attribution' USING ERRCODE='23514'; END IF;
  RETURN NULL;
END $$;


--
-- Name: validate_project_administration(); Type: FUNCTION; Schema: business; Owner: -
--

CREATE FUNCTION business.validate_project_administration() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_TABLE_NAME = 'projects' THEN
    IF TG_OP <> 'DELETE' THEN PERFORM business.check_project_administration(NEW.id); END IF;
  ELSIF TG_TABLE_NAME = 'users' THEN
    PERFORM business.check_project_administration(r.project_id) FROM business.role_assignments r
      WHERE r.user_id = NEW.id AND r.role = 'project_lead';
  ELSE
    IF TG_OP <> 'INSERT' THEN PERFORM business.check_project_administration(OLD.project_id); END IF;
    IF TG_OP <> 'DELETE' THEN PERFORM business.check_project_administration(NEW.project_id); END IF;
  END IF;
  RETURN NULL;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: budget_accounts; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.budget_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying(120) NOT NULL,
    purpose character varying NOT NULL,
    organizational_unit_id uuid,
    project_id uuid,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    effective_from timestamp(6) without time zone NOT NULL,
    effective_until timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT explicit_budget_owner CHECK (((((purpose)::text = ANY ((ARRAY['reserve'::character varying, 'unassigned'::character varying])::text[])) AND (organizational_unit_id IS NULL) AND (project_id IS NULL)) OR (((purpose)::text = 'unit'::text) AND (organizational_unit_id IS NOT NULL) AND (project_id IS NULL)) OR (((purpose)::text = 'project'::text) AND (project_id IS NOT NULL) AND (organizational_unit_id IS NULL)))),
    CONSTRAINT valid_budget_account_state CHECK ((((currency)::text = 'USD'::text) AND ((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])) AND ((effective_until IS NULL) OR (effective_until > effective_from))))
);


--
-- Name: budget_periods; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.budget_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    budget_account_id uuid NOT NULL,
    month_start date NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT valid_utc_budget_month CHECK ((((currency)::text = 'USD'::text) AND ((status)::text = ANY ((ARRAY['open'::character varying, 'closed'::character varying])::text[])) AND (EXTRACT(day FROM month_start) = (1)::numeric)))
);


--
-- Name: demo_sessions; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.demo_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_digest character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: financial_transactions; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.financial_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    kind character varying NOT NULL,
    currency character varying DEFAULT 'USD'::character varying NOT NULL,
    month_start date NOT NULL,
    amount numeric(38,15) NOT NULL,
    source_type character varying(64) NOT NULL,
    source_id character varying(128) NOT NULL,
    request_fingerprint character varying(64) NOT NULL,
    actor_id uuid,
    priced_usage_receipt_id uuid,
    usage_event_id uuid,
    user_id uuid,
    project_id uuid,
    home_unit_id uuid,
    original_transaction_id uuid,
    correction_group_id uuid,
    reason character varying(500) NOT NULL,
    audit_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    write_transaction_id bigint DEFAULT txid_current() NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT explicit_correction_origin CHECK (((((kind)::text = ANY ((ARRAY['reversal'::character varying, 'adjustment'::character varying])::text[])) = (original_transaction_id IS NOT NULL)) AND ((correction_group_id IS NULL) OR ((kind)::text = ANY ((ARRAY['reversal'::character varying, 'adjustment'::character varying])::text[]))))),
    CONSTRAINT finite_financial_amount CHECK ((amount < 'Infinity'::numeric)),
    CONSTRAINT valid_financial_operation CHECK ((((currency)::text = 'USD'::text) AND (amount >= (0)::numeric) AND (((kind)::text <> ALL ((ARRAY['funding'::character varying, 'transfer'::character varying])::text[])) OR (amount > (0)::numeric)) AND ((kind)::text = ANY ((ARRAY['funding'::character varying, 'transfer'::character varying, 'usage_charge'::character varying, 'reversal'::character varying, 'adjustment'::character varying])::text[])) AND (EXTRACT(day FROM month_start) = (1)::numeric) AND ((length((reason)::text) >= 1) AND (length((reason)::text) <= 500)) AND ((original_transaction_id IS NULL) OR (original_transaction_id <> id))))
);


--
-- Name: ledger_entries; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.ledger_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    financial_transaction_id uuid NOT NULL,
    budget_period_id uuid NOT NULL,
    funding_delta numeric(38,15) DEFAULT 0.0 NOT NULL,
    expense_delta numeric(38,15) DEFAULT 0.0 NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT finite_ledger_deltas CHECK (((funding_delta > '-Infinity'::numeric) AND (funding_delta < 'Infinity'::numeric) AND (expense_delta > '-Infinity'::numeric) AND (expense_delta < 'Infinity'::numeric)))
);


--
-- Name: organizational_memberships; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.organizational_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    organizational_unit_id uuid NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    membership_type character varying DEFAULT 'member'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: organizational_units; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.organizational_units (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    parent_unit_id uuid,
    name character varying NOT NULL,
    unit_type character varying NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT unit_not_own_parent CHECK (((parent_unit_id IS NULL) OR (parent_unit_id <> id)))
);


--
-- Name: organizations; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    description text,
    demo boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: priced_usage_receipts; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.priced_usage_receipts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    usage_event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    project_id uuid,
    occurred_at timestamp(6) without time zone NOT NULL,
    amount numeric(38,15) NOT NULL,
    currency character varying NOT NULL,
    payload jsonb NOT NULL,
    payload_fingerprint character varying(64) NOT NULL,
    status character varying DEFAULT 'unresolved'::character varying NOT NULL,
    resolution_code character varying,
    financial_transaction_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT finite_receipt_amount CHECK ((amount < 'Infinity'::numeric)),
    CONSTRAINT valid_priced_receipt CHECK (((amount >= (0)::numeric) AND ((currency)::text = 'USD'::text) AND ((status)::text = ANY ((ARRAY['posted'::character varying, 'unresolved'::character varying])::text[])) AND (((status)::text = 'posted'::text) = (financial_transaction_id IS NOT NULL)) AND (jsonb_typeof((payload -> 'amount'::text)) = 'string'::text) AND (((payload ->> 'amount'::text))::numeric = amount)))
);


--
-- Name: project_memberships; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.project_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    project_id uuid NOT NULL,
    user_id uuid NOT NULL,
    project_role character varying DEFAULT 'contributor'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    joined_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    left_at timestamp(6) without time zone,
    CONSTRAINT valid_membership_period CHECK (((left_at IS NULL) OR (left_at >= joined_at))),
    CONSTRAINT valid_project_role CHECK (((project_role)::text = ANY (ARRAY[('owner'::character varying)::text, ('lead'::character varying)::text, ('contributor'::character varying)::text, ('reviewer'::character varying)::text])))
);


--
-- Name: projects; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    description text,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    created_by_id uuid,
    archived_from_status character varying,
    CONSTRAINT valid_project_restore_status CHECK (((archived_from_status IS NULL) OR ((archived_from_status)::text = ANY ((ARRAY['planned'::character varying, 'active'::character varying])::text[])))),
    CONSTRAINT valid_project_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('planned'::character varying)::text, ('archived'::character varying)::text])))
);


--
-- Name: reporting_relationships; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.reporting_relationships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    manager_id uuid NOT NULL,
    report_id uuid NOT NULL,
    relationship_type character varying DEFAULT 'line_manager'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT no_self_reporting CHECK ((manager_id <> report_id)),
    CONSTRAINT valid_reporting_type CHECK (((relationship_type)::text = ANY (ARRAY[('line_manager'::character varying)::text, ('dotted_line'::character varying)::text])))
);


--
-- Name: role_assignments; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.role_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying NOT NULL,
    scope_type character varying NOT NULL,
    organizational_unit_id uuid,
    project_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT valid_role_and_explicit_scope CHECK (((((role)::text = 'employee'::text) AND ((scope_type)::text = 'self'::text) AND (organizational_unit_id IS NULL) AND (project_id IS NULL)) OR (((role)::text = ANY ((ARRAY['organization_viewer'::character varying, 'project_creator'::character varying, 'financial_operator'::character varying])::text[])) AND ((scope_type)::text = 'organization'::text) AND (organizational_unit_id IS NULL) AND (project_id IS NULL)) OR (((role)::text = 'team_manager'::text) AND ((scope_type)::text = 'unit'::text) AND (organizational_unit_id IS NOT NULL) AND (project_id IS NULL)) OR (((role)::text = 'project_lead'::text) AND ((scope_type)::text = 'project'::text) AND (project_id IS NOT NULL) AND (organizational_unit_id IS NULL))))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: business; Owner: -
--

CREATE TABLE business.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    email character varying NOT NULL,
    job_title character varying NOT NULL,
    job_function character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    demo_identity boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT valid_user_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text])))
);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: budget_accounts budget_accounts_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.budget_accounts
    ADD CONSTRAINT budget_accounts_pkey PRIMARY KEY (id);


--
-- Name: budget_periods budget_periods_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.budget_periods
    ADD CONSTRAINT budget_periods_pkey PRIMARY KEY (id);


--
-- Name: demo_sessions demo_sessions_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.demo_sessions
    ADD CONSTRAINT demo_sessions_pkey PRIMARY KEY (id);


--
-- Name: financial_transactions financial_transactions_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT financial_transactions_pkey PRIMARY KEY (id);


--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: organizational_memberships organizational_memberships_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_memberships
    ADD CONSTRAINT organizational_memberships_pkey PRIMARY KEY (id);


--
-- Name: organizational_units organizational_units_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_units
    ADD CONSTRAINT organizational_units_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: priced_usage_receipts priced_usage_receipts_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.priced_usage_receipts
    ADD CONSTRAINT priced_usage_receipts_pkey PRIMARY KEY (id);


--
-- Name: project_memberships project_memberships_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.project_memberships
    ADD CONSTRAINT project_memberships_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: reporting_relationships reporting_relationships_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.reporting_relationships
    ADD CONSTRAINT reporting_relationships_pkey PRIMARY KEY (id);


--
-- Name: role_assignments role_assignments_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.role_assignments
    ADD CONSTRAINT role_assignments_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_organization_id_manager_id_b1a56d25f0; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX idx_on_organization_id_manager_id_b1a56d25f0 ON business.reporting_relationships USING btree (organization_id, manager_id);


--
-- Name: idx_on_organization_id_organizational_unit_id_ebf7869ace; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX idx_on_organization_id_organizational_unit_id_ebf7869ace ON business.organizational_memberships USING btree (organization_id, organizational_unit_id);


--
-- Name: idx_on_organization_id_parent_unit_id_3f231201a8; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX idx_on_organization_id_parent_unit_id_3f231201a8 ON business.organizational_units USING btree (organization_id, parent_unit_id);


--
-- Name: idx_on_organization_id_project_id_left_at_65363c72a7; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX idx_on_organization_id_project_id_left_at_65363c72a7 ON business.project_memberships USING btree (organization_id, project_id, left_at);


--
-- Name: idx_on_report_id_relationship_type_79f0209472; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX idx_on_report_id_relationship_type_79f0209472 ON business.reporting_relationships USING btree (report_id, relationship_type);


--
-- Name: index_budget_accounts_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_budget_accounts_on_organization_id_and_id ON business.budget_accounts USING btree (organization_id, id);


--
-- Name: index_budget_periods_on_budget_account_id_and_month_start; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_budget_periods_on_budget_account_id_and_month_start ON business.budget_periods USING btree (budget_account_id, month_start);


--
-- Name: index_budget_periods_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_budget_periods_on_organization_id_and_id ON business.budget_periods USING btree (organization_id, id);


--
-- Name: index_demo_sessions_on_expires_at; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_demo_sessions_on_expires_at ON business.demo_sessions USING btree (expires_at);


--
-- Name: index_demo_sessions_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_demo_sessions_on_organization_id ON business.demo_sessions USING btree (organization_id);


--
-- Name: index_demo_sessions_on_token_digest; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_demo_sessions_on_token_digest ON business.demo_sessions USING btree (token_digest);


--
-- Name: index_financial_transactions_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_financial_transactions_on_organization_id_and_id ON business.financial_transactions USING btree (organization_id, id);


--
-- Name: index_financial_transactions_on_original_transaction_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_financial_transactions_on_original_transaction_id ON business.financial_transactions USING btree (original_transaction_id);


--
-- Name: index_ledger_entries_on_budget_period_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_ledger_entries_on_budget_period_id ON business.ledger_entries USING btree (budget_period_id);


--
-- Name: index_ledger_entries_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_ledger_entries_on_organization_id_and_id ON business.ledger_entries USING btree (organization_id, id);


--
-- Name: index_organizational_memberships_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_organizational_memberships_on_organization_id ON business.organizational_memberships USING btree (organization_id);


--
-- Name: index_organizational_units_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_organizational_units_on_organization_id ON business.organizational_units USING btree (organization_id);


--
-- Name: index_organizational_units_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_organizational_units_on_organization_id_and_id ON business.organizational_units USING btree (organization_id, id);


--
-- Name: index_organizational_units_on_organization_id_and_name; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_organizational_units_on_organization_id_and_name ON business.organizational_units USING btree (organization_id, name);


--
-- Name: index_organizations_on_slug; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_slug ON business.organizations USING btree (slug);


--
-- Name: index_priced_usage_receipts_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_priced_usage_receipts_on_organization_id_and_id ON business.priced_usage_receipts USING btree (organization_id, id);


--
-- Name: index_priced_usage_receipts_on_status; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_priced_usage_receipts_on_status ON business.priced_usage_receipts USING btree (status);


--
-- Name: index_priced_usage_receipts_on_usage_event_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_priced_usage_receipts_on_usage_event_id ON business.priced_usage_receipts USING btree (usage_event_id);


--
-- Name: index_project_memberships_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_project_memberships_on_organization_id ON business.project_memberships USING btree (organization_id);


--
-- Name: index_project_memberships_on_organization_id_and_user_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_project_memberships_on_organization_id_and_user_id ON business.project_memberships USING btree (organization_id, user_id);


--
-- Name: index_projects_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_projects_on_organization_id ON business.projects USING btree (organization_id);


--
-- Name: index_projects_on_organization_id_and_created_by_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_projects_on_organization_id_and_created_by_id ON business.projects USING btree (organization_id, created_by_id);


--
-- Name: index_projects_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_organization_id_and_id ON business.projects USING btree (organization_id, id);


--
-- Name: index_projects_on_organization_id_and_slug; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_projects_on_organization_id_and_slug ON business.projects USING btree (organization_id, slug);


--
-- Name: index_projects_on_organization_id_and_status; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_projects_on_organization_id_and_status ON business.projects USING btree (organization_id, status);


--
-- Name: index_reporting_relationships_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_reporting_relationships_on_organization_id ON business.reporting_relationships USING btree (organization_id);


--
-- Name: index_role_assignments_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_role_assignments_on_organization_id ON business.role_assignments USING btree (organization_id);


--
-- Name: index_role_assignments_on_organization_id_and_user_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_role_assignments_on_organization_id_and_user_id ON business.role_assignments USING btree (organization_id, user_id);


--
-- Name: index_users_on_organization_id; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_users_on_organization_id ON business.users USING btree (organization_id);


--
-- Name: index_users_on_organization_id_and_email; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_users_on_organization_id_and_email ON business.users USING btree (organization_id, email);


--
-- Name: index_users_on_organization_id_and_id; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX index_users_on_organization_id_and_id ON business.users USING btree (organization_id, id);


--
-- Name: index_users_on_organization_id_and_name; Type: INDEX; Schema: business; Owner: -
--

CREATE INDEX index_users_on_organization_id_and_name ON business.users USING btree (organization_id, name);


--
-- Name: one_operation_per_correction_side; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX one_operation_per_correction_side ON business.financial_transactions USING btree (correction_group_id, kind) WHERE (correction_group_id IS NOT NULL);


--
-- Name: one_original_expense_per_usage; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX one_original_expense_per_usage ON business.financial_transactions USING btree (usage_event_id) WHERE ((kind)::text = 'usage_charge'::text);


--
-- Name: one_primary_home_team; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX one_primary_home_team ON business.organizational_memberships USING btree (user_id) WHERE is_primary;


--
-- Name: one_reversal_per_operation; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX one_reversal_per_operation ON business.financial_transactions USING btree (original_transaction_id) WHERE ((kind)::text = 'reversal'::text);


--
-- Name: unique_active_project_membership; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_active_project_membership ON business.project_memberships USING btree (project_id, user_id) WHERE (left_at IS NULL);


--
-- Name: unique_financial_source; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_financial_source ON business.financial_transactions USING btree (organization_id, source_type, source_id);


--
-- Name: unique_organization_budget_purpose; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_organization_budget_purpose ON business.budget_accounts USING btree (organization_id, currency, purpose) WHERE ((purpose)::text = ANY ((ARRAY['reserve'::character varying, 'unassigned'::character varying])::text[]));


--
-- Name: unique_project_budget_account; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_project_budget_account ON business.budget_accounts USING btree (organization_id, project_id, currency) WHERE ((purpose)::text = 'project'::text);


--
-- Name: unique_scoped_role; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_scoped_role ON business.role_assignments USING btree (user_id, role, scope_type, organizational_unit_id, project_id) NULLS NOT DISTINCT;


--
-- Name: unique_unit_budget_account; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_unit_budget_account ON business.budget_accounts USING btree (organization_id, organizational_unit_id, currency) WHERE ((purpose)::text = 'unit'::text);


--
-- Name: unique_unit_membership; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_unit_membership ON business.organizational_memberships USING btree (user_id, organizational_unit_id);


--
-- Name: budget_accounts budget_account_identity; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER budget_account_identity BEFORE UPDATE ON business.budget_accounts FOR EACH ROW EXECUTE FUNCTION business.protect_budget_identity();


--
-- Name: budget_periods budget_period_identity; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER budget_period_identity BEFORE UPDATE ON business.budget_periods FOR EACH ROW EXECUTE FUNCTION business.protect_budget_identity();


--
-- Name: ledger_entries financial_entry_creation; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER financial_entry_creation BEFORE INSERT ON business.ledger_entries FOR EACH ROW EXECUTE FUNCTION business.guard_financial_entry();


--
-- Name: financial_transactions financial_source_integrity; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER financial_source_integrity AFTER INSERT ON business.financial_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_financial_source();


--
-- Name: financial_transactions financial_transaction_integrity; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER financial_transaction_integrity AFTER INSERT ON business.financial_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_financial_operation();


--
-- Name: financial_transactions financial_transactions_append_only; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER financial_transactions_append_only BEFORE DELETE OR UPDATE ON business.financial_transactions FOR EACH ROW EXECUTE FUNCTION business.financial_append_only();


--
-- Name: financial_transactions financial_transactions_no_truncate; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER financial_transactions_no_truncate BEFORE TRUNCATE ON business.financial_transactions FOR EACH STATEMENT EXECUTE FUNCTION business.financial_append_only();


--
-- Name: ledger_entries ledger_entries_append_only; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER ledger_entries_append_only BEFORE DELETE OR UPDATE ON business.ledger_entries FOR EACH ROW EXECUTE FUNCTION business.financial_append_only();


--
-- Name: ledger_entries ledger_entries_no_truncate; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER ledger_entries_no_truncate BEFORE TRUNCATE ON business.ledger_entries FOR EACH STATEMENT EXECUTE FUNCTION business.financial_append_only();


--
-- Name: ledger_entries ledger_entry_integrity; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_entry_integrity AFTER INSERT ON business.ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_financial_operation();


--
-- Name: reporting_relationships prevent_reporting_cycle; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER prevent_reporting_cycle BEFORE INSERT OR UPDATE ON business.reporting_relationships FOR EACH ROW EXECUTE FUNCTION business.check_reporting_cycle();


--
-- Name: organizational_units prevent_unit_cycle; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER prevent_unit_cycle BEFORE INSERT OR UPDATE ON business.organizational_units FOR EACH ROW EXECUTE FUNCTION business.check_unit_cycle();


--
-- Name: project_memberships project_memberships_administration_guard; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER project_memberships_administration_guard AFTER INSERT OR DELETE OR UPDATE ON business.project_memberships DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_project_administration();


--
-- Name: projects projects_administration_guard; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER projects_administration_guard AFTER INSERT OR DELETE OR UPDATE ON business.projects DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_project_administration();


--
-- Name: priced_usage_receipts receipt_source_immutable; Type: TRIGGER; Schema: business; Owner: -
--

CREATE TRIGGER receipt_source_immutable BEFORE DELETE OR UPDATE ON business.priced_usage_receipts FOR EACH ROW EXECUTE FUNCTION business.protect_priced_receipt();


--
-- Name: role_assignments role_assignments_administration_guard; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER role_assignments_administration_guard AFTER INSERT OR DELETE OR UPDATE ON business.role_assignments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_project_administration();


--
-- Name: users users_administration_guard; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER users_administration_guard AFTER UPDATE ON business.users DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((old.status)::text IS DISTINCT FROM (new.status)::text)) EXECUTE FUNCTION business.validate_project_administration();


--
-- Name: budget_periods fk_rails_013a1cf3ac; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.budget_periods
    ADD CONSTRAINT fk_rails_013a1cf3ac FOREIGN KEY (organization_id, budget_account_id) REFERENCES business.budget_accounts(organization_id, id);


--
-- Name: ledger_entries fk_rails_06c4de55f1; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.ledger_entries
    ADD CONSTRAINT fk_rails_06c4de55f1 FOREIGN KEY (organization_id, financial_transaction_id) REFERENCES business.financial_transactions(organization_id, id);


--
-- Name: role_assignments fk_rails_0f09f7eaf9; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.role_assignments
    ADD CONSTRAINT fk_rails_0f09f7eaf9 FOREIGN KEY (organization_id, user_id) REFERENCES business.users(organization_id, id);


--
-- Name: budget_accounts fk_rails_14ce76a516; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.budget_accounts
    ADD CONSTRAINT fk_rails_14ce76a516 FOREIGN KEY (organization_id, organizational_unit_id) REFERENCES business.organizational_units(organization_id, id);


--
-- Name: organizational_units fk_rails_1edc901ddd; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_units
    ADD CONSTRAINT fk_rails_1edc901ddd FOREIGN KEY (organization_id, parent_unit_id) REFERENCES business.organizational_units(organization_id, id);


--
-- Name: priced_usage_receipts fk_rails_20b83b8a7f; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.priced_usage_receipts
    ADD CONSTRAINT fk_rails_20b83b8a7f FOREIGN KEY (organization_id, project_id) REFERENCES business.projects(organization_id, id);


--
-- Name: organizational_memberships fk_rails_223f0aaca2; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_memberships
    ADD CONSTRAINT fk_rails_223f0aaca2 FOREIGN KEY (organization_id, user_id) REFERENCES business.users(organization_id, id);


--
-- Name: demo_sessions fk_rails_2438643fda; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.demo_sessions
    ADD CONSTRAINT fk_rails_2438643fda FOREIGN KEY (organization_id, user_id) REFERENCES business.users(organization_id, id);


--
-- Name: organizational_units fk_rails_26a2e4370e; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_units
    ADD CONSTRAINT fk_rails_26a2e4370e FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: financial_transactions fk_rails_2c97e36896; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT fk_rails_2c97e36896 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: project_memberships fk_rails_329479fb2c; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.project_memberships
    ADD CONSTRAINT fk_rails_329479fb2c FOREIGN KEY (organization_id, project_id) REFERENCES business.projects(organization_id, id);


--
-- Name: budget_accounts fk_rails_363b2b3848; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.budget_accounts
    ADD CONSTRAINT fk_rails_363b2b3848 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: projects fk_rails_53626d53e6; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.projects
    ADD CONSTRAINT fk_rails_53626d53e6 FOREIGN KEY (organization_id, created_by_id) REFERENCES business.users(organization_id, id);


--
-- Name: reporting_relationships fk_rails_588165b05e; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.reporting_relationships
    ADD CONSTRAINT fk_rails_588165b05e FOREIGN KEY (organization_id, manager_id) REFERENCES business.users(organization_id, id);


--
-- Name: ledger_entries fk_rails_5e43ced659; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.ledger_entries
    ADD CONSTRAINT fk_rails_5e43ced659 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: financial_transactions fk_rails_621b50d147; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT fk_rails_621b50d147 FOREIGN KEY (organization_id, original_transaction_id) REFERENCES business.financial_transactions(organization_id, id);


--
-- Name: organizational_memberships fk_rails_68eac7feb9; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_memberships
    ADD CONSTRAINT fk_rails_68eac7feb9 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: financial_transactions fk_rails_88cde441c7; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT fk_rails_88cde441c7 FOREIGN KEY (organization_id, project_id) REFERENCES business.projects(organization_id, id);


--
-- Name: financial_transactions fk_rails_94e70b9d2f; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT fk_rails_94e70b9d2f FOREIGN KEY (organization_id, home_unit_id) REFERENCES business.organizational_units(organization_id, id);


--
-- Name: financial_transactions fk_rails_9731b4b759; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT fk_rails_9731b4b759 FOREIGN KEY (organization_id, user_id) REFERENCES business.users(organization_id, id);


--
-- Name: projects fk_rails_9aee26923d; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.projects
    ADD CONSTRAINT fk_rails_9aee26923d FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: priced_usage_receipts fk_rails_a028ca7c71; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.priced_usage_receipts
    ADD CONSTRAINT fk_rails_a028ca7c71 FOREIGN KEY (organization_id, financial_transaction_id) REFERENCES business.financial_transactions(organization_id, id);


--
-- Name: financial_transactions fk_rails_a058bd92a1; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT fk_rails_a058bd92a1 FOREIGN KEY (organization_id, priced_usage_receipt_id) REFERENCES business.priced_usage_receipts(organization_id, id);


--
-- Name: priced_usage_receipts fk_rails_b6b00082fe; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.priced_usage_receipts
    ADD CONSTRAINT fk_rails_b6b00082fe FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: organizational_memberships fk_rails_c4505bc98f; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_memberships
    ADD CONSTRAINT fk_rails_c4505bc98f FOREIGN KEY (organization_id, organizational_unit_id) REFERENCES business.organizational_units(organization_id, id);


--
-- Name: ledger_entries fk_rails_c55922a0b9; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.ledger_entries
    ADD CONSTRAINT fk_rails_c55922a0b9 FOREIGN KEY (organization_id, budget_period_id) REFERENCES business.budget_periods(organization_id, id);


--
-- Name: budget_accounts fk_rails_c85f383985; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.budget_accounts
    ADD CONSTRAINT fk_rails_c85f383985 FOREIGN KEY (organization_id, project_id) REFERENCES business.projects(organization_id, id);


--
-- Name: role_assignments fk_rails_caa781d59a; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.role_assignments
    ADD CONSTRAINT fk_rails_caa781d59a FOREIGN KEY (organization_id, project_id) REFERENCES business.projects(organization_id, id);


--
-- Name: reporting_relationships fk_rails_ce85be66e7; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.reporting_relationships
    ADD CONSTRAINT fk_rails_ce85be66e7 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: project_memberships fk_rails_cf38ba24b5; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.project_memberships
    ADD CONSTRAINT fk_rails_cf38ba24b5 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: role_assignments fk_rails_d5d049f535; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.role_assignments
    ADD CONSTRAINT fk_rails_d5d049f535 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: users fk_rails_d7b9ff90af; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.users
    ADD CONSTRAINT fk_rails_d7b9ff90af FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: project_memberships fk_rails_e03d0485bf; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.project_memberships
    ADD CONSTRAINT fk_rails_e03d0485bf FOREIGN KEY (organization_id, user_id) REFERENCES business.users(organization_id, id);


--
-- Name: role_assignments fk_rails_f6f675626a; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.role_assignments
    ADD CONSTRAINT fk_rails_f6f675626a FOREIGN KEY (organization_id, organizational_unit_id) REFERENCES business.organizational_units(organization_id, id);


--
-- Name: demo_sessions fk_rails_f731f7f0e4; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.demo_sessions
    ADD CONSTRAINT fk_rails_f731f7f0e4 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: priced_usage_receipts fk_rails_f85bee2b24; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.priced_usage_receipts
    ADD CONSTRAINT fk_rails_f85bee2b24 FOREIGN KEY (organization_id, user_id) REFERENCES business.users(organization_id, id);


--
-- Name: reporting_relationships fk_rails_f8f78d2a18; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.reporting_relationships
    ADD CONSTRAINT fk_rails_f8f78d2a18 FOREIGN KEY (organization_id, report_id) REFERENCES business.users(organization_id, id);


--
-- Name: financial_transactions fk_rails_fab990c62a; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.financial_transactions
    ADD CONSTRAINT fk_rails_fab990c62a FOREIGN KEY (organization_id, actor_id) REFERENCES business.users(organization_id, id);


--
-- Name: budget_periods fk_rails_fbde5a014c; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.budget_periods
    ADD CONSTRAINT fk_rails_fbde5a014c FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO business;

INSERT INTO "schema_migrations" (version) VALUES
('20261109000300'),
('20261109000200'),
('20261109000100'),
('20261107000100');

