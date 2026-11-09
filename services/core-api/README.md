# Core API

Rails API owns the `business` PostgreSQL schema. Slice 2 adds tenant-scoped organizational entities, revocable server-side demo sessions, reusable authorization policies, directory/management projections, and limited project metadata editing. Health remains public and database-aware.

From the repository root:

```bash
docker compose exec core-api bin/rails db:migrate db:seed
docker compose exec -e RAILS_ENV=test core-api bin/rails db:migrate
docker compose exec core-api bundle exec rspec
```

Demo selection/seed/reset require `DEMO_AUTH_ENABLED=true` in development/test and are always disabled in production. See [architecture](../../docs/architecture.md), [contracts](../../contracts/README.md), and [development](../../docs/development.md).
