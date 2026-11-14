package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.domain.sha256
import com.tokentrack.usage.generation.SyntheticGenerator
import org.springframework.stereotype.Component
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Slice 9B demonstration data. Writes an additive usage CSV v1 file and a matching execution JSONL v1 sidecar for the
 * separate stable source `demo-agent-insights-v1`; nothing already imported is rewritten. Dates are fixed
 * (2026-11-12..2026-12-10 UTC, behaviour changing at 2026-11-26) and every draw is a hash of the seed, so output is
 * byte-reproducible and independent of the wall clock. Outcomes are simulated and labelled `synthetic_fixture`.
 */
@Component
class AgentInsightScenarioGenerator(private val mapper:ObjectMapper,private val csv:SyntheticGenerator) {
    companion object { const val SOURCE="demo-agent-insights-v1";val FROM:LocalDate=LocalDate.parse("2026-11-12");val CHANGE:LocalDate=LocalDate.parse("2026-11-26");val TO:LocalDate=LocalDate.parse("2026-12-10") }
    /** Per-period knobs: runs per day, success/retry probability (per mille), tokens per run and share of the alternate model. */
    data class Phase(val perDay:Int,val success:Int,val retry:Int,val input:Long,val output:Long,val alternate:Int=0)
    data class Scenario(val key:String,val name:String,val workflow:String,val project:String,val model:Pair<String,String>,val alternateModel:Pair<String,String>?,val baseline:Phase,val current:Phase,val description:String,val days:Set<Int>?=null,val retryInputPercent:Int=100)
    val scenarios=listOf(
        Scenario("pr-review-assistant","PR Review Assistant","code-review","developer-productivity","openai" to "gpt-5.4-mini",null,Phase(12,920,80,40000,3000),Phase(12,920,260,40000,3000),"Scenario A: retry rate rises between periods",retryInputPercent=150),
        Scenario("test-triage-agent","Test Triage Agent","test-triage","fraud-detection","anthropic" to "claude-haiku-4-5",null,Phase(10,940,60,30000,2500),Phase(10,720,60,30000,2500),"Scenario B: success rate deteriorates"),
        Scenario("release-notes-writer","Release Notes Writer","documentation","customer-analytics","openai" to "gpt-5.4",null,Phase(8,930,50,20000,2000),Phase(8,930,50,20000,3100),"Scenario C: output tokens per run grow"),
        Scenario("support-summarizer","Support Summarizer","summarization","knowledge-automation","openai" to "gpt-5.4-mini","anthropic" to "claude-sonnet-4-6",Phase(10,930,50,30000,2500,150),Phase(10,930,50,30000,2500,650),"Scenario D: priced model mix changes"),
        Scenario("docs-indexer","Docs Indexer","indexing","developer-productivity","google" to "gemini-2.5-flash",null,Phase(6,950,40,50000,1500),Phase(14,950,40,50000,1500),"Scenario E: more runs at stable per-run efficiency"),
        Scenario("legacy-migration-helper","Legacy Migration Helper","migration","fraud-detection","openai" to "gpt-5.4-mini","local" to "experimental-unpriced-v1",Phase(8,920,60,30000,2500,300),Phase(8,920,60,45000,2500,300),"Scenario F: part of the usage has no pricing profile"),
        Scenario("incident-scribe","Incident Scribe","incident-response","developer-productivity","anthropic" to "claude-haiku-4-5",null,Phase(1,1000,0,20000,2000),Phase(1,1000,670,20000,2000),"Scenario G: too few runs to compare",days=setOf(3,7,11,17,21,25))
    )
    fun generate(snapshot:JsonNode,usageOutput:Path,executionsOutput:Path,seed:Long):Map<String,Any> {
        val org=snapshot.path("organizations").first{it.path("slug").asText()=="aperture-technologies"}.path("id").asText()
        val projects=snapshot.path("projects").filter{it.path("organization_id").asText()==org}.associate{it.path("slug").asText() to it.path("id").asText()}
        val from=FROM.atStartOfDay(ZoneOffset.UTC).toInstant();val to=TO.atStartOfDay(ZoneOffset.UTC).toInstant()
        val engineers=snapshot.path("users").filter{it.path("organization_id").asText()==org&&it.path("job_function").asText()=="Engineering"}.map{it.path("id").asText()}.toSet()
        // Only people whose recorded membership covers the whole simulated window; membership is never invented or backdated.
        fun members(project:String)=snapshot.path("memberships").filter{it.path("project_id").asText()==project&&Instant.parse(it.path("joined_at").asText())<=from&&(it.path("left_at").isNull||Instant.parse(it.path("left_at").asText())>=to)}.map{it.path("user_id").asText()}.distinct().sortedWith(compareBy<String>{it !in engineers}.thenBy{it}).take(3)
        fun draw(vararg parts:Any)=(sha256("insight-scenarios-v1/$seed/${parts.joinToString("/")}").take(8).toLong(16)%1000).toInt()
        val usage=mutableListOf<Map<String,String>>();val executions=mutableListOf<String>();val perScenario=linkedMapOf<String,Int>()
        for(s in scenarios) {
            val project=projects.getValue(s.project);val users=members(project);require(users.isNotEmpty()){"Snapshot has no member covering the window for ${s.project}"}
            val definition=mapOf("key" to s.key,"name" to s.name,"description" to "Deterministic Slice 9B demo agent. ${s.description}.","workflow_type" to s.workflow,"owner_user_id" to users.first(),"project_id" to project,"status" to "active")
            var day=FROM;var count=0
            while(day<TO) {
                val index=java.time.temporal.ChronoUnit.DAYS.between(FROM,day).toInt();val phase=if(day<CHANGE)s.baseline else s.current
                if(s.days==null||index in s.days) repeat(phase.perDay) { i->
                    val id="ins-${s.key}-${day.toString().replace("-","")}-${i.toString().padStart(3,'0')}"
                    val started=day.atStartOfDay(ZoneOffset.UTC).toInstant().plusSeconds(8*3600L+i*(36000L/phase.perDay)+draw(id,"offset")%120)
                    val outcomeDraw=draw(id,"outcome");val outcome=if(outcomeDraw<phase.success)"success" else if(outcomeDraw<phase.success+(1000-phase.success)*3/4)"failure" else "cancelled"
                    val retryDraw=draw(id,"retry");val retries=if(retryDraw<phase.retry/6)2 else if(retryDraw<phase.retry)1 else 0
                    val alternate=s.alternateModel!=null&&draw(id,"model")<phase.alternate;val (provider,model)=if(alternate)s.alternateModel!! else s.model
                    val jitter=900+draw(id,"tokens")%200;val input=phase.input*jitter/1000*(if(retries>0)s.retryInputPercent else 100)/100;val output=phase.output*(900+draw(id,"output")%200)/1000
                    val completed=started.plusSeconds(40L+draw(id,"duration")%30+retries*12)
                    val error=listOf("timeout","provider_error","tool_execution_error")[draw(id,"error")%3]
                    val attempts=(0..retries).map { n->val aStart=started.plusSeconds(n*12L);val last=n==retries
                        mapOf("attempt_id" to "$id-a${n+1}","attempt_number" to n+1,"started_at" to aStart.toString(),"completed_at" to (if(last)completed else aStart.plusSeconds(10)).toString(),"status" to if(!last||outcome=="failure")"failed" else if(outcome=="cancelled")"cancelled" else "succeeded","error_category" to if(!last||outcome=="failure")error else null) }
                    val user=users[draw(id,"user")%users.size]
                    val fields=mapOf("schema_version" to "1","organization_id" to org,"user_id" to user,"project_id" to project,"provider" to provider,"model" to model,"tool" to "${s.workflow}-agent","input_tokens" to input.toString(),"cached_input_tokens" to (input/5).toString(),"output_tokens" to output.toString(),"occurred_at" to started.plusSeconds(15).toString(),"workflow_type" to s.workflow,"agent_run_id" to id)
                    usage+=fields+mapOf("event_id" to "ins-evt-${sha256("$seed/$id").take(20)}")
                    executions+=mapper.writeValueAsString(mapOf("schema_version" to 1,"source" to SOURCE,"organization_id" to org,"run_id" to id,"agent" to definition,"user_id" to user,"project_id" to project,"started_at" to started.toString(),"completed_at" to completed.toString(),"status" to mapOf("success" to "completed","failure" to "failed","cancelled" to "cancelled").getValue(outcome),"outcome" to outcome,"outcome_source" to "synthetic_fixture","attempts" to attempts))
                    count++
                }
                day=day.plusDays(1)
            }
            perScenario[s.key]=count
        }
        csv.write(usageOutput,usage);executionsOutput.toAbsolutePath().parent?.let(Files::createDirectories);Files.writeString(executionsOutput,executions.joinToString("\n",postfix="\n"))
        return mapOf("schema_version" to 1,"source" to SOURCE,"seed" to seed,"window" to mapOf("from" to FROM.toString(),"behaviour_change" to CHANGE.toString(),"to" to TO.toString()),"runs" to executions.size,"usage_events" to usage.size,"scenarios" to perScenario,
            "correction_run_id" to "ins-docs-indexer-20261126-000","usage_output" to usageOutput.toString(),"executions_output" to executionsOutput.toString(),"executions_sha256" to sha256(executions.joinToString("\n",postfix="\n")))
    }
}
