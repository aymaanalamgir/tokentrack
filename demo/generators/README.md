# Deterministic usage fixtures

Run from the repository root after migrations/seeds and service credential setup:

```bash
demo/generators/generate-usage.sh 2026-11-10 2026-12-10 42
```

This exports a minimal, credential-protected snapshot from Rails, then runs the Kotlin `SyntheticGenerator`. The saved snapshot contains fictional identifiers, job functions, primary team IDs, and recorded membership periods; it contains no emails, employee names, reporting graphs, or permissions. Kotlin never reconstructs Rails UUIDs or creates business records.

The date interval is UTC, inclusive start and exclusive end. Choose a window overlapping the recorded membership periods to get project-attributed events. Earlier dates produce unassigned activity when project membership cannot be established. After a demo reset, export again and choose an appropriate explicit window; do not backdate memberships to make a fixture pass.

The generator version, seed, canonical snapshot contents, and explicit date interval determine all records and event IDs. Snapshot object keys and set-like arrays are sorted for the snapshot hash. User/project choices follow stable ordering and Java's seeded `Random`; current time and filenames are not inputs. A manifest next to the CSV records reproducibility inputs and coverage. A changed snapshot is a changed input, even if the random seed is unchanged.

The generator models weekday/weekend intensity, a three-day engineering spike, engineering/agent workflows with higher token counts, function-specific tools, multiple synthetic provider/model dimensions, and unassigned activity. Model names are fictional identifiers, not live provider catalogue claims. Project assignment uses half-open recorded membership periods and ignores home-team ownership.

Outputs under `demo/fixtures/`:

- `organization-snapshot-v1.json`: exported generator input.
- `usage-events-v1.csv` and its manifest: several thousand valid events for the standard 30-day window.
- `usage-events-invalid-v1.csv`: a small mixed file with valid rows, replay/conflict rows, and deterministic invalid fields/references.

Run `docker compose exec usage-engine bin/usage help` to inspect accepted arguments. See [CSV contract](../../contracts/usage-event-v1.md) and [development workflow](../../docs/development.md) for imports, reports, source namespaces, and exit codes. No prompts, completions, costs, or productivity scores are generated.
