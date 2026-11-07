# Usage Engine

Kotlin/Spring Boot service. Owns the `usage` PostgreSQL schema. Only standard database-aware Actuator health is exposed; ingestion, pricing, and event delivery are planned.

Run `docker compose exec usage-engine gradle test` from the repository root. JUnit starts the application with an H2 test database and verifies healthy/unhealthy Actuator responses. The full Compose runtime uses PostgreSQL. See [development instructions](../../docs/development.md).

After Kotlin source changes, run `docker compose restart usage-engine` to compile and restart. The checked-in Gradle wrapper supports host development with JDK 21.
