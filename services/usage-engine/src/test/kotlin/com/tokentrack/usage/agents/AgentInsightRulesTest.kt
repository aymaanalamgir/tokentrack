package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.generation.SyntheticGenerator
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.math.BigDecimal
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant

class AgentInsightRulesTest {
    private val t=InsightThresholds()
    private val now=Instant.parse("2030-01-01T00:00:00Z")
    private fun row(runs:Int,success:Int=runs,failed:Int=0,cancelled:Int=0,unknown:Int=0,retried:Int=0,input:Long=1000L*runs,output:Long=100L*runs,linked:Int=runs,median:String?="40",timed:Int=runs-unknown)=InsightRules.derive(mapOf(
        "runs" to runs,"successful_runs" to success,"failed_runs" to failed,"cancelled_runs" to cancelled,"incomplete_runs" to unknown,"retried_runs" to retried,"retries" to retried,"attempts" to runs+retried,
        "input_tokens" to input,"output_tokens" to output,"cached_input_tokens" to 0,"usage_events" to linked,"priced_events" to linked,"linked_runs" to linked,"timed_runs" to timed,"median_duration_seconds" to median,"average_duration_seconds" to median))
    private fun types(b:Map<String,Any?>,c:Map<String,Any?>)=InsightRules.detect(b,c,emptyMap(),t).map{it["type"]}

