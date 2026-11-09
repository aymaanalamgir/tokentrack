package com.tokentrack.usage.generation

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.domain.sha256
import com.tokentrack.usage.ingestion.UsageCsvReader
import org.apache.commons.csv.CSVFormat
import org.apache.commons.csv.CSVPrinter
import org.springframework.stereotype.Component
import java.io.StringWriter
import java.nio.file.Files
import java.nio.file.Path
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Locale
import java.util.Random

@Component
class SyntheticGenerator(private val mapper: ObjectMapper) {
    data class Dataset(val rows: List<Map<String, String>>, val manifest: Map<String, Any>)
    private fun canonical(node: JsonNode): String = when {
        node.isObject -> node.fieldNames().asSequence().sorted().joinToString(",", "{", "}") { mapper.writeValueAsString(it) + ":" + canonical(node[it]) }
        node.isArray -> node.map { canonical(it) }.sorted().joinToString(",", "[", "]")
        else -> node.toString()
    }
    fun generate(snapshot: JsonNode, seed: Long, from: LocalDate, to: LocalDate): Dataset {
        require(snapshot.path("snapshot_version").asInt() == 1 && snapshot.path("policy_version").asText() == "membership-period-v1") { "Unsupported organizational snapshot" }
        val days = java.time.temporal.ChronoUnit.DAYS.between(from, to).toInt()
        require(days in 1..90) { "Choose an explicit 1–90 day UTC window (end exclusive)" }
        require(from.year >= 2000 && to.year <= 2099) { "Window must be in years 2000–2099" }
        val snapshotHash = sha256(canonical(snapshot))
        val stream = sha256("generator-v1/$seed/$from/$to/$snapshotHash")
        val random = Random(stream.take(16).toULong(16).toLong())
        val users = snapshot.path("users").sortedBy { it.path("id").asText() }
        require(users.isNotEmpty() && users.size <= 2000) { "Snapshot must contain 1–2000 fictional users" }
        val organizations = snapshot.path("organizations").map { it.path("id").asText() }.toSet()
        val projects = snapshot.path("projects").filter { it.path("status").asText() != "archived" }.associate { it.path("id").asText() to it.path("organization_id").asText() }
        val periods = snapshot.path("memberships").groupBy { it.path("user_id").asText() }
        val rows = mutableListOf<Map<String, String>>()
        repeat(days) { day ->
            val date = from.plusDays(day.toLong())
            val weekend = date.dayOfWeek in listOf(DayOfWeek.SATURDAY, DayOfWeek.SUNDAY)
            val spike = day in (days * 2 / 3)..(days * 2 / 3 + 2)
            users.forEach { user ->
                val id = user.path("id").asText(); val org = user.path("organization_id").asText()
                require(org in organizations) { "Snapshot user has no organization" }
                val function = user.path("job_function").asText().lowercase(Locale.ROOT)
                val engineering = listOf("engineer", "architecture", "data science").any { it in function }
                val workflows = when {
                    engineering -> listOf("coding-assistant" to "coding", "code-review-agent" to "code-review", "test-generator" to "testing", "debugging-agent" to "debugging")
                    "design" in function -> listOf("research-assistant" to "user-research", "content-assistant" to "design-content")
                    "product" in function -> listOf("documentation-assistant" to "requirements", "research-assistant" to "research-synthesis")
                    "sales" in function || "marketing" in function -> listOf("proposal-assistant" to "proposal-writing", "research-assistant" to "account-research")
                    else -> listOf("knowledge-assistant" to "knowledge-retrieval", "document-assistant" to "document-analysis")
                }
                val count = if (weekend) random.nextInt(2) else (if (engineering) 5 else 2) + random.nextInt(3) + if (engineering && spike) 4 else 0
                repeat(count) { index ->
                    require(rows.size < UsageCsvReader.MAX_ROWS) { "Generated dataset exceeds 100000 rows; shorten the window" }
                    val time = date.atTime(13 + random.nextInt(9), random.nextInt(60), random.nextInt(60)).toInstant(ZoneOffset.UTC)
                    val eligible = periods[id].orEmpty().filter {
                        it.path("organization_id").asText() == org && projects[it.path("project_id").asText()] == org &&
                            Instant.parse(it.path("joined_at").asText()) <= time &&
                            (it.path("left_at").isNull || Instant.parse(it.path("left_at").asText()) > time)
                    }.map { it.path("project_id").asText() }.distinct().sorted()
                    val project = if (eligible.isNotEmpty() && random.nextInt(5) != 0) eligible[random.nextInt(eligible.size)] else ""
                    val (tool, workflow) = workflows[random.nextInt(workflows.size)]
                    val agent = "agent" in tool
                    val scale = (if (agent) 4 else 1) * (if (engineering && spike) 6 else 1)
                    val input = (if (engineering) 2000 + random.nextInt(18000) else 500 + random.nextInt(5000)) * scale
                    val output = (300 + random.nextInt(if (engineering) 6000 else 1800)) * scale
                    val providerIndex = random.nextInt(3)
                    val provider = listOf("openai", "anthropic", "local")[providerIndex]
                    // Synthetic identifiers only; no claims about provider catalogues.
                    val model = listOf("demo-code-v1", "demo-reasoning-v1", "demo-small-v1")[providerIndex]
                    val key = sha256("$stream/$org/$id/$date/$index")
                    rows += linkedMapOf("schema_version" to "1", "event_id" to "syn-${key.take(40)}", "organization_id" to org,
                        "user_id" to id, "project_id" to project, "provider" to provider, "model" to model, "tool" to tool,
                        "input_tokens" to input.toString(), "output_tokens" to output.toString(), "occurred_at" to time.toString(),
                        "cached_input_tokens" to (input / (2 + random.nextInt(5))).toString(),
                        "agent_run_id" to if (agent) "run-${sha256("$stream/$id/$date/${index / 3}").take(24)}" else "", "workflow_type" to workflow)
                }
            }
        }
        val manifest = linkedMapOf<String, Any>("generator_version" to 1, "schema_version" to 1, "seed" to seed, "from_inclusive" to from.toString(), "to_exclusive" to to.toString(),
            "snapshot_sha256" to snapshotHash, "rows" to rows.size, "organization_count" to rows.map { it.getValue("organization_id") }.toSet().size,
            "primary_team_count" to users.map { it.path("primary_unit_id").asText() }.filter { it.isNotEmpty() && it != "null" }.toSet().size,
            "project_count" to rows.map { it.getValue("project_id") }.filter { it.isNotEmpty() }.toSet().size,
            "unassigned_rows" to rows.count { it["project_id"].isNullOrEmpty() }, "providers" to rows.map { it.getValue("provider") }.toSet().sorted())
        return Dataset(rows, manifest)
    }
    fun write(path: Path, rows: List<Map<String, String>>) {
        val csv = StringWriter()
        CSVPrinter(csv, CSVFormat.RFC4180.builder().setRecordSeparator("\n").setHeader(*UsageCsvReader.HEADERS.toTypedArray()).get()).use { printer ->
            rows.forEach { row -> printer.printRecord(UsageCsvReader.HEADERS.map { row[it].orEmpty() }) }
        }
        val bytes = csv.toString().toByteArray(Charsets.UTF_8)
        require(bytes.size <= UsageCsvReader.MAX_BYTES) { "Generated file exceeds 20 MiB; shorten the window" }
        path.toAbsolutePath().parent?.let(Files::createDirectories)
        Files.write(path, bytes)
    }
    fun invalidRows(rows: List<Map<String, String>>): List<Map<String, String>> {
        require(rows.size >= 2)
        val first = rows.first(); val second = rows.last()
        fun bad(field: String, value: String, label: String) = first + mapOf("event_id" to "invalid-$label-${first.getValue("event_id").takeLast(16)}", field to value)
        val other = rows.first { it["organization_id"] != first["organization_id"] }
        return listOf(first, second, first, first + ("input_tokens" to (first.getValue("input_tokens").toLong() + 1).toString()),
            bad("input_tokens", "-1", "negative"), bad("input_tokens", "1.5", "fraction"), bad("user_id", "not-a-uuid", "uuid"),
            bad("occurred_at", "yesterday", "timestamp"), bad("model", "unsupported model text", "model"), bad("schema_version", "2", "version"),
            bad("input_tokens", "0", "zero") + mapOf("output_tokens" to "0", "cached_input_tokens" to "0"),
            bad("user_id", "00000000-0000-0000-0000-000000000001", "unknown-user"),
            bad("organization_id", "00000000-0000-0000-0000-000000000002", "unknown-org"),
            bad("user_id", other.getValue("user_id"), "cross-tenant"),
            bad("project_id", "00000000-0000-0000-0000-000000000003", "unknown-project"),
            bad("event_id", "", "required"), bad("cached_input_tokens", "1000000000000", "cached"))
    }
}
