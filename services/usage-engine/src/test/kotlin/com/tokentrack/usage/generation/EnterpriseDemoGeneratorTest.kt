package com.tokentrack.usage.generation

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import com.tokentrack.usage.ingestion.UsageCsvReader
import org.apache.commons.csv.CSVFormat
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant

class EnterpriseDemoGeneratorTest {
    private val mapper = ObjectMapper()
    private val specPath = listOf(Path.of("/app/demo/enterprise/companies-v1.json"), Path.of("../../demo/enterprise/companies-v1.json")).firstOrNull(Files::exists)

    /** Memento AI's real spec with a synthetic 18-person snapshot: one dated rotation and one late project start. */
    private fun fixture(): Pair<JsonNode, JsonNode> {
        assumeTrue(specPath != null, "enterprise spec not mounted")
        val spec = mapper.readTree(specPath!!.toFile()) as ObjectNode
        spec.replace("companies", mapper.createArrayNode().add(spec["companies"].first { it["slug"].asText() == "memento-ai" }))
        val company = spec["companies"][0]
        val functions = company["departments"].flatMap { d -> listOfNotNull(d["head"]?.get("function")?.asText()) + d["teams"].flatMap { t -> List(t["size"].asInt()) { t["function"].asText() } } }
        val org = "00000000-0000-0000-0000-0000000000aa"
        val users = functions.mapIndexed { i, fn -> mapOf("id" to "00000000-0000-0000-0000-%012d".format(i + 1), "organization_id" to org, "job_function" to fn, "primary_unit_id" to null, "office" to "New York") }
        val projects = company["projects"].mapIndexed { i, _ -> "00000000-0000-0000-0001-%012d".format(i + 1) }
        val memberships = users.flatMapIndexed { i, u -> projects.mapIndexedNotNull { j, p ->
            if ((i + j) % 3 != 0) null else mapOf("organization_id" to org, "user_id" to u["id"], "project_id" to p,
                "joined_at" to if (j == 2) "2026-02-01T00:00:00Z" else "2025-10-01T00:00:00Z", "left_at" to if (i == 0 && j == 0) "2026-03-01T00:00:00Z" else null)
        } }
        val references = (company["agents"].map { it["owner"].asText() } + company["personas"].properties().map { it.value.asText() }).distinct().associateWith { users[0]["id"] }
        val snapshot = mapper.valueToTree<JsonNode>(mapOf("organizations" to listOf(mapOf("id" to org, "slug" to "memento-ai", "references" to references)),
            "users" to users, "projects" to projects.map { mapOf("id" to it, "organization_id" to org) }, "memberships" to memberships))
        return spec to snapshot
    }
    private fun run(dir: Path, seed: Long = 42, profile: String = "demo"): Map<String, Any?> { val (spec, snapshot) = fixture()
        return EnterpriseDemoGenerator(mapper, SyntheticGenerator(mapper)).generate(spec, snapshot, EnterpriseDemoGenerator.Options(seed, profile, null, null, dir)) }
    private fun rows(dir: Path) = Files.list(dir.resolve("memento-ai")).filter { it.fileName.toString().startsWith("usage-") }.sorted().toList().flatMap { file ->
        CSVFormat.RFC4180.builder().setHeader().setSkipHeaderRecord(true).get().parse(Files.newBufferedReader(file)).records.map { it.toMap() } }
    private fun runs(dir: Path) = Files.list(dir.resolve("memento-ai")).filter { it.fileName.toString().startsWith("executions-") }.sorted().toList().flatMap { Files.readAllLines(it).map(mapper::readTree) }

    @Test fun `same inputs produce identical files and a different seed does not`(@TempDir a: Path, @TempDir b: Path, @TempDir c: Path) {
        run(a); run(b); run(c, seed = 43)
        assertEquals(Files.readString(a.resolve("manifest.json")), Files.readString(b.resolve("manifest.json")))
        assertNotEquals(Files.readString(a.resolve("manifest.json")).replace("\"seed\" : 42", ""), Files.readString(c.resolve("manifest.json")).replace("\"seed\" : 43", ""))
    }

