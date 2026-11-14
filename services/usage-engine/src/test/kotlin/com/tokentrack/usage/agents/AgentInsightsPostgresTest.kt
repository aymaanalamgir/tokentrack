package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.transaction.annotation.Transactional
import java.time.Instant
import java.util.UUID

/** Real PostgreSQL. Every test inserts its own tenant inside a rolled-back transaction. */
@Tag("postgres") @Transactional
@SpringBootTest(properties=["spring.main.web-application-type=none"])
class AgentInsightsPostgresTest {
    companion object {
        @JvmStatic @DynamicPropertySource fun database(r:DynamicPropertyRegistry) {
            val name=requireNotNull(System.getenv("USAGE_TEST_DB_NAME"));require(name!=System.getenv("DB_NAME"))
            r.add("spring.datasource.url"){"jdbc:postgresql://${System.getenv("DB_HOST")?:"localhost"}:${System.getenv("DB_PORT")?:"5432"}/$name?currentSchema=usage&connectTimeout=3&socketTimeout=30"}
            r.add("spring.datasource.driver-class-name"){"org.postgresql.Driver"}
        }
    }
    @Autowired lateinit var jdbc:JdbcTemplate
    @Autowired lateinit var mapper:ObjectMapper
    @Autowired lateinit var analytics:AgentAnalytics
    @Autowired lateinit var insights:AgentInsights
    private val org=UUID.randomUUID();private val other=UUID.randomUUID();private val user=UUID.randomUUID();private val colleague=UUID.randomUUID();private val project=UUID.randomUUID();private val source="insights-postgres"
    private val fp="a".repeat(64)
    private fun definition(tenant:UUID,key:String):UUID { val id=UUID.randomUUID();jdbc.update("INSERT INTO usage.agent_definitions(id,organization_id,source,agent_key,name,description,workflow_type,owner_user_id,project_id,status,fingerprint) VALUES (?,?,?,?,?,?,?,?,?,'active',?)",id,tenant,source,key,key,"test","code-review",user,project,fp);return id }
    /** Inserts [count] runs spread evenly over [from, from+days). The first [retried] have a failed first attempt; outcomes fill success, failure, cancelled, then unknown. */
    private fun runs(tenant:UUID,agent:UUID,prefix:String,count:Int,from:String,days:Int,retried:Int=0,failed:Int=0,cancelled:Int=0,unknown:Int=0,by:UUID=user,seconds:Int=40) {
        jdbc.update("""INSERT INTO usage.agent_runs(id,organization_id,agent_definition_id,source,external_run_id,user_id,project_id,started_at,completed_at,status,outcome,outcome_source,fingerprint)
            SELECT md5(?||g)::uuid,?,?,?,?||'-'||g,?,?,s,CASE WHEN o='unknown' THEN NULL ELSE s+make_interval(secs=>?) END,CASE o WHEN 'success' THEN 'completed' WHEN 'failure' THEN 'failed' WHEN 'cancelled' THEN 'cancelled' ELSE 'running' END,o,'observed',?
            FROM (SELECT g,?::timestamptz+(g-1)*make_interval(secs=>?::float8/?) s,CASE WHEN g<=? THEN 'failure' WHEN g<=? THEN 'cancelled' WHEN g<=? THEN 'unknown' ELSE 'success' END o FROM generate_series(1,?) g) x""",
            "$tenant/$prefix",tenant,agent,source,prefix,by,project,seconds,fp,from,days*86400,count,failed,failed+cancelled,failed+cancelled+unknown,count)
        jdbc.update("""INSERT INTO usage.agent_attempts(id,organization_id,agent_run_id,external_attempt_id,attempt_number,started_at,completed_at,status,error_category,fingerprint)
            SELECT gen_random_uuid(),r.organization_id,r.id,r.external_run_id||'-a'||n,n,r.started_at,r.started_at+interval '5 seconds',CASE WHEN n=1 AND split_part(r.external_run_id,'-',-1)::int>?-? THEN 'failed' ELSE 'succeeded' END,CASE WHEN n=1 AND split_part(r.external_run_id,'-',-1)::int>?-? THEN 'timeout' END,?
            FROM usage.agent_runs r CROSS JOIN generate_series(1,2) n WHERE r.organization_id=? AND r.external_run_id LIKE ?||'-%' AND (n=1 OR split_part(r.external_run_id,'-',-1)::int>?-?)""",count,retried,count,retried,fp,tenant,prefix,count,retried)
    }
    private fun usage(tenant:UUID,prefix:String,input:Int,output:Int) {
        val batch=UUID.randomUUID();jdbc.update("INSERT INTO usage.import_batches(id,source,input_label,status,completed_at,total_rows,accepted_rows,scan_complete) VALUES (?,?,?,'completed',now(),1,1,true)",batch,source,"test.csv")
        jdbc.update("""INSERT INTO usage.usage_events(id,organization_id,source,event_id,user_id,project_id,provider,model,tool,input_tokens,output_tokens,cached_input_tokens,occurred_at,agent_run_id,workflow_type,import_batch_id,schema_version,payload_fingerprint)
            SELECT gen_random_uuid(),organization_id,source,'evt-'||external_run_id,user_id,project_id,'openai','demo-code-v1','agent',?,?,0,started_at+interval '1 second',external_run_id,'code-review',?,1,? FROM usage.agent_runs WHERE organization_id=? AND external_run_id LIKE ?||'-%'""",input,output,batch,fp,tenant,prefix)
    }
    private fun body(tenant:UUID=org,start:String?="2026-11-01T00:00:00Z",end:String?="2026-12-01T00:00:00Z",extra:Map<String,Any?> =emptyMap(),all:Boolean=true,users:List<UUID> =emptyList(),agent:UUID?=null):ObjectNode=mapper.valueToTree(
        mapOf("organization_id" to tenant.toString(),"all_users" to all,"scope_users" to users.map{it.toString()},"scope_projects" to emptyList<String>(),"filter_users" to null,"start" to start,"end" to end,"agent_id" to agent?.toString(),"run_id" to null,"project_id" to null,"user_id" to null,"workflow_type" to null,"status" to null,"outcome" to null,"retried" to null)+extra)
    private fun cohort(base:ObjectNode,batch:Int=1000):Pair<List<Map<String,Any?>>,Int> {
        val all=mutableListOf<Map<String,Any?>>();var cursor=mapOf<String,Any?>("after_started_at" to null,"after_id" to null);var pages=0
        while(true) { val page=analytics.cohort(mapper.valueToTree<ObjectNode>(mapper.convertValue(base,Map::class.java)+cursor+mapOf("batch" to batch,"bucket" to "day")));pages++
            @Suppress("UNCHECKED_CAST") val rows=page["rows"] as List<Map<String,Any?>>;assertTrue(rows.size<=batch);all+=rows
            @Suppress("UNCHECKED_CAST") cursor=(page["next"] as Map<String,Any?>?)?:break }
        return all to pages
    }
    private fun <T> timed(label:String,work:()->T):T { val start=System.nanoTime();val result=work();println("PERF $label: ${(System.nanoTime()-start)/1_000_000} ms");return result }

