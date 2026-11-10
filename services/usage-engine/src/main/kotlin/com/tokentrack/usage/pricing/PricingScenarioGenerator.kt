package com.tokentrack.usage.pricing

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.domain.sha256
import com.tokentrack.usage.generation.SyntheticGenerator
import org.springframework.stereotype.Component
import java.nio.file.Path
import java.time.Instant
import java.util.TreeMap

@Component
class PricingScenarioGenerator(private val mapper:ObjectMapper,private val csv:SyntheticGenerator) {
    fun generate(snapshot:JsonNode,output:Path):Map<String,Any> {
        val org=snapshot.path("organizations").first { it.path("slug").asText()=="aperture-technologies" }.path("id").asText()
        val projects=snapshot.path("projects").filter { it.path("organization_id").asText()==org }.associateBy { it.path("slug").asText() }
        val fraud=projects.getValue("fraud-detection").path("id").asText()
        val dev=projects.getValue("developer-productivity").path("id").asText()
        val at=Instant.parse("2026-11-15T14:30:00Z")
        val periods=snapshot.path("memberships").filter { it.path("organization_id").asText()==org && Instant.parse(it.path("joined_at").asText())<=at && (it.path("left_at").isNull || Instant.parse(it.path("left_at").asText())>at) }.groupBy { it.path("user_id").asText() }
        val user=snapshot.path("users").filter { it.path("organization_id").asText()==org && it.path("job_function").asText()=="Engineering" && periods[it.path("id").asText()].orEmpty().map { p->p.path("project_id").asText() }.containsAll(listOf(fraud,dev)) }.sortedBy { it.path("id").asText() }.firstOrNull() ?: error("Snapshot needs a shared engineer with recorded Fraud/Developer Productivity memberships")
        fun row(name:String,provider:String,model:String,input:String="10000",cached:String="2000",out:String="2000",time:String="2026-11-15T14:30:00Z"):Map<String,String> {
            val fields=mapOf("schema_version" to "1","organization_id" to org,"user_id" to user.path("id").asText(),"project_id" to fraud,"provider" to provider,"model" to model,"tool" to "coding-assistant","input_tokens" to input,"cached_input_tokens" to cached,"output_tokens" to out,"occurred_at" to time,"workflow_type" to "pricing-scenario","agent_run_id" to "")
            return fields+mapOf("event_id" to "scenario-$name-${sha256(mapper.writeValueAsString(TreeMap(fields))).take(12)}")
        }
        val rows=listOf(row("mini-uncached","openai","gpt-5.4-mini","100000","0","10000"),row("mini-cached","openai","gpt-5.4-mini","100000","20000","10000"),
            row("sonnet","anthropic","claude-sonnet-4-6","100000","20000","10000"),row("haiku","anthropic","claude-haiku-4-5"),row("gpt54","openai","gpt-5.4"),row("gemini","google","gemini-2.5-flash"),
            row("change-before","synthetic","effective-change-example","10000","0","1000"),row("change-after","synthetic","effective-change-example","10000","0","1000","2026-11-25T14:30:00Z"),
            row("unknown","openai","unconfigured-model"),row("cache-writes","synthetic","cache-write-example"))
        csv.write(output,rows)
        return mapOf("rows" to rows.size,"organization_id" to org,"shared_engineer_id" to user.path("id").asText(),"project_id" to fraud,"source" to "demo-pricing-scenarios-v1","output" to output.toString())
    }
}
