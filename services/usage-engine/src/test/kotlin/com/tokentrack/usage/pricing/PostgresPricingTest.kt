package com.tokentrack.usage.pricing

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.delivery.*
import com.tokentrack.usage.domain.ValidationError
import com.tokentrack.usage.generation.SyntheticGenerator
import com.tokentrack.usage.ingestion.IngestionService
import com.tokentrack.usage.references.ReferenceResolver
import com.tokentrack.usage.validation.EventValidator
import com.tokentrack.usage.persistence.UsageRepository
import org.junit.jupiter.api.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.io.TempDir
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.dao.DataAccessException
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.DynamicPropertyRegistry
import org.springframework.test.context.DynamicPropertySource
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.support.TransactionTemplate
import java.math.BigDecimal
import java.nio.file.Path
import java.sql.Timestamp
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@Tag("postgres") @Timeout(30)
@SpringBootTest(properties=["spring.main.web-application-type=none"])
class PostgresPricingTest {
    companion object {
        @JvmStatic @DynamicPropertySource fun database(r:DynamicPropertyRegistry) {
            val name=requireNotNull(System.getenv("USAGE_TEST_DB_NAME"));require(name!=(System.getenv("DB_NAME")?:"tokentrack_development"))
            r.add("spring.datasource.url") { "jdbc:postgresql://${System.getenv("DB_HOST")?:"localhost"}:${System.getenv("DB_PORT")?:"5432"}/$name?currentSchema=usage&connectTimeout=3&socketTimeout=3" }
            r.add("spring.datasource.driver-class-name") { "org.postgresql.Driver" }
        }
    }
    @Autowired lateinit var jdbc:JdbcTemplate
    @Autowired lateinit var manager:PlatformTransactionManager
    @Autowired lateinit var mapper:ObjectMapper
    @Autowired lateinit var repository:PricingRepository
    @Autowired lateinit var ingestionRepository:UsageRepository
    @Autowired lateinit var outbox:OutboxRepository
    @TempDir lateinit var temp:Path
    private lateinit var source:String
    private lateinit var model:String
    private val rateIds=mutableListOf<UUID>()
    @BeforeEach fun setup() { source="price-test-${UUID.randomUUID()}";model="test-${UUID.randomUUID()}";rateIds.clear() }
    @AfterEach fun cleanup() {
        TransactionTemplate(manager).executeWithoutResult {
            val tables=listOf("delivery_outbox","priced_usage_events","pricing_model_mappings","model_pricing_rates")
            tables.forEach { jdbc.execute("ALTER TABLE usage.$it DISABLE TRIGGER USER") }
            jdbc.update("DELETE FROM usage.delivery_attempts WHERE outbox_id IN(SELECT o.id FROM usage.delivery_outbox o JOIN usage.priced_usage_events p ON p.id=o.priced_usage_event_id JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=?)",source)
            jdbc.update("DELETE FROM usage.delivery_outbox WHERE priced_usage_event_id IN(SELECT p.id FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=?)",source)
            jdbc.update("DELETE FROM usage.pricing_failures WHERE usage_event_id IN(SELECT id FROM usage.usage_events WHERE source=?)",source)
            jdbc.update("DELETE FROM usage.priced_usage_events WHERE usage_event_id IN(SELECT id FROM usage.usage_events WHERE source=?)",source)
            jdbc.update("DELETE FROM usage.import_rejections WHERE import_batch_id IN(SELECT id FROM usage.import_batches WHERE source=?)",source)
            jdbc.update("DELETE FROM usage.usage_events WHERE source=?",source)
            jdbc.update("DELETE FROM usage.import_batches WHERE source=?",source)
            jdbc.update("DELETE FROM usage.pricing_model_mappings WHERE source=?",source)
            rateIds.forEach { jdbc.update("DELETE FROM usage.model_pricing_rates WHERE id=?",it) }
            tables.forEach { jdbc.execute("ALTER TABLE usage.$it ENABLE TRIGGER USER") }
        }
    }
    private fun rate(input:String="0.75",from:String="2026-11-01T00:00:00Z",until:String?=null,id:UUID=UUID.randomUUID()):UUID {
        jdbc.update("""INSERT INTO usage.model_pricing_rates(id,provider,model,pricing_tier,currency,input_rate_per_million,cached_input_rate_per_million,output_rate_per_million,effective_from,effective_until,source_url,verified_at,synthetic)
            VALUES (?,'test',?,'standard_text_cache_read','USD',?::numeric,0.075,4.5,?,?,'urn:test:synthetic','2026-11-09T00:00:00Z',true)""",id,model,input,Timestamp.from(Instant.parse(from)),until?.let { Timestamp.from(Instant.parse(it)) })
        synchronized(rateIds) { rateIds+=id };return id
    }
    private fun mapping(basis:String="synthetic_standard_cache_read",maxInput:Long=200000) {
        jdbc.update("""INSERT INTO usage.pricing_model_mappings(id,source,source_provider,source_model,target_provider,target_model,pricing_tier,currency,billing_basis,description,max_input_tokens,max_output_tokens,max_context_tokens)
            VALUES (?,?,'test',?,'test',?,'standard_text_cache_read','USD',?,'Explicit synthetic test profile',?,64000,200000)""",UUID.randomUUID(),source,model,model,basis,maxInput)
    }
    private fun importRows(times:List<String> = listOf("2026-11-15T14:30:00Z")) {
        val rows=times.mapIndexed { index,time -> mapOf("schema_version" to "1","event_id" to "event-$index","organization_id" to "11111111-1111-1111-1111-111111111111","user_id" to "22222222-2222-2222-2222-222222222222","project_id" to "","provider" to "test","model" to model,"tool" to "coding-assistant","input_tokens" to "100000","cached_input_tokens" to "20000","output_tokens" to "10000","occurred_at" to time) }
        val file=temp.resolve("events.csv");SyntheticGenerator(mapper).write(file,rows)
        IngestionService(EventValidator(),ReferenceResolver { refs -> refs.associate { it.key() to null } },ingestionRepository).importFile(file,source)
    }
    private fun price()=PricingService(repository).price(source)
    private fun scalar(sql:String)=jdbc.queryForObject(sql,Long::class.java)!!
    private fun ack(payload:JsonNode)=FinancialResponse(201,mapper.valueToTree(mapOf("schema_version" to 1,"priced_event_id" to payload["priced_event_id"].asText(),"usage_event_id" to payload["usage_event_id"].asText(),"status" to "posted","currency" to "USD","amount" to payload["amount"].asText(),"financial_transaction_id" to UUID.randomUUID().toString())))
    private fun gateway(handler:(JsonNode)->FinancialResponse)=object:FinancialGateway {
        override fun post(payload:String)=handler(mapper.readTree(payload))
        override fun reconcile(ids:List<String>)=FinancialResponse(503)
    }
    @Test fun `pricing is idempotent atomic with its outbox and leaves canonical fingerprints intact`() {
        importRows();rate();mapping()
        val fingerprint=jdbc.queryForObject("SELECT payload_fingerprint FROM usage.usage_events WHERE source=?",String::class.java,source)
        val first=price();assertEquals(1,first["priced"])
        assertEquals(BigDecimal("0.106500000000000"),jdbc.queryForObject("SELECT total_cost FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=?",BigDecimal::class.java,source))
        assertEquals(0,price()["priced"])
        assertEquals(fingerprint,jdbc.queryForObject("SELECT payload_fingerprint FROM usage.usage_events WHERE source=?",String::class.java,source))
        assertEquals(1,scalar("SELECT COUNT(*) FROM usage.delivery_outbox o JOIN usage.priced_usage_events p ON p.id=o.priced_usage_event_id JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source='$source'"))
    }
    @Test fun `unpriced diagnostics distinguish missing metadata missing schedules and unsupported profiles`() {
        importRows();assertEquals(1,price()["missing_rate"])
        rate();assertEquals(1,price()["insufficient_billing_metadata"])
        mapping(basis="cache_write_unsupported");assertEquals(1,price()["unsupported_profile"])
        assertEquals(0L,scalar("SELECT COUNT(*) FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source='$source'"))
    }
    @Test fun `explicit short-context limits reject unsupported configurations without a guessed price`() {
        importRows();rate();mapping(maxInput=99999)
        assertEquals(1,price()["unsupported_profile"])
    }
    @Test fun `later schedules preserve earlier immutable cost snapshots`() {
        importRows(listOf("2026-11-15T00:00:00Z","2026-11-25T00:00:00Z"));rate(input="3",until="2026-11-20T00:00:00Z");mapping()
        assertEquals(1,price()["priced"])
        rate(input="2.5",from="2026-11-20T00:00:00Z")
        assertEquals(1,price()["priced"])
        val inputs=jdbc.queryForList("SELECT p.input_rate_snapshot FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=? ORDER BY e.occurred_at",source)
        assertEquals(listOf("3","2.5"),inputs.map { DecimalMoney.text(it["input_rate_snapshot"] as BigDecimal) })
        assertThrows(DataAccessException::class.java) { jdbc.update("UPDATE usage.priced_usage_events SET total_cost=0 WHERE usage_event_id IN(SELECT id FROM usage.usage_events WHERE source=?)",source) }
        assertThrows(DataAccessException::class.java) { jdbc.update("UPDATE usage.model_pricing_rates SET input_rate_per_million=0 WHERE id=?",rateIds.first()) }
    }
    @Test fun `PostgreSQL serializes concurrent overlapping schedule insertion`() {
        val pool=Executors.newFixedThreadPool(2);val barrier=CountDownLatch(2)
        try {
            val tasks=(1..2).map { pool.submit<Boolean> { barrier.countDown();check(barrier.await(5,TimeUnit.SECONDS));try { rate();true } catch(_:DataAccessException) { false } } }
            assertEquals(1,tasks.count { it.get(10,TimeUnit.SECONDS) })
        } finally { pool.shutdownNow() }
    }
    @Test fun `concurrent pricing jobs create one snapshot and one outbox record`() {
        importRows();rate();mapping();val pool=Executors.newFixedThreadPool(2)
        try { (1..2).map { pool.submit { price() } }.forEach { it.get(10,TimeUnit.SECONDS) } } finally { pool.shutdownNow() }
        assertEquals(1L,scalar("SELECT COUNT(*) FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source='$source'"))
        assertEquals(1L,scalar("SELECT COUNT(*) FROM usage.delivery_outbox o JOIN usage.priced_usage_events p ON p.id=o.priced_usage_event_id JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source='$source'"))
    }
    @Test fun `successful delivery records acknowledgment and an inspectable attempt`() {
        importRows();rate();mapping();price()
        val result=DeliveryWorker(outbox,gateway(::ack)).deliver(10,2)
        assertEquals(1,result["delivered"])
        assertEquals(0,DeliveryWorker(outbox,gateway(::ack)).deliver(10,2)["attempted"])
    }
    @Test fun `temporary failures retry with backoff then recover without replacing the payload`() {
        importRows();rate();mapping();price()
        val failed=DeliveryWorker(outbox,gateway { FinancialResponse(503) }).deliver(1,1)
        assertEquals(1,failed["retry"])
        assertEquals(0,DeliveryWorker(outbox,gateway(::ack)).deliver(1,1)["attempted"])
        jdbc.update("UPDATE usage.delivery_outbox SET next_attempt_at=CURRENT_TIMESTAMP WHERE priced_usage_event_id IN(SELECT p.id FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=?)",source)
        assertEquals(1,DeliveryWorker(outbox,gateway(::ack)).deliver(1,1)["delivered"])
    }
    @Test fun `authentication and conflicting payload failures become dead without infinite retry`() {
        importRows(listOf("2026-11-15T00:00:00Z","2026-11-15T01:00:00Z"));rate();mapping();price()
        val first=DeliveryWorker(outbox,gateway { FinancialResponse(401) }).deliver(1,1)
        val second=DeliveryWorker(outbox,gateway { FinancialResponse(409) }).deliver(1,1)
        assertEquals(1,first["dead"]);assertEquals(1,second["dead"])
        assertEquals(0,DeliveryWorker(outbox,gateway(::ack)).deliver(10,1)["attempted"])
        assertEquals(2,DeliveryWorker(outbox,gateway(::ack)).deliver(10,1,true)["delivered"])
    }
    @Test fun `an unavailable owner and malformed acknowledgment are never marked delivered`() {
        importRows(listOf("2026-11-15T00:00:00Z","2026-11-15T01:00:00Z"));rate();mapping();price()
        assertEquals(1,DeliveryWorker(outbox,gateway { FinancialResponse(202) }).deliver(1,1)["retry"])
        assertEquals(1,DeliveryWorker(outbox,gateway { payload -> val result=ack(payload);(result.body as com.fasterxml.jackson.databind.node.ObjectNode).put("amount","999");result }).deliver(1,1)["retry"])
    }
    @Test fun `worker restart reclaims an expired lease and stale acknowledgments cannot win`() {
        importRows();rate();mapping();price()
        val stale=outbox.claim(1).single()
        jdbc.update("UPDATE usage.delivery_outbox SET lease_until=CURRENT_TIMESTAMP-INTERVAL '1 minute' WHERE id=?",stale.id)
        val current=outbox.claim(1).single()
        assertEquals("lease_lost",outbox.finish(stale,ack(mapper.readTree(stale.payload))))
        assertEquals("delivered",outbox.finish(current,ack(mapper.readTree(current.payload))))
    }
    @Test fun `concurrent delivery workers do not claim a message twice`() {
        importRows();rate();mapping();price();val calls=AtomicInteger();val pool=Executors.newFixedThreadPool(2)
        val worker=DeliveryWorker(outbox,gateway { calls.incrementAndGet();ack(it) })
        try { (1..2).map { pool.submit { worker.deliver(1,1) } }.forEach { it.get(10,TimeUnit.SECONDS) } } finally { pool.shutdownNow() }
        assertEquals(1,calls.get())
    }
    @Test fun `outbox payload and prices cannot be edited or truncated through normal SQL`() {
        importRows();rate();mapping();price()
        assertThrows(DataAccessException::class.java) { jdbc.update("UPDATE usage.delivery_outbox SET payload=jsonb_set(payload,'{amount}','\"2\"') WHERE priced_usage_event_id IN(SELECT p.id FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=?)",source) }
        assertThrows(DataAccessException::class.java) { jdbc.execute("TRUNCATE usage.priced_usage_events CASCADE") }
    }
    private fun reconciliationResponse(changes:Map<String,Any?> = emptyMap()):FinancialResponse {
        val row=jdbc.queryForMap("SELECT p.id,p.usage_event_id,p.total_cost,o.payload_fingerprint,o.acknowledged_transaction_id FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id JOIN usage.delivery_outbox o ON o.priced_usage_event_id=p.id WHERE e.source=?",source)
        val amount=DecimalMoney.text(row["total_cost"] as BigDecimal)
        val record=mapOf("priced_event_id" to row["id"].toString(),"usage_event_id" to row["usage_event_id"].toString(),"posted_usage_event_id" to row["usage_event_id"].toString(),"status" to "posted",
            "original_amount" to amount,"original_ledger_amount" to amount,"net_amount" to amount,"adjustment_delta" to "0","payload_fingerprint" to row["payload_fingerprint"],"financial_transaction_id" to row["acknowledged_transaction_id"]?.toString())+changes
        return FinancialResponse(200,mapper.valueToTree(mapOf("schema_version" to 1,"data" to listOf(record),"integrity" to mapOf("duplicate_expenses" to 0,"unbalanced_transfers" to 0,"posted_receipts_missing_transactions" to 0,"invalid_operation_entries" to 0))))
    }
    @Test fun `reconciliation detects original ledger discrepancies rather than calling them adjustments`() {
        importRows();rate();mapping();price();DeliveryWorker(outbox,gateway(::ack)).deliver(1,1)
        val fake=object:FinancialGateway {
            override fun post(payload:String)=ack(mapper.readTree(payload))
            override fun reconcile(ids:List<String>)=reconciliationResponse(mapOf("original_ledger_amount" to "0.2","net_amount" to "0.2"))
        }
        val result=FinancialReconciler(jdbc,fake,repository).reconcile(source)
        assertEquals("discrepancy",result["status"]);assertEquals(1,result["amount_discrepancies"])
    }
    @Test fun `authorized correction deltas reconcile without repricing the source snapshot`() {
        importRows();rate();mapping();price();DeliveryWorker(outbox,gateway(::ack)).deliver(1,1)
        val fake=object:FinancialGateway {
            override fun post(payload:String)=ack(mapper.readTree(payload))
            override fun reconcile(ids:List<String>)=reconciliationResponse(mapOf("net_amount" to "0.1","adjustment_delta" to "-0.0065"))
        }
        val result=FinancialReconciler(jdbc,fake,repository).reconcile(source)
        assertEquals("reconciled",result["status"]);assertEquals("0.1065",result["priced_total_usd"]);assertEquals("0.1",result["net_expenditure_usd"])
    }
    @Test fun `delivered events missing a financial posting are reconciliation discrepancies`() {
        importRows();rate();mapping();price();DeliveryWorker(outbox,gateway(::ack)).deliver(1,1)
        val fake=object:FinancialGateway {
            override fun post(payload:String)=ack(mapper.readTree(payload))
            override fun reconcile(ids:List<String>)=reconciliationResponse(mapOf("status" to "missing"))
        }
        assertEquals(1,FinancialReconciler(jdbc,fake,repository).reconcile(source)["delivered_missing_postings"])
    }
    @Test fun `controlled closure allows a future schedule without changing the previous snapshot`() {
        importRows();val first=rate();mapping();price()
        repository.closeRate(first,Instant.parse("2026-11-20T00:00:00Z"))
        rate(input="0.5",from="2026-11-20T00:00:00Z")
        val originalUntil:Timestamp?=jdbc.queryForObject("SELECT effective_until_snapshot FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=?",Timestamp::class.java,source)
        org.junit.jupiter.api.Assertions.assertNull(originalUntil)
        assertEquals("0.1065",repository.counts(source)["total_usd"])
        assertThrows(DataAccessException::class.java) { repository.closeRate(first,Instant.parse("2026-11-10T00:00:00Z")) }
    }
    @Test fun `retry budget is bounded and permanent validation failures stop immediately`() {
        importRows();rate();mapping();price()
        repeat(8) {
            jdbc.update("UPDATE usage.delivery_outbox SET next_attempt_at=CURRENT_TIMESTAMP WHERE priced_usage_event_id IN(SELECT p.id FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE e.source=?)",source)
            DeliveryWorker(outbox,gateway { FinancialResponse(503) }).deliver(1,1)
        }
        assertEquals(0,DeliveryWorker(outbox,gateway(::ack)).deliver(1,1)["attempted"])
        assertEquals(1,DeliveryWorker(outbox,gateway { FinancialResponse(422) }).deliver(1,1,true)["dead"])
    }

}