    @Test fun `twelve months of valid canonical rows inside the window`(@TempDir dir: Path) {
        run(dir)
        val events = rows(dir)
        assertTrue(events.size > 2000)
        assertEquals((0..11).map { java.time.YearMonth.of(2025, 11).plusMonths(it.toLong()).toString() }, events.map { it.getValue("occurred_at").take(7) }.distinct().sorted())
        assertEquals(UsageCsvReader.HEADERS.toSet(), events.first().keys)
        events.forEach { e ->
            val t = Instant.parse(e["occurred_at"]); assertTrue(t >= Instant.parse("2025-11-01T00:00:00Z") && t < Instant.parse("2026-11-01T00:00:00Z"))
            assertTrue(e.getValue("cached_input_tokens").toLong() <= e.getValue("input_tokens").toLong())
        }
        assertEquals(events.size, events.map { it["event_id"] }.toSet().size)
    }

    @Test fun `roll-ups are labelled, single calls stay within one request, and agent runs link to usage`(@TempDir dir: Path) {
        run(dir)
        val events = rows(dir); val runRecords = runs(dir)
        val rollups = events.filter { it.getValue("model").endsWith("-rollup") }
        assertTrue(rollups.isNotEmpty() && rollups.all { it["agent_run_id"].isNullOrEmpty() })
        events.filterNot { it.getValue("model").endsWith("-rollup") }.forEach { e ->
            assertFalse(e["agent_run_id"].isNullOrEmpty(), "non-roll-up usage belongs to an agent run")
            assertTrue(e.getValue("input_tokens").toLong() + e.getValue("output_tokens").toLong() <= 195_000)
        }
        val byRun = events.filter { !it["agent_run_id"].isNullOrEmpty() }.groupBy { it.getValue("agent_run_id") }
        assertEquals(byRun.keys, runRecords.map { it["run_id"].asText() }.toSet())
        runRecords.forEach { r ->
            assertEquals("synthetic_fixture", r["outcome_source"].asText())
            val attempts = r["attempts"]; assertEquals((1..attempts.size()).toList(), attempts.map { it["attempt_number"].asInt() })
            assertTrue(attempts.all { Instant.parse(it["started_at"].asText()) >= Instant.parse(r["started_at"].asText()) })
            assertEquals(r["status"].asText() == "running", r["completed_at"].isNull)
            assertTrue(byRun.getValue(r["run_id"].asText()).all { it.getValue("user_id") == r["user_id"].asText() && it.getValue("project_id") == (r["project_id"]?.takeUnless { it.isNull }?.asText() ?: "") })
        }
        assertTrue(runRecords.map { it["outcome"].asText() }.toSet().containsAll(listOf("success", "failure")))
    }

    @Test fun `project usage only falls inside a recorded membership`(@TempDir dir: Path) {
        run(dir)
        val (_, snapshot) = fixture()
        val periods = snapshot["memberships"].groupBy { it["user_id"].asText() to it["project_id"].asText() }
        rows(dir).filter { !it["project_id"].isNullOrEmpty() }.forEach { e ->
            val t = Instant.parse(e["occurred_at"])
            assertTrue(periods[e.getValue("user_id") to e.getValue("project_id")].orEmpty().any { m ->
                Instant.parse(m["joined_at"].asText()) <= t && (m["left_at"].isNull || Instant.parse(m["left_at"].asText()) > t) }, "event ${e["event_id"]} outside membership")
        }
    }

    @Test fun `smoke profile is a deterministic subset`(@TempDir demo: Path, @TempDir smoke: Path) {
        val full = run(demo); val small = run(smoke, profile = "smoke")
        val fullEvents = ((full["companies"] as Map<*, *>)["memento-ai"] as Map<*, *>)["usage_events"] as Int
        val smokeEvents = ((small["companies"] as Map<*, *>)["memento-ai"] as Map<*, *>)["usage_events"] as Int
        assertTrue(smokeEvents in 1 until fullEvents / 2, "smoke $smokeEvents vs demo $fullEvents")
    }
}