    @Test fun `previous period defaults to the last fourteen recorded days and an equal preceding window`() {
        val c=Periods.resolve("previous_period",null,null,Instant.parse("2026-12-09T21:14:37Z"),now)
        assertEquals(Period(Instant.parse("2026-11-26T00:00:00Z"),Instant.parse("2026-12-10T00:00:00Z")),c.current)
        assertEquals(Period(Instant.parse("2026-11-12T00:00:00Z"),Instant.parse("2026-11-26T00:00:00Z")),c.baseline);assertFalse(c.partial)
        val explicit=Periods.resolve("previous_period",Instant.parse("2026-12-01T00:00:00Z"),Instant.parse("2026-12-04T00:00:00Z"),null,now)
        assertEquals(Period(Instant.parse("2026-11-28T00:00:00Z"),Instant.parse("2026-12-01T00:00:00Z")),explicit.baseline)
    }
    @Test fun `partial week compares the equivalent elapsed portion of the previous Monday week`() {
        val c=Periods.resolve("week",null,null,Instant.parse("2026-12-09T21:14:37Z"),now)
        assertEquals(Period(Instant.parse("2026-12-07T00:00:00Z"),Instant.parse("2026-12-10T00:00:00Z")),c.current)
        assertEquals(Period(Instant.parse("2026-11-30T00:00:00Z"),Instant.parse("2026-12-03T00:00:00Z")),c.baseline)
        assertTrue(c.partial);assertEquals("equivalent_elapsed_portion",c.basis)
    }
    @Test fun `complete week and month use whole calendar periods with half-open UTC bounds`() {
        val week=Periods.resolve("week",Instant.parse("2026-11-01T00:00:00Z"),Instant.parse("2026-12-07T00:00:00Z"),Instant.parse("2026-12-09T21:00:00Z"),now)
        assertEquals(Period(Instant.parse("2026-11-30T00:00:00Z"),Instant.parse("2026-12-07T00:00:00Z")),week.current);assertEquals(Period(Instant.parse("2026-11-23T00:00:00Z"),Instant.parse("2026-11-30T00:00:00Z")),week.baseline);assertFalse(week.partial)
        val month=Periods.resolve("month",Instant.parse("2026-11-01T00:00:00Z"),Instant.parse("2026-12-01T00:00:00Z"),Instant.parse("2026-12-09T21:00:00Z"),now)
        assertEquals(Period(Instant.parse("2026-11-01T00:00:00Z"),Instant.parse("2026-12-01T00:00:00Z")),month.current);assertEquals(Period(Instant.parse("2026-10-01T00:00:00Z"),Instant.parse("2026-11-01T00:00:00Z")),month.baseline)
    }
    @Test fun `partial month never extends the baseline past the previous month`() {
        val c=Periods.resolve("month",null,null,Instant.parse("2026-03-30T10:00:00Z"),now)
        assertEquals(Period(Instant.parse("2026-03-01T00:00:00Z"),Instant.parse("2026-03-31T00:00:00Z")),c.current)
        assertEquals(Period(Instant.parse("2026-02-01T00:00:00Z"),Instant.parse("2026-03-01T00:00:00Z")),c.baseline);assertTrue(c.partial)
        assertThrows(IllegalArgumentException::class.java){Periods.resolve("quarter",null,null,null,now)}
        assertThrows(IllegalArgumentException::class.java){Periods.resolve("week",Instant.parse("2026-03-01T00:00:00Z"),null,null,now)}
    }
    @Test fun `rates exclude unknown outcomes and never turn a missing denominator into zero`() {
        val r=row(runs=10,success=6,failed=1,cancelled=1,unknown=2,retried=3)
        assertEquals("75",r["success_rate_percent"]);assertEquals("30",r["retry_rate_percent"]);assertEquals(8L,r["concluded_runs"])
        val unlinked=row(runs=4,linked=0,input=0,output=0);assertNull(unlinked["input_tokens_per_run"]);assertNull(unlinked["pricing_coverage_percent"])
        val empty=InsightRules.derive(emptyMap());assertNull(empty["success_rate_percent"]);assertNull(empty["retry_rate_percent"]);assertNull(empty["average_duration_seconds"])
        assertNull(row(runs=3,success=0,unknown=3)["success_rate_percent"])
        val none=InsightRules.empty();assertEquals(0L,none["runs"]);assertEquals(0L,none["concluded_runs"]);assertNull(none["success_rate_percent"]);assertNull(none["input_tokens_per_run"])
    }
    @Test fun `a valid retry spike is detected with evidence equal to the aggregates`() {
        val found=InsightRules.detect(row(150,retried=12),row(160,retried=34),mapOf("current" to mapOf("timeout" to 30L)),t).single()
        assertEquals("retry_increase",found["type"]);assertEquals("8",found["baseline"]);assertEquals("21.25",found["current"]);assertEquals("13.25",found["absolute_change"]);assertEquals("warning",found["severity"]);assertEquals("sufficient",found["evidence_quality"])
        val evidence=found["evidence"] as Map<*,*>;assertEquals(34,(evidence["current"] as Map<*,*>)["retried_runs"]);assertEquals(12,(evidence["baseline"] as Map<*,*>)["retried_runs"]);assertEquals(mapOf("timeout" to 30L),(evidence["current"] as Map<*,*>)["failed_attempts_by_error"])
        assertEquals(mapOf("baseline_runs" to 150L,"current_runs" to 160L,"basis" to "runs"),found["sample_size"])
    }
    @Test fun `changes below threshold and volume growth alone produce no finding`() {
        assertEquals(emptyList<Any>(),types(row(100,retried=8),row(100,retried=17)))
        assertEquals(emptyList<Any>(),types(row(84,success=80,failed=4),row(196,success=187,failed=9)))
        assertEquals(emptyList<Any>(),types(row(100,success=94,failed=6),row(100,success=85,failed=15)))
    }
    @Test fun `success deterioration is detected and doubles to critical`() {
        val warning=InsightRules.detect(row(100,success=94,failed=6),row(100,success=80,failed=15,cancelled=5),emptyMap(),t).single()
        assertEquals("success_rate_decline",warning["type"]);assertEquals("-14",warning["absolute_change"]);assertEquals("warning",warning["severity"])
        assertEquals("critical",InsightRules.detect(row(100,success=94,failed=6),row(100,success=70,failed=30),emptyMap(),t).single()["severity"])
        // Running/unknown runs are not failures: 20 unknown runs do not lower the rate.
        assertEquals(emptyList<Any>(),types(row(100,success=94,failed=6),row(120,success=94,failed=6,unknown=20)))
    }
    @Test fun `token spikes are normalised per linked run`() {
        assertEquals(emptyList<Any>(),types(row(50),row(150)))
        assertEquals(listOf("output_token_spike"),types(row(50),row(50,output=7000)))
        assertEquals(listOf("input_token_spike"),types(row(50),row(50,input=65000)))
        // Zero baseline tokens: no infinite percentage, no finding.
        assertEquals(emptyList<Any>(),types(row(50,input=0,output=0),row(50)))
    }
    @Test fun `duration uses the median`() {
        val found=InsightRules.detect(row(40,median="40"),row(40,median="60"),emptyMap(),t).single()
        assertEquals("duration_increase",found["type"]);assertEquals("50",found["percent_change"])
    }
    @Test fun `sparse limited and missing baselines never yield a confident anomaly`() {
        assertEquals(emptyList<Any>(),types(row(3),row(3,retried=2)));assertEquals("insufficient_data",InsightRules.quality(3,3,t))
        val limited=InsightRules.detect(row(18,retried=1),row(14,retried=6),emptyMap(),t).single();assertEquals("info",limited["severity"]);assertEquals("limited_sample",limited["evidence_quality"])
        assertTrue(limited["quality_reason"].toString().startsWith("14 current and 18 comparison runs"))
        assertEquals(emptyList<Any>(),types(InsightRules.derive(emptyMap()),row(200,retried=100)));assertEquals("unsupported_comparison",InsightRules.quality(0,200,t));assertEquals("no_data",InsightRules.quality(0,0,t))
        assertTrue(InsightRules.reason("insufficient_data",3,3,"runs",t).startsWith("Insufficient data"))
    }
    @Test fun `rate-only scenario re-rates identical tokens exactly and is absent when unsupported`() {
        val rates=listOf(mapOf("provider" to "anthropic","model" to "claude-sonnet-4-6","pricing_tier" to "std","input_rate" to "3","cached_input_rate" to "0.3","output_rate" to "15"),mapOf("provider" to "openai","model" to "gpt-5.4-mini","pricing_tier" to "std","input_rate" to "0.75","cached_input_rate" to "0.075","output_rate" to "4.5"),mapOf("provider" to "google","model" to "other-tier","pricing_tier" to "batch","input_rate" to "0.01","cached_input_rate" to "0.01","output_rate" to "0.01"))
        val model=mapOf("pricing_provider" to "anthropic","pricing_model" to "claude-sonnet-4-6","pricing_tier" to "std","pricing_profiles" to 1,"priced_events" to 2,"priced_input_tokens" to "100000","priced_cached_input_tokens" to "20000","priced_output_tokens" to "10000","modeled_cost" to "0.396")
        val s=InsightRules.rateScenario(model,rates)!!
        assertEquals("openai/gpt-5.4-mini",s["alternative_pricing_model"]);assertEquals("0.1065",s["modeled_cost_at_alternative_rates"]);assertEquals("0.2895",s["modeled_difference"]);assertEquals("Hypothetical rate-only comparison",s["label"])
        assertNull(InsightRules.rateScenario(model+mapOf("pricing_profiles" to 2),rates));assertNull(InsightRules.rateScenario(model+mapOf("modeled_cost" to "0.05"),rates));assertNull(InsightRules.rateScenario(model-"pricing_provider",rates))
    }
    @Test fun `threshold configuration is validated and exposed once`() {
        assertEquals("10",t.toMap()["retry_rate_increase_points"]);assertEquals(20,t.toMap()["min_runs"])
        assertThrows(IllegalArgumentException::class.java){InsightThresholds(minRuns=5,minRunsLimited=8)}
        assertThrows(IllegalArgumentException::class.java){InsightThresholds(criticalMultiplier=BigDecimal.ONE)}
        val strict=InsightThresholds(retryRateIncreasePoints=BigDecimal(20));assertEquals(emptyList<Any>(),InsightRules.detect(row(150,retried=12),row(160,retried=34),emptyMap(),strict))
    }
    @Test fun `scenario generator is deterministic and independent of the clock`(@TempDir dir:Path) {
        val mapper=ObjectMapper();val org="00000000-0000-0000-0000-0000000000aa"
        val projects=listOf("developer-productivity","fraud-detection","customer-analytics","knowledge-automation").mapIndexed{i,slug->mapOf("id" to "00000000-0000-0000-0000-00000000010$i","organization_id" to org,"slug" to slug,"status" to "active")}
        val users=(1..3).map{mapOf("id" to "00000000-0000-0000-0000-00000000020$it","organization_id" to org,"job_function" to "Engineering")}
        val snapshot=mapper.valueToTree<com.fasterxml.jackson.databind.JsonNode>(mapOf("organizations" to listOf(mapOf("id" to org,"slug" to "aperture-technologies")),"projects" to projects,"users" to users,
            "memberships" to projects.flatMap{p->users.map{u->mapOf("organization_id" to org,"user_id" to u["id"],"project_id" to p["id"],"joined_at" to "2026-11-01T00:00:00Z","left_at" to null)}}))
        val generator=AgentInsightScenarioGenerator(mapper,SyntheticGenerator(mapper))
        val first=generator.generate(snapshot,dir.resolve("a.csv"),dir.resolve("a.jsonl"),42);val second=generator.generate(snapshot,dir.resolve("b.csv"),dir.resolve("b.jsonl"),42)
        assertEquals(Files.readString(dir.resolve("a.csv")),Files.readString(dir.resolve("b.csv")));assertEquals(first["executions_sha256"],second["executions_sha256"]);assertEquals(1630,first["runs"])
        assertNotEquals(first["executions_sha256"],generator.generate(snapshot,dir.resolve("c.csv"),dir.resolve("c.jsonl"),43)["executions_sha256"])
        val records=Files.readAllLines(dir.resolve("a.jsonl")).map(mapper::readTree);assertTrue(records.all{it["outcome_source"].asText()=="synthetic_fixture"&&it["started_at"].asText()>="2026-11-12"&&it["started_at"].asText()<"2026-12-10"})
        assertEquals(6,records.count{it["agent"]["key"].asText()=="incident-scribe"})
    }
}
