package com.tokentrack.usage.generation

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.domain.sha256
import org.springframework.stereotype.Component
import java.nio.file.Files
import java.nio.file.Path
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.SplittableRandom
import kotlin.math.exp
import kotlin.math.ln

/**
 * Twelve-month workload for the fictional enterprise companies, from demo/enterprise/companies-v1.json and the
 * Rails organizational snapshot (people, offices, dated project memberships, fixture references).
 *
 * Two kinds of usage event, both canonical CSV v1 rows in the company's own source namespace:
 *  - Agent runs: several linked events, each one model call, plus an execution JSONL v1 record per run.
 *  - Interactive roll-ups: one event per person, interactive workflow and half-month period (1st–15th, 16th–end),
 *    holding the summed tokens of that period's calls. Its source model carries the spec's "rollup_suffix"
 *    ("-rollup") and has its own pricing mapping, so a roll-up is never presented as a single provider request. Periods never cross a month, and schedules change only on month boundaries, so pricing the
 *    summed tokens costs exactly what pricing each call would.
 *
 * Nothing is priced or posted here. All randomness comes from SHA-256-seeded generators keyed by seed, company,
 * person and period or day, so identical inputs produce identical bytes.
 */
@Component
class EnterpriseDemoGenerator(private val mapper: ObjectMapper, private val csv: SyntheticGenerator) {
    data class Options(val seed: Long, val profile: String, val start: LocalDate?, val companies: Set<String>?, val output: Path)
    private data class Membership(val project: String, val joined: Instant, val left: Instant?)
    private data class Person(val id: String, val function: String, val office: String?, val memberships: List<Membership>)
    private data class Agent(val node: JsonNode, val ownerId: String) { val key: String get() = node["key"].asText() }
    private data class Profile(val included: Boolean, val activity: Double, val jitter: Double, val adoptMonth: Int)

    private fun random(vararg parts: Any) = SplittableRandom(sha256(parts.joinToString("/")).take(16).toULong(16).toLong())
    private fun logUniform(r: SplittableRandom, range: JsonNode) = exp(ln(range[0].asDouble()) + r.nextDouble() * (ln(range[1].asDouble()) - ln(range[0].asDouble())))
    private fun <T> weighted(r: SplittableRandom, weights: List<Pair<T, Double>>): T {
        val total = weights.sumOf { it.second }; var x = r.nextDouble() * total
        for ((item, w) in weights) { x -= w; if (x <= 0) return item }
        return weights.last().first
    }

    fun generate(spec: JsonNode, snapshot: JsonNode, options: Options): Map<String, Any?> {
        require(spec["spec_version"].asInt() == 1) { "Unsupported enterprise spec" }
        val profileScale = spec["profiles"][options.profile]?.get("scale")?.asDouble() ?: throw IllegalArgumentException("Unknown profile ${options.profile}")
        val start = options.start ?: LocalDate.parse(spec["start"].asText())
        val months = spec["months"].asInt()
        val end = start.plusMonths(months.toLong())
        require(months in 1..24 && start.dayOfMonth == 1 && start.year >= 2000 && end.year <= 2099) { "Start must be the first day of a month" }
        val results = linkedMapOf<String, Any?>()
        for (company in spec["companies"]) {
            val slug = company["slug"].asText()
            if (options.companies != null && slug !in options.companies) continue
            val org = snapshot["organizations"].firstOrNull { it["slug"].asText() == slug } ?: throw IllegalArgumentException("Snapshot lacks $slug; seed it and export with --organizations")
            val orgId = org["id"].asText()
            val memberships = snapshot["memberships"].filter { it["organization_id"].asText() == orgId }.groupBy { it["user_id"].asText() }
            val people = snapshot["users"].filter { it["organization_id"].asText() == orgId }.map { u ->
                Person(u["id"].asText(), u["job_function"].asText(), u["office"]?.takeUnless { it.isNull }?.asText(),
                    memberships[u["id"].asText()].orEmpty().map { m -> Membership(m["project_id"].asText(), Instant.parse(m["joined_at"].asText()), m["left_at"]?.takeUnless { it.isNull }?.let { Instant.parse(it.asText()) }) })
            }.sortedBy { it.id }
            require(people.isNotEmpty()) { "No people for $slug" }
            val agents = company["agents"].map { a -> Agent(a, org["references"][a["owner"].asText()]?.asText() ?: throw IllegalArgumentException("Missing owner reference ${a["owner"]}")) }
            results[slug] = generateCompany(spec, company, orgId, people, agents, options, profileScale, start, months)
        }
        val manifest = mapOf("schema_version" to 1, "generator" to "enterprise-demo-v2", "seed" to options.seed, "profile" to options.profile, "start" to start.toString(), "end_exclusive" to end.toString(), "companies" to results)
        Files.createDirectories(options.output)
        Files.writeString(options.output.resolve("manifest.json"), mapper.writerWithDefaultPrettyPrinter().writeValueAsString(manifest) + "\n")
        return manifest
    }