    @Test fun `cohorts above the former 5000-run cap are reported and paged completely without truncation`() {
        val agent=definition(org,"big");runs(org,agent,"big",6200,"2026-11-01T00:00:00Z",28,retried=620,failed=310,unknown=62);usage(org,"big",1000,100)
        runs(other,definition(other,"foreign"),"foreign",50,"2026-11-01T00:00:00Z",28)
        // Autovacuum keeps statistics current on a live database; rows inserted inside this transaction need an explicit ANALYZE.
        listOf("agent_runs","agent_attempts","usage_events").forEach{jdbc.execute("ANALYZE usage.$it")}
        val report=timed("overview report 6200 runs"){analytics.report(mapper.valueToTree<ObjectNode>(mapper.convertValue(body(),Map::class.java)+mapOf("limit" to 25,"offset" to 0)))}
        val totals=report["totals"] as Map<*,*>;assertEquals(6200L,totals["runs"]);assertEquals(620L,totals["retried_runs"]);assertEquals("10.000000",totals["retry_rate_percent"]);assertFalse(report.containsKey("cohort_runs"));assertEquals(25,((report["runs"] as Map<*,*>)["rows"] as List<*>).size)
        val (rows,pages)=timed("cohort walk 6200 runs in 1000-run pages"){cohort(body())}
        assertEquals(7,pages);assertEquals(6200,rows.size);assertEquals(6200,rows.map{it["run_id"]}.toSet().size);assertEquals(620,rows.count{it["retried"]==true});assertEquals(310,rows.count{it["outcome"]=="failure"})
        assertTrue(rows.none{it["run_id"].toString().startsWith("foreign")})
        val result=timed("insights 6200 runs"){insights.report(body(start="2026-11-15T00:00:00Z",end="2026-11-29T00:00:00Z",extra=mapOf("compare" to "previous_period")))}
        val both=(result["totals"] as Map<*,*>);assertEquals(6200L,((both["current"] as Map<*,*>)["runs"] as Number).toLong()+((both["baseline"] as Map<*,*>)["runs"] as Number).toLong())
        println("PLAN "+jdbc.queryForList("EXPLAIN SELECT r.id FROM usage.agent_runs r WHERE r.organization_id=? AND r.started_at>=? AND r.started_at<? AND (r.started_at,r.id)>(?,?) ORDER BY r.started_at,r.id LIMIT 1000",org,java.sql.Timestamp.from(Instant.parse("2026-11-01T00:00:00Z")),java.sql.Timestamp.from(Instant.parse("2026-12-01T00:00:00Z")),java.sql.Timestamp.from(Instant.parse("2026-11-10T00:00:00Z")),UUID.randomUUID()).joinToString(" | "){it.values.first().toString()})
    }
    @Test fun `weekly comparison detects a retry spike from recorded attempts and ignores other tenants and scopes`() {
        val agent=definition(org,"review");runs(org,agent,"prev",150,"2026-11-23T00:00:00Z",7,retried=12);runs(org,agent,"cur",160,"2026-11-30T00:00:00Z",7,retried=34,failed=8,cancelled=2,unknown=5)
        val quiet=definition(org,"quiet");runs(org,quiet,"qprev",40,"2026-11-23T00:00:00Z",7,by=colleague);runs(org,quiet,"qcur",120,"2026-11-30T00:00:00Z",7,by=colleague)
        runs(other,definition(other,"foreign"),"fcur",500,"2026-11-30T00:00:00Z",7,retried=400)
        val result=insights.report(body(start="2026-11-01T00:00:00Z",end="2026-12-07T00:00:00Z",extra=mapOf("compare" to "week")),Instant.parse("2027-01-01T00:00:00Z"))
        assertEquals(mapOf("start" to "2026-11-30T00:00:00Z","end" to "2026-12-07T00:00:00Z"),result["current_period"]);assertEquals(mapOf("start" to "2026-11-23T00:00:00Z","end" to "2026-11-30T00:00:00Z"),result["comparison_period"]);assertEquals(false,result["partial_current_period"])
        @Suppress("UNCHECKED_CAST") val found=result["insights"] as List<Map<String,Any?>>
        val retry=found.single{it["type"]=="retry_increase"};assertEquals(agent.toString(),retry["agent_id"]);assertEquals("8",retry["baseline"]);assertEquals("21.25",retry["current"])
        assertEquals(mapOf("timeout" to 34L),((retry["evidence"] as Map<*,*>)["current"] as Map<*,*>)["failed_attempts_by_error"])
        // Volume tripled for the quiet agent at identical per-run behaviour: not an inefficiency.
        assertTrue(found.none{it["agent_id"]==quiet.toString()})
        @Suppress("UNCHECKED_CAST") val agents=result["agents"] as List<Map<String,Any?>>;assertEquals(2,agents.size)
        val current=agents.single{it["id"]==agent.toString()}["current"] as Map<*,*>;assertEquals(160L,current["runs"]);assertEquals(5L,current["incomplete_runs"]);assertEquals(2L,current["cancelled_runs"]);assertEquals(155L,current["concluded_runs"]);assertEquals("93.5484",current["success_rate_percent"])
        // Employee-style population: only the colleague's runs are visible, so the retry finding is not derivable.
        val scoped=insights.report(body(start="2026-11-01T00:00:00Z",end="2026-12-07T00:00:00Z",extra=mapOf("compare" to "week"),all=false,users=listOf(colleague)),Instant.parse("2027-01-01T00:00:00Z"))
        assertEquals(listOf(quiet.toString()),(scoped["agents"] as List<*>).map{(it as Map<*,*>)["id"]});assertEquals(emptyList<Any>(),scoped["insights"])
        assertEquals(false,insights.report(body(extra=mapOf("compare" to "week"),all=false,users=listOf(colleague),agent=agent))["agent_visible"]);assertEquals(true,insights.report(body(extra=mapOf("compare" to "week"),agent=agent))["agent_visible"])
    }
    @Test fun `monthly partial period, token normalisation, sparse data and missing baseline`() {
        val agent=definition(org,"writer");runs(org,agent,"nov",60,"2026-11-01T00:00:00Z",9);usage(org,"nov",1000,100);runs(org,agent,"dec",90,"2026-12-01T00:00:00Z",9);usage(org,"dec",1000,160)
        val sparse=definition(org,"sparse");runs(org,sparse,"snov",3,"2026-11-01T00:00:00Z",9);runs(org,sparse,"sdec",3,"2026-12-01T00:00:00Z",9,retried=2)
        val fresh=definition(org,"fresh");runs(org,fresh,"fdec",80,"2026-12-01T00:00:00Z",9,retried=40)
        val result=insights.report(body(start=null,end=null,extra=mapOf("compare" to "month")),Instant.parse("2027-01-01T00:00:00Z"))
        assertEquals(mapOf("start" to "2026-12-01T00:00:00Z","end" to "2026-12-10T00:00:00Z"),result["current_period"]);assertEquals(mapOf("start" to "2026-11-01T00:00:00Z","end" to "2026-11-10T00:00:00Z"),result["comparison_period"]);assertEquals(true,result["partial_current_period"]);assertEquals("equivalent_elapsed_portion",result["comparison_basis"])
        @Suppress("UNCHECKED_CAST") val found=result["insights"] as List<Map<String,Any?>>;@Suppress("UNCHECKED_CAST") val agents=(result["agents"] as List<Map<String,Any?>>).associateBy{it["agent_key"]}
        val spike=found.single();assertEquals("output_token_spike",spike["type"]);assertEquals(agent.toString(),spike["agent_id"]);assertEquals("100",spike["baseline"]);assertEquals("160",spike["current"]);assertEquals("60",spike["percent_change"])
        assertEquals("insufficient_data",agents.getValue("sparse")["evidence_state"]);assertEquals("unsupported_comparison",agents.getValue("fresh")["evidence_state"]);assertEquals("sufficient",agents.getValue("writer")["evidence_state"])
        assertEquals(result,insights.report(body(start=null,end=null,extra=mapOf("compare" to "month")),Instant.parse("2027-01-01T00:00:00Z")))
        assertThrows(IllegalArgumentException::class.java){insights.report(body(extra=mapOf("compare" to "decade")))}
    }
    @Test fun `retried drill-down filter matches recorded attempts`() {
        val agent=definition(org,"drill");runs(org,agent,"d",30,"2026-11-10T00:00:00Z",5,retried=7)
        assertEquals(7,cohort(body(extra=mapOf("retried" to true))).first.size);assertEquals(23,cohort(body(extra=mapOf("retried" to false))).first.size);assertEquals(30,cohort(body(),batch=4).first.size)
    }
}
