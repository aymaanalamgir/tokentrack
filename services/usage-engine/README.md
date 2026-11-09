# Usage Engine

Kotlin/Spring Boot owns the usage schema and the CLI ingestion pipeline. Spring JDBC persists immutable events, batch counts, and bounded rejection details; Flyway applies versioned usage-only SQL migrations. Public web exposure remains Actuator health.

```bash
# From repository root with Compose running:
docker compose exec usage-engine bin/usage help
docker compose exec usage-engine bin/usage import /app/demo/fixtures/usage-events-v1.csv --source demo-synthetic-v1
docker compose exec usage-engine bin/usage list
docker compose exec usage-engine gradle test
docker compose exec usage-engine gradle integrationTest
```

`integrationTest` always executes against the separate `USAGE_TEST_DB_NAME` configured by Compose, never the development database. Tests exercise genuine PostgreSQL migration, uniqueness, concurrency, atomic chunks, partial retries, and schema isolation. Health tests retain H2. Parser/validator/reference-client/generator tests run without external Rails requests.

`bin/usage` compiles classes using the pinned Gradle/JDK container and launches a non-web CLI process with original arguments and DevTools restarts disabled. Exit codes propagate directly. Host development uses the checked-in Gradle wrapper with JDK 21; the server remains `UsageEngineApplicationKt`, and the production image remains a runnable jar. Restart usage-engine after source changes; no host Kotlin toolchain is required.

See [CSV contract](../../contracts/usage-event-v1.md), [Slice 4 architecture and results](../../docs/slice4.md), and [development commands](../../docs/development.md).
