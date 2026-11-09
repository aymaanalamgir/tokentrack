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
    CONSTRAINT valid_role_and_explicit_scope CHECK (((((role)::text = 'employee'::text) AND ((scope_type)::text = 'self'::text) AND (organizational_unit_id IS NULL) AND (project_id IS NULL)) OR (((role)::text = ANY ((ARRAY['organization_viewer'::character varying, 'project_creator'::character varying])::text[])) AND ((scope_type)::text = 'organization'::text) AND (organizational_unit_id IS NULL) AND (project_id IS NULL)) OR (((role)::text = 'team_manager'::text) AND ((scope_type)::text = 'unit'::text) AND (organizational_unit_id IS NOT NULL) AND (project_id IS NULL)) OR (((role)::text = 'project_lead'::text) AND ((scope_type)::text = 'project'::text) AND (project_id IS NOT NULL) AND (organizational_unit_id IS NULL))))
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
-- Name: demo_sessions demo_sessions_pkey; Type: CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.demo_sessions
    ADD CONSTRAINT demo_sessions_pkey PRIMARY KEY (id);


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
-- Name: one_primary_home_team; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX one_primary_home_team ON business.organizational_memberships USING btree (user_id) WHERE is_primary;


--
-- Name: unique_active_project_membership; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_active_project_membership ON business.project_memberships USING btree (project_id, user_id) WHERE (left_at IS NULL);


--
-- Name: unique_scoped_role; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_scoped_role ON business.role_assignments USING btree (user_id, role, scope_type, organizational_unit_id, project_id) NULLS NOT DISTINCT;


--
-- Name: unique_unit_membership; Type: INDEX; Schema: business; Owner: -
--

CREATE UNIQUE INDEX unique_unit_membership ON business.organizational_memberships USING btree (user_id, organizational_unit_id);


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
-- Name: role_assignments role_assignments_administration_guard; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER role_assignments_administration_guard AFTER INSERT OR DELETE OR UPDATE ON business.role_assignments DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_project_administration();


--
-- Name: users users_administration_guard; Type: TRIGGER; Schema: business; Owner: -
--

CREATE CONSTRAINT TRIGGER users_administration_guard AFTER UPDATE ON business.users DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((old.status)::text IS DISTINCT FROM (new.status)::text)) EXECUTE FUNCTION business.validate_project_administration();


--
-- Name: role_assignments fk_rails_0f09f7eaf9; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.role_assignments
    ADD CONSTRAINT fk_rails_0f09f7eaf9 FOREIGN KEY (organization_id, user_id) REFERENCES business.users(organization_id, id);


--
-- Name: organizational_units fk_rails_1edc901ddd; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_units
    ADD CONSTRAINT fk_rails_1edc901ddd FOREIGN KEY (organization_id, parent_unit_id) REFERENCES business.organizational_units(organization_id, id);


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
-- Name: project_memberships fk_rails_329479fb2c; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.project_memberships
    ADD CONSTRAINT fk_rails_329479fb2c FOREIGN KEY (organization_id, project_id) REFERENCES business.projects(organization_id, id);


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
-- Name: organizational_memberships fk_rails_68eac7feb9; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_memberships
    ADD CONSTRAINT fk_rails_68eac7feb9 FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: projects fk_rails_9aee26923d; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.projects
    ADD CONSTRAINT fk_rails_9aee26923d FOREIGN KEY (organization_id) REFERENCES business.organizations(id);


--
-- Name: organizational_memberships fk_rails_c4505bc98f; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.organizational_memberships
    ADD CONSTRAINT fk_rails_c4505bc98f FOREIGN KEY (organization_id, organizational_unit_id) REFERENCES business.organizational_units(organization_id, id);


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
-- Name: reporting_relationships fk_rails_f8f78d2a18; Type: FK CONSTRAINT; Schema: business; Owner: -
--

ALTER TABLE ONLY business.reporting_relationships
    ADD CONSTRAINT fk_rails_f8f78d2a18 FOREIGN KEY (organization_id, report_id) REFERENCES business.users(organization_id, id);


--
-- PostgreSQL database dump complete
--

SET search_path TO business;

INSERT INTO "schema_migrations" (version) VALUES
('20261109000100'),
('20261107000100');

