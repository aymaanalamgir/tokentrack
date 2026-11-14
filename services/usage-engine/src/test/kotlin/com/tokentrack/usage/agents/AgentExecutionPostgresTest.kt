package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.references.ReferenceResolver
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.support.TransactionTemplate
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

@Tag("postgres") @Transactional
@SpringBootTest(properties=["spring.main.web-application-type=none"])
class AgentExecutionPostgresTest {
    companion object {
        @JvmStatic @DynamicPropertySource fun database(r:DynamicPropertyRegistry) {
            val name=requireNotNull(System.getenv("USAGE_TEST_DB_NAME"));require(name!=System.getenv("DB_NAME"))
            r.add("spring.datasource.url"){"jdbc:postgresql://${System.getenv("DB_HOST")?:"localhost"}:${System.getenv("DB_PORT")?:"5432"}/$name?currentSchema=usage&connectTimeout=3&socketTimeout=3"}
            r.add("spring.datasource.driver-class-name"){"org.postgresql.Driver"}
        }
    }
    @Autowired lateinit var jdbc:JdbcTemplate
    @Autowired lateinit var mapper:ObjectMapper
    @Autowired lateinit var manager:PlatformTransactionManager
    @TempDir lateinit var temp:Path
    private val org=UUID.randomUUID();private val user=UUID.randomUUID();private val project=UUID.randomUUID();private val source="agent-postgres"
    private fun record(outcome:String="success"):Map<String,Any?> {
        val status=if(outcome=="success")"completed" else "failed";val attemptStatus=if(outcome=="success")"succeeded" else "failed"
        return mapOf("schema_version" to 1,"source" to source,"organization_id" to org.toString(),"run_id" to "run-1","agent" to mapOf("key" to "review-${project.toString().take(8)}","name" to "Review","description" to "test","workflow_type" to "code-review","owner_user_id" to user.toString(),"project_id" to project.toString(),"status" to "active"),"user_id" to user.toString(),"project_id" to project.toString(),"started_at" to "2026-11-15T14:00:00Z","completed_at" to "2026-11-15T14:00:42Z","status" to status,"outcome" to outcome,"outcome_source" to "observed","attempts" to listOf(mapOf("attempt_id" to "run-1-a1","attempt_number" to 1,"started_at" to "2026-11-15T14:00:00Z","completed_at" to "2026-11-15T14:00:42Z","status" to attemptStatus,"error_category" to if(outcome=="success")null else "provider_error")))
    }
    private fun file(value:Map<String,Any?>,name:String):Path=temp.resolve(name).also{Files.writeString(it,mapper.writeValueAsString(value)+"\n")}
    private fun service()=AgentExecutionService(jdbc,TransactionTemplate(manager),mapper,ReferenceResolver{refs->refs.associate{it.key() to null}})
    @Test fun `imports links replays and conflicts without changing usage`() {
        val batch=UUID.randomUUID();jdbc.update("INSERT INTO usage.import_batches(id,source,input_label,status,completed_at,total_rows,accepted_rows,scan_complete) VALUES (?,?,?,'completed',now(),1,1,true)",batch,source,"test.csv")
        jdbc.update("INSERT INTO usage.usage_events(id,organization_id,source,event_id,user_id,project_id,provider,model,tool,input_tokens,output_tokens,cached_input_tokens,occurred_at,agent_run_id,workflow_type,import_batch_id,schema_version,payload_fingerprint) VALUES (?,?,?,?,?,?,?,?,?,100,20,10,'2026-11-15T14:00:10Z','run-1','code-review',?,1,?)",UUID.randomUUID(),org,source,"event-1",user,project,"openai","demo-code-v1","coding-assistant",batch,"a".repeat(64))
        val before=jdbc.queryForObject("SELECT COUNT(*) FROM usage.usage_events",Long::class.java)
        val first=service().importFile(file(record(),"valid.jsonl"),source);assertEquals(1,(first["batch"] as Map<*,*>)["imported_rows"])
        val replay=service().importFile(file(record(),"replay.jsonl"),source);assertEquals(1,(replay["batch"] as Map<*,*>)["duplicate_rows"])
        val conflict=service().importFile(file(record("failure"),"conflict.jsonl"),source);assertEquals(1,(conflict["batch"] as Map<*,*>)["rejected_rows"])
        assertEquals(before,jdbc.queryForObject("SELECT COUNT(*) FROM usage.usage_events",Long::class.java));assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM usage.agent_runs",Int::class.java));assertEquals(1,jdbc.queryForObject("SELECT COUNT(*) FROM usage.agent_attempts",Int::class.java))
    }
    @Test fun `metrics keep retries separate and aggregate linked tokens once`() {
        service().importFile(file(record(),"metrics.jsonl"),source)
        val body=mapper.valueToTree<com.fasterxml.jackson.databind.node.ObjectNode>(mapOf("organization_id" to org.toString(),"all_users" to true,"scope_users" to emptyList<String>(),"scope_projects" to emptyList<String>(),"filter_users" to null,"start" to "2026-11-01T00:00:00Z","end" to "2026-12-01T00:00:00Z","agent_id" to null,"run_id" to null,"project_id" to null,"user_id" to null,"workflow_type" to null,"status" to null,"outcome" to null,"retried" to null,"limit" to 25,"offset" to 0))
        val totals=AgentAnalytics(jdbc).report(body)["totals"] as Map<*,*>
        assertEquals(1L,totals["runs"]);assertEquals(1L,totals["successful_runs"]);assertEquals(0,(totals["average_retries"] as String).toBigDecimal().compareTo(java.math.BigDecimal.ZERO))
    }
}
