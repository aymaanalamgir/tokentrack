package com.tokentrack.usage.analytics

import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.generation.SyntheticGenerator
import com.tokentrack.usage.ingestion.IngestionService
import com.tokentrack.usage.persistence.UsageRepository
import com.tokentrack.usage.references.ReferenceResolver
import com.tokentrack.usage.validation.EventValidator
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.io.TempDir
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.transaction.annotation.Transactional
import java.nio.file.Path
import java.util.UUID

@Tag("postgres") @Transactional
@SpringBootTest(properties=["spring.main.web-application-type=none"])
class UsageAnalyticsTest {
    companion object {
        @JvmStatic @DynamicPropertySource fun database(r:DynamicPropertyRegistry) {
            val name=requireNotNull(System.getenv("USAGE_TEST_DB_NAME"));require(name!=System.getenv("DB_NAME"))
            r.add("spring.datasource.url") { "jdbc:postgresql://${System.getenv("DB_HOST")?:"localhost"}:${System.getenv("DB_PORT")?:"5432"}/$name?currentSchema=usage&connectTimeout=3&socketTimeout=3" }
            r.add("spring.datasource.driver-class-name") { "org.postgresql.Driver" }
        }
    }
    @Autowired lateinit var analytics:UsageAnalytics
    @Autowired lateinit var mapper:ObjectMapper
    @Autowired lateinit var repository:UsageRepository
    @Autowired lateinit var pricing:com.tokentrack.usage.pricing.PricingRepository
    @Autowired lateinit var pricingService:com.tokentrack.usage.pricing.PricingService
    private lateinit var source:String
    @TempDir lateinit var temp:Path
    private val org=UUID.randomUUID().toString();private val user=UUID.randomUUID().toString();private val other=UUID.randomUUID().toString();private val project=UUID.randomUUID().toString()
    private fun request()=mapper.valueToTree<com.fasterxml.jackson.databind.node.ObjectNode>(mapOf("organization_id" to org,"all_users" to false,"scope_users" to listOf(user),"scope_projects" to emptyList<String>(),"filter_users" to null,"start" to "2026-11-01T00:00:00Z","end" to "2026-12-01T00:00:00Z","granularity" to "day","project_id" to null,"user_id" to null,"provider" to null,"model" to null,"tool" to null))
    @BeforeEach fun importRows() {
        source="analytics-${UUID.randomUUID()}"
        val rows=listOf(Triple(user,org,"2026-11-15T14:00:00Z"),Triple(other,org,"2026-11-16T14:00:00Z"),Triple(user,UUID.randomUUID().toString(),"2026-11-15T14:00:00Z")).mapIndexed { i,(u,o,t)->mapOf("schema_version" to "1","event_id" to "event-$i","organization_id" to o,"user_id" to u,"project_id" to if(i==1)project else "","provider" to "openai","model" to "demo-code-v1","tool" to "coding-assistant","input_tokens" to "100000","cached_input_tokens" to "20000","output_tokens" to "10000","occurred_at" to t,"agent_run_id" to "","workflow_type" to "") }
        val file=temp.resolve("events.csv");SyntheticGenerator(mapper).write(file,rows)
        IngestionService(EventValidator(),ReferenceResolver { refs->refs.associate { it.key() to null } },repository).importFile(file,source)
    }
    @Suppress("UNCHECKED_CAST") private fun totals(result:Map<String,Any?>)=result["totals"] as Map<String,Any?>
    @Test fun `self aggregation includes unpriced tokens with cached subset counted once and excludes tenants`() {
        val result=analytics.report(request());val total=totals(result)
        @Suppress("UNCHECKED_CAST") val range=result["available_range"] as Map<String,String?>
        assertTrue(range["start"]!!.endsWith("Z"))
        assertEquals(1L,total["events"]);assertEquals("100000",total["input_tokens"]);assertEquals("10000",total["output_tokens"]);assertEquals("20000",total["cached_input_tokens"]);assertEquals(1L,total["unpriced_events"])
    }
    @Test fun `explicit organization scope remains tenant bound and models and tools reconcile`() {
        val result=analytics.report(request().put("all_users",true));assertEquals(2L,totals(result)["events"])
        for(key in listOf("models","tools","projects","employees")) {
            @Suppress("UNCHECKED_CAST") val rows=result[key] as List<Map<String,Any?>>
            assertEquals(2L,rows.sumOf { (it["events"] as Number).toLong() })
        }
    }
    @Test fun `led project union does not authorize unrelated activity for contributors`() {
        val body=request();body.set<com.fasterxml.jackson.databind.JsonNode>("scope_projects",mapper.valueToTree(listOf(project)))
        assertEquals(2L,totals(analytics.report(body))["events"])
        body.put("user_id",other);assertEquals(1L,totals(analytics.report(body))["events"])
        body.set<com.fasterxml.jackson.databind.JsonNode>("scope_projects",mapper.valueToTree(emptyList<String>()))
        assertEquals(0L,totals(analytics.report(body))["events"])
    }
    @Test fun `date predicates are half open and filters only narrow scope`() {
        val body=request().put("end","2026-11-15T14:00:00Z")
        assertEquals(0L,totals(analytics.report(body))["events"])
        body.put("end","2026-12-01T00:00:00Z").put("tool","other-tool")
        assertEquals(0L,totals(analytics.report(body))["events"])
    }
    @Test fun `weekly buckets start Monday UTC and monthly buckets use first day`() {
        val body=request().put("all_users",true).put("granularity","week")
        @Suppress("UNCHECKED_CAST") val weeks=analytics.report(body)["timeseries"] as List<Map<String,Any?>>
        assertEquals(listOf("2026-11-09T00:00:00Z","2026-11-16T00:00:00Z"),weeks.map{it["bucket"]})
        body.put("granularity","month")
        @Suppress("UNCHECKED_CAST") val months=analytics.report(body)["timeseries"] as List<Map<String,Any?>>
        assertEquals("2026-11-01T00:00:00Z",months.single()["bucket"])
    }
    @Test fun `invalid identifiers unknown keys huge lists and unbounded ranges fail before querying`() {
        val invalid=listOf(request().put("granularity","hour"),request().put("start","2000-01-01T00:00:00Z"),request().put("organization_id","bad"),request().put("sql","select anything"),request().put("all_users","true"))
        invalid.forEach { body->assertThrows(IllegalArgumentException::class.java){analytics.report(body)} }
        val body=request();body.set<com.fasterxml.jackson.databind.JsonNode>("scope_users",mapper.valueToTree((1..201).map{UUID.randomUUID().toString()}))
        assertThrows(IllegalArgumentException::class.java){analytics.report(body)}
    }
    @Test fun `priced analytics retain original model separately from synthetic pricing profile`() {
        val catalogue=mapper.readTree(javaClass.getResourceAsStream("/pricing/catalogue-v1.json"))
        val mapping=catalogue["mappings"].first { it["source_model"].asText()=="demo-code-v1" }.deepCopy<com.fasterxml.jackson.databind.node.ObjectNode>()
        mapping.put("id",UUID.randomUUID().toString()).put("source",source)
        (catalogue as com.fasterxml.jackson.databind.node.ObjectNode).set<com.fasterxml.jackson.databind.JsonNode>("mappings",mapper.createArrayNode().add(mapping))
        val file=temp.resolve("catalogue.json");mapper.writeValue(file.toFile(),catalogue);pricing.loadCatalogue(file);pricingService.price(source)
        @Suppress("UNCHECKED_CAST") val models=analytics.report(request())["models"] as List<Map<String,Any?>>
        assertEquals("demo-code-v1",models.single()["model"]);assertEquals("gpt-5.4-mini",models.single()["pricing_model"])
        assertEquals("synthetic_standard_cache_read",models.single()["billing_basis"])
        assertEquals(1L,models.single()["priced_events"])
    }
    @Test fun `separate service authentication rejects browser and other credentials`() {
        val controller=AnalyticsController(analytics,"a".repeat(64))
        assertEquals(401,controller.report(null,request()).statusCode.value())
        assertEquals(401,controller.report("Bearer "+"b".repeat(64),request()).statusCode.value())
        assertEquals(200,controller.report("Bearer "+"a".repeat(64),request()).statusCode.value())
        assertEquals(400,controller.report("Bearer "+"a".repeat(64),request().put("granularity","hour")).statusCode.value())
    }
}
