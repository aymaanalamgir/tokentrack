# Core API

API-only Rails service. Owns the `business` PostgreSQL schema. Only `GET /api/v1/health` is implemented. It runs `SELECT 1`, returns JSON and HTTP 503 on database failure, and never returns connection details.

Run `docker compose exec core-api bundle exec rspec` from the repository root. See [development instructions](../../docs/development.md) for configuration and future migrations.
