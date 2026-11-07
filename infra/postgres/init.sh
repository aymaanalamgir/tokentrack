#!/bin/sh
set -eu

# psql variables safely quote values and identifiers, including unusual passwords.
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1 \
  --set core_user="$CORE_DB_USER" --set core_password="$CORE_DB_PASSWORD" \
  --set usage_user="$USAGE_DB_USER" --set usage_password="$USAGE_DB_PASSWORD" \
  --set test_db="$POSTGRES_TEST_DB" <<'SQL'
CREATE ROLE :"core_user" LOGIN PASSWORD :'core_password';
CREATE ROLE :"usage_user" LOGIN PASSWORD :'usage_password';
CREATE DATABASE :"test_db";
SQL

for database in "$POSTGRES_DB" "$POSTGRES_TEST_DB"; do
  psql --username "$POSTGRES_USER" --dbname "$database" --set ON_ERROR_STOP=1 \
    --set database="$database" --set core_user="$CORE_DB_USER" --set usage_user="$USAGE_DB_USER" <<'SQL'
REVOKE ALL ON DATABASE :"database" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"database" TO :"core_user", :"usage_user";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA IF NOT EXISTS business AUTHORIZATION :"core_user";
CREATE SCHEMA IF NOT EXISTS usage AUTHORIZATION :"usage_user";
ALTER ROLE :"core_user" IN DATABASE :"database" SET search_path = business;
ALTER ROLE :"usage_user" IN DATABASE :"database" SET search_path = usage;
SQL
done