    private fun generateCompany(spec: JsonNode, company: JsonNode, orgId: String, people: List<Person>, agents: List<Agent>, options: Options, profileScale: Double,
                                start: LocalDate, months: Int): Map<String, Any?> {
        val slug = company["slug"].asText(); val source = company["source"].asText(); val seed = options.seed
        val activity = company["activity"]; val tiers = spec["tiers"]; val workflows = spec["workflows"]; val functions = company["functions"]
        val offices = company["offices"]; val hq = offices.fieldNames().next(); val suffix = spec["rollup_suffix"].asText()
        val monthFactors = activity["months"].map { it.asDouble() }; require(monthFactors.size >= months)
        val holidays = activity["holidays"].map { it.asText() }.toSet()
        val drift = activity["frontier_drift"].map { it.asDouble() }
        val windowEnd = start.plusMonths(months.toLong()).atStartOfDay(ZoneOffset.UTC).toInstant()
        val agentsByWorkflow = agents.groupBy { it.node["workflow"].asText() }
        val fallback = mapper.readTree("""{"tier":"moderate","project_share":0.1,"workflows":{"chat-assistant":0.6,"document-drafting":0.4}}""")
        fun fn(p: Person) = functions[p.function] ?: fallback
        fun tier(p: Person) = tiers[fn(p)["tier"].asText()]
        fun monthIndex(day: LocalDate) = ChronoUnit.MONTHS.between(start, day.withDayOfMonth(1)).toInt()
        fun dayFactor(day: LocalDate) = monthFactors[monthIndex(day)] * (if (day.dayOfWeek.value >= 6) activity["weekend_factor"].asDouble() else 1.0) *
            (if ("%02d-%02d".format(day.monthValue, day.dayOfMonth) in holidays) 0.25 else 1.0)
        fun frontierShift(m: Int) = drift[0] + (drift[1] - drift[0]) * m / (months - 1).coerceAtLeast(1)
        fun offset(p: Person) = (offices[p.office ?: hq] ?: offices[hq]).asLong()
        fun localTime(p: Person, day: LocalDate, r: SplittableRandom): Instant =
            day.atStartOfDay(ZoneOffset.UTC).toInstant().plus(Duration.ofMinutes(9L * 60 + r.nextInt(9 * 60) - offset(p) * 60)).plusSeconds(r.nextInt(60).toLong())
                .coerceIn(day.atStartOfDay(ZoneOffset.UTC).toInstant().plusSeconds(60), day.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant().minusSeconds(4 * 3600))
        fun project(p: Person, from: Instant, to: Instant, share: Double, r: SplittableRandom): String {
            val covering = p.memberships.filter { it.joined <= from && (it.left == null || it.left > to) }.map { it.project }.distinct().sorted()
            return if (covering.isNotEmpty() && r.nextDouble() < share) covering[r.nextInt(covering.size)] else ""
        }
        fun model(wf: JsonNode, m: Int, r: SplittableRandom): Pair<String, String> {
            if (r.nextDouble() < activity["unpriced_share"].asDouble()) return spec["models"]["unpriced"].let { it["provider"].asText() to it["model"].asText() }
            val choice = weighted(r, wf["models"].properties().map { (name, w) -> name to w.asDouble() * (if (name == "frontier") frontierShift(m) else 1.0) })
            return spec["models"][choice].let { it["provider"].asText() to it["model"].asText() }
        }
        fun tokens(wf: JsonNode, r: SplittableRandom, calls: Int, inputScale: Double, outputScale: Double): Triple<Long, Long, Long> {
            var input = 0L; var output = 0L; var cached = 0L
            repeat(calls) {
                var i = (logUniform(r, wf["input"]) * inputScale).toLong().coerceIn(200, 180_000)
                val o = (logUniform(r, wf["output"]) * outputScale).toLong().coerceIn(50, 60_000)
                if (i + o > 195_000) i = 195_000 - o
                input += i; output += o
                cached += (i * (wf["cached"][0].asDouble() + r.nextDouble() * (wf["cached"][1].asDouble() - wf["cached"][0].asDouble()))).toLong()
            }
            return Triple(input, output, cached)
        }
        fun row(id: String, p: Person, project: String, provider: String, model: String, workflow: String, time: Instant, t: Triple<Long, Long, Long>, runId: String) =
            mapOf("schema_version" to "1", "event_id" to id, "organization_id" to orgId, "user_id" to p.id, "project_id" to project, "provider" to provider, "model" to model,
                "tool" to workflows[workflow]["tool"].asText(), "input_tokens" to t.first.toString(), "output_tokens" to t.second.toString(), "cached_input_tokens" to t.third.toString(),
                "occurred_at" to time.toString(), "agent_run_id" to runId, "workflow_type" to workflow)

        // Per person: whether included in this profile, how often they use AI, intensity jitter, adoption month.
        val profiles = people.associate { p ->
            val r = random("enterprise-v2", seed, slug, "person", p.id); val adoption = tier(p)["adoption"]
            val activityFactor = weighted(r, listOf(1.0 to adoption["daily"].asDouble(), 0.3 to adoption["weekly"].asDouble(), 0.07 to adoption["occasional"].asDouble(), 0.0 to adoption["none"].asDouble()))
            val jitter = 0.6 + r.nextDouble() * 0.9
            val lag = (r.nextDouble() * (tier(p)["lag_months"].asInt() + 1)).toInt()
            p.id to Profile(r.nextDouble() < profileScale, activityFactor, jitter, lag)
        }
        val short = slug.substringBefore('-')
        val rows = mutableListOf<Map<String, String>>()

        // Pass 1: interactive roll-ups per person, half-month period and non-agent workflow.
        val periods = (0 until months).flatMap { m -> val first = start.plusMonths(m.toLong()); listOf(first to first.withDayOfMonth(16), first.withDayOfMonth(16) to first.plusMonths(1)) }
        for (p in people) {
            val pr = profiles.getValue(p.id); if (!pr.included || pr.activity == 0.0) continue
            val f = fn(p); val dailyCalls = tier(p)["daily_calls"]
            val interactive = f["workflows"].properties().filter { !agentsByWorkflow.containsKey(it.key) }.map { it.key to it.value.asDouble() }
            if (interactive.isEmpty()) continue
            val callsPerDay = (dailyCalls[0].asDouble() + dailyCalls[1].asDouble()) / 2 * pr.activity * pr.jitter * activity["rollup_scale"].asDouble() * interactive.sumOf { it.second } / f["workflows"].properties().sumOf { it.value.asDouble() }
            for ((from, until) in periods) {
                val m = monthIndex(from); if (m < pr.adoptMonth) continue
                val r = random("enterprise-v2", seed, slug, "period", p.id, from)
                val days = generateSequence(from) { it.plusDays(1) }.takeWhile { it < until }.toList()
                val expected = days.sumOf { callsPerDay * dayFactor(it) }
                val calls = expected.toInt() + if (r.nextDouble() < expected - expected.toInt()) 1 else 0
                if (calls == 0) continue
                val perWorkflow = sortedMapOf<String, Int>()
                repeat(calls) { perWorkflow.merge(weighted(r, interactive), 1, Int::plus) }
                val workdays = days.filter { it.dayOfWeek.value <= 5 }.ifEmpty { days }
                for ((workflow, n) in perWorkflow) {
                    val wf = workflows[workflow]
                    val time = localTime(p, workdays[r.nextInt(workdays.size)], r)
                    val projectId = project(p, from.atStartOfDay(ZoneOffset.UTC).toInstant(), until.atStartOfDay(ZoneOffset.UTC).toInstant(), f["project_share"].asDouble(), r)
                    val (provider, baseModel) = model(wf, m, r)
                    rows += row("ent-$short-u-${sha256("enterprise-v2/$seed/$slug/${p.id}/$from/$workflow").take(24)}", p, projectId, provider, baseModel + suffix, workflow, time, tokens(wf, r, n, 1.0, 1.0), "")
                }
            }
        }
        val rollups = rows.size

        // Pass 2: agent runs for agentic workflows, scaled so the company's event target is met on average.
        val target = activity["events"][options.profile]?.asDouble() ?: activity["events"]["demo"].asDouble() * profileScale
        val agentTarget = maxOf(target - rollups, target * 0.15)
        fun agentWeight(p: Person) = fn(p)["workflows"].properties().filter { agentsByWorkflow.containsKey(it.key) }.sumOf { (w, weight) ->
            weight.asDouble() * workflows[w]["calls"].let { (it[0].asDouble() + it[1].asDouble()) / 2 } } / fn(p)["workflows"].properties().sumOf { it.value.asDouble() }
        val dayList = generateSequence(start) { it.plusDays(1) }.takeWhile { it < start.plusMonths(months.toLong()) }.toList()
        var expectedCalls = 0.0
        for (day in dayList) { val factor = dayFactor(day); val m = monthIndex(day)
            for (p in people) { val pr = profiles.getValue(p.id); if (pr.included && m >= pr.adoptMonth) expectedCalls += tier(p)["events"].asDouble() * pr.activity * pr.jitter * factor * agentWeight(p) } }
        val k = if (expectedCalls > 0) agentTarget / expectedCalls else 0.0
        val runs = mutableListOf<Pair<Instant, String>>(); val runOutcomes = sortedMapOf<String, Int>()
        val errors = listOf("timeout", "provider_error", "tool_execution_error", "validation_failure")
        for (day in dayList) {
            val factor = dayFactor(day); val m = monthIndex(day)
            for (p in people) {
                val pr = profiles.getValue(p.id); if (!pr.included || m < pr.adoptMonth || pr.activity == 0.0) continue
                val f = fn(p)
                val agentic = f["workflows"].properties().filter { agentsByWorkflow.containsKey(it.key) }.map { it.key to it.value.asDouble() }
                if (agentic.isEmpty()) continue
                val r = random("enterprise-v2", seed, slug, "day", p.id, day)
                val mean = tier(p)["events"].asDouble() * pr.activity * pr.jitter * factor * k * agentic.sumOf { it.second } / f["workflows"].properties().sumOf { it.value.asDouble() }
                val slots = mean.toInt() + if (r.nextDouble() < mean - mean.toInt()) 1 else 0
                repeat(slots) { slot ->
                    val workflow = weighted(r, agentic); val wf = workflows[workflow]
                    val agentList = agentsByWorkflow.getValue(workflow); val agent = agentList[r.nextInt(agentList.size)]
                    val at = localTime(p, day, r)
                    val projectId = project(p, at.minusSeconds(60), at.plusSeconds(3 * 3600), f["project_share"].asDouble(), r)
                    // Outcomes are synthetic draws from the agent's profile for this month, never inferred from tokens.
                    var success = agent.node["success"].asDouble(); var retry = agent.node["retry"].asDouble(); var outputMultiplier = 1.0
                    agent.node["drift"]?.forEach { if (m >= it["from_month"].asInt()) { it["success"]?.let { v -> success = v.asDouble() }; it["retry"]?.let { v -> retry = v.asDouble() }; it["output_multiplier"]?.let { v -> outputMultiplier = v.asDouble() } } }
                    val identity = sha256("enterprise-v2/$seed/$slug/${p.id}/$day/$slot")
                    val runId = "ent-$short-r-${identity.take(24)}"
                    val calls = wf["calls"][0].asInt() + r.nextInt(wf["calls"][1].asInt() - wf["calls"][0].asInt() + 1)
                    val retries = if (r.nextDouble() < retry) (if (r.nextDouble() < 0.25) 2 else 1) else 0
                    var time = at
                    val callTimes = (0 until calls + retries).map { i -> if (i > 0) time = time.plusSeconds(40L + r.nextInt(140)); time }
                    callTimes.forEachIndexed { i, t ->
                        val (provider, mdl) = model(wf, m, r)
                        rows += row("ent-$short-e-${sha256("$identity/$i").take(24)}", p, projectId, provider, mdl, workflow, t, tokens(wf, r, 1, if (i == 0) 1.0 else 0.6 + r.nextDouble() * 0.4, outputMultiplier), runId)
                    }
                    val startedAt = at.minusSeconds(3); val last = callTimes.last()
                    val running = last > windowEnd.minus(Duration.ofHours(30)) && r.nextDouble() < 0.4
                    val outcome = when { running -> "unknown"; r.nextDouble() < success -> "success"; r.nextDouble() < 0.75 -> "failure"; else -> "cancelled" }
                    val completedAt = if (running) null else last.plusSeconds(5)
                    val span = Duration.between(startedAt, last).seconds
                    val attempts = (0..retries).map { i ->
                        val aStart = startedAt.plusSeconds(i * span / (retries + 1)); val final = i == retries
                        val aEnd = if (final) completedAt else maxOf(aStart, startedAt.plusSeconds((i + 1) * span / (retries + 1) - 1))
                        val status = if (!final || outcome == "failure") "failed" else when (outcome) { "cancelled" -> "cancelled"; "unknown" -> "running"; else -> "succeeded" }
                        mapOf("attempt_id" to "$runId-a${i + 1}", "attempt_number" to i + 1, "started_at" to aStart.toString(), "completed_at" to aEnd?.toString(), "status" to status,
                            "error_category" to if (status == "failed") errors[r.nextInt(errors.size)] else null)
                    }
                    val record = linkedMapOf("schema_version" to 1, "source" to source, "organization_id" to orgId, "run_id" to runId,
                        "agent" to linkedMapOf("key" to agent.key, "name" to agent.node["name"].asText(), "description" to "Synthetic ${company["name"].asText()} agent for ${workflow.replace('-', ' ')} workflows.",
                            "workflow_type" to workflow, "owner_user_id" to agent.ownerId, "project_id" to null, "status" to "active"),
                        "user_id" to p.id, "project_id" to projectId.ifEmpty { null }, "started_at" to startedAt.toString(), "completed_at" to completedAt?.toString(),
                        "status" to mapOf("success" to "completed", "failure" to "failed", "cancelled" to "cancelled", "unknown" to "running").getValue(outcome), "outcome" to outcome,
                        "outcome_source" to "synthetic_fixture", "attempts" to attempts)
                    runs += startedAt to mapper.writeValueAsString(record)
                    runOutcomes.merge(outcome, 1, Int::plus)
                }
            }
        }
        // One file per UTC month keeps each import well inside the CSV (20 MB / 100k rows) and JSONL limits.
        val dir = options.output.resolve(slug); Files.createDirectories(dir)
        val files = sortedMapOf<String, Any>()
        rows.sortedWith(compareBy({ it["occurred_at"] }, { it["event_id"] })).groupBy { it.getValue("occurred_at").take(7) }.forEach { (month, monthRows) ->
            val path = dir.resolve("usage-$month.csv"); csv.write(path, monthRows)
            files["usage-$month.csv"] = mapOf("rows" to monthRows.size, "sha256" to sha256(Files.readString(path)))
        }
        runs.sortedWith(compareBy({ it.first }, { it.second })).groupBy { it.first.toString().take(7) }.forEach { (month, monthRuns) ->
            val text = monthRuns.joinToString("") { it.second + "\n" }
            Files.writeString(dir.resolve("executions-$month.jsonl"), text)
            files["executions-$month.jsonl"] = mapOf("rows" to monthRuns.size, "sha256" to sha256(text))
        }
        return mapOf("organization_id" to orgId, "source" to source, "people" to people.size, "people_in_profile" to profiles.values.count { it.included },
            "active_people" to rows.map { it["user_id"] }.toSet().size, "usage_events" to rows.size, "rollup_events" to rollups, "agent_runs" to runs.size,
            "agent_linked_events" to rows.size - rollups, "project_events" to rows.count { !it["project_id"].isNullOrEmpty() }, "run_outcomes" to runOutcomes, "files" to files)
    }
}
