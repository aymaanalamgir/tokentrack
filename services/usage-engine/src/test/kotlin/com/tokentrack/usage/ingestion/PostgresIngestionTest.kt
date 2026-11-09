package com.tokentrack.usage.ingestion

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.tokentrack.usage.domain.*
import com.tokentrack.usage.generation.SyntheticGenerator
import com.tokentrack.usage.persistence.UsageRepository
import com.tokentrack.usage.references.ReferenceResolver
import com.tokentrack.usage.validation.EventValidator
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
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@Tag("postgres")
@Timeout(30)
@SpringBootTest(properties = ["spring.main.web-application-type=none"])
class PostgresIngestionTest {
    companion object {
        @JvmStatic @DynamicPropertySource fun database(registry: DynamicPropertyRegistry) {
            val name = requireNotNull(System.getenv("USAGE_TEST_DB_NAME")) { "Set USAGE_TEST_DB_NAME to the isolated PostgreSQL test database" }
            require(name != (System.getenv("DB_NAME") ?: "tokentrack_development")) { "Integration tests require a separate database" }
            registry.add("spring.datasource.url") { "jdbc:postgresql://${System.getenv("DB_HOST") ?: "localhost"}:${System.getenv("DB_PORT") ?: "5432"}/$name?currentSchema=usage&connectTimeout=3&socketTimeout=3" }
            registry.add("spring.datasource.driver-class-name") { "org.postgresql.Driver" }
        }
    }
    @Autowired lateinit var repository: UsageRepository
    @Autowired lateinit var jdbc: JdbcTemplate
    @Autowired lateinit var manager: PlatformTransactionManager
    @TempDir lateinit var temp: Path
    private lateinit var source: String
    private val org = UUID.randomUUID().toString()
    private val user = UUID.randomUUID().toString()
    private val generator = SyntheticGenerator(jacksonObjectMapper())
    @BeforeEach fun setup() { source = "test-${UUID.randomUUID()}" }
    @AfterEach fun cleanup() {
        TransactionTemplate(manager).executeWithoutResult {
            jdbc.update("DELETE FROM usage.import_rejections WHERE import_batch_id IN (SELECT id FROM usage.import_batches WHERE source=?)", source)
            jdbc.update("DELETE FROM usage.usage_events WHERE source=?", source)
            jdbc.update("DELETE FROM usage.import_batches WHERE source=?", source)
        }
    }
    private fun row(id: String = "event-1") = mapOf("schema_version" to "1", "event_id" to id, "organization_id" to org, "user_id" to user, "project_id" to "",
        "provider" to "openai", "model" to "model-a", "tool" to "coding-assistant", "input_tokens" to "100", "output_tokens" to "20", "occurred_at" to "2026-11-09T12:00:00Z")
    private fun csv(rows: List<Map<String, String>>, name: String = "events.csv"): Path = temp.resolve(name).also { generator.write(it, rows) }
    private val validRefs = ReferenceResolver { refs -> refs.associate { it.key() to null } }
    private fun service(resolver: ReferenceResolver = validRefs) = IngestionService(EventValidator(), resolver, repository)
    private fun count() = jdbc.queryForObject("SELECT COUNT(*) FROM usage.usage_events WHERE source=?", Int::class.java, source)!!

    @Test fun `first import persists and replays in any filename only count duplicates`() {
        val first = service().importFile(csv(listOf(row(), row("event-2"))), source)
        assertEquals(2, first.acceptedRows); assertEquals("completed", first.status)
        val replay = service().importFile(csv(listOf(row(), row("event-2")), "renamed.csv"), source)
        assertEquals(0, replay.acceptedRows); assertEquals(2, replay.duplicateRows); assertEquals(2, count())
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM usage.usage_events WHERE import_batch_id=?", Int::class.java, first.id))
    }
    @Test fun `duplicates within a file and conflicting payloads preserve the original`() {
        val result = service().importFile(csv(listOf(row(), row(), row() + ("input_tokens" to "101"))), source)
        assertEquals(1, result.acceptedRows); assertEquals(1, result.duplicateRows); assertEquals(1, result.rejectedRows)
        assertEquals("completed_with_rejections", result.status)
        assertEquals("EVENT_ID_CONFLICT", repository.rejections(result.id).single()["code"])
        assertEquals(100L, jdbc.queryForObject("SELECT input_tokens FROM usage.usage_events WHERE source=?", Long::class.java, source))
        val conflict = service().importFile(csv(listOf(row() + ("tool" to "different-tool"))), source)
        assertEquals(1, conflict.rejectedRows); assertEquals(1, count())
    }
    @Test fun `mixed invalid rows retain valid rows and persistent actionable rejections`() {
        val result = service().importFile(csv(listOf(row(), row("negative") + ("input_tokens" to "-1"), row("zero") + mapOf("input_tokens" to "0", "output_tokens" to "0"), row("event-2"))), source)
        assertEquals(4, result.totalRows); assertEquals(2, result.acceptedRows); assertEquals(2, result.rejectedRows)
        assertEquals(listOf(3,4), repository.rejections(result.id).map { it["row_number"] })
        assertEquals(setOf("INVALID_TOKEN_COUNT", "ZERO_TOKEN_EVENT"), repository.errors(result.id).map { it["code"] }.toSet())
        assertEquals(2, count()); assertTrue(result.scanComplete)
    }
    @Test fun `reference business errors are row rejections without blocking other users`() {
        val bad = UUID.randomUUID().toString()
        val resolver = ReferenceResolver { refs -> refs.associate { it.key() to if (it.userId.toString() == bad) ValidationError("INVALID_USER_REFERENCE", "user_id", "User does not belong to this organization") else null } }
        val result = service(resolver).importFile(csv(listOf(row(), row("foreign") + ("user_id" to bad))), source)
        assertEquals(1, result.acceptedRows); assertEquals(1, result.rejectedRows); assertEquals(0, result.infrastructureFailures)
    }
    @Test fun `service outage after a committed chunk reports partial progress and retries safely`() {
        val calls = AtomicInteger()
        val resolver = ReferenceResolver { refs ->
            if (refs.isNotEmpty() && calls.incrementAndGet() > 1) throw ImportFailure("REFERENCE_SERVICE_UNAVAILABLE", true)
            refs.associate { it.key() to null }
        }
        val file = csv(listOf(row(), row("second") + ("occurred_at" to "2026-11-09T13:00:00Z")))
        val partial = service(resolver).importFile(file, source, 1)
        assertEquals("partial", partial.status); assertEquals(1, partial.acceptedRows); assertEquals(1, partial.unprocessedRows)
        assertEquals(1, partial.infrastructureFailures); assertEquals("REFERENCE_SERVICE_UNAVAILABLE", partial.failureCode)
        assertTrue(repository.rejections(partial.id).isEmpty()); assertFalse(partial.scanComplete)
        val retry = service().importFile(file, source, 1)
        assertEquals(1, retry.acceptedRows); assertEquals(1, retry.duplicateRows); assertEquals(2, count())
    }
    @Test fun `exact reference cache avoids redundant calls across chunks`() {
        val calls = AtomicInteger()
        val resolver = ReferenceResolver { refs -> if (refs.isNotEmpty()) calls.incrementAndGet(); refs.associate { it.key() to null } }
        service(resolver).importFile(csv(listOf(row(), row("second"))), source, 1)
        assertEquals(1, calls.get())
    }
    @Test fun `invalid header and malformed quoting are distinct fatal reports preserving prior rows`() {
        val badHeader = temp.resolve("bad-header.csv").also { Files.writeString(it, "event_id,prompt\nevent,private text\n") }
        val header = service().importFile(badHeader, source)
        assertEquals("failed", header.status); assertEquals("INVALID_HEADERS", header.failureCode); assertEquals(0, header.acceptedRows)
        val file = csv(listOf(row())).also { Files.writeString(it, Files.readString(it) + "\"unterminated") }
        val malformed = service().importFile(file, source)
        assertEquals("partial", malformed.status); assertEquals("INVALID_CSV", malformed.failureCode); assertEquals(1, malformed.acceptedRows)
        assertEquals(1, count()); assertFalse(malformed.scanComplete)
        assertEquals("INVALID_CSV", repository.rejections(malformed.id).single()["code"])
    }
    @Test fun `wrong column count is recoverable within a mixed file`() {
        val file = csv(listOf(row(), row("second")))
        val text = Files.readString(file); val at = text.indexOf('\n') + 1
        Files.writeString(file, text.take(at) + "wrong,columns\n" + text.drop(at))
        val result = service().importFile(file, source)
        assertEquals(2, result.acceptedRows); assertEquals(1, result.rejectedRows); assertTrue(result.scanComplete)
        assertEquals("COLUMN_COUNT", repository.rejections(result.id).single()["code"])
    }
    @Test fun `concurrent imports are protected by PostgreSQL uniqueness`() {
        val file = csv(listOf(row()))
        val barrier = CountDownLatch(2)
        val resolver = ReferenceResolver { refs -> barrier.countDown(); check(barrier.await(5, TimeUnit.SECONDS)); refs.associate { it.key() to null } }
        val pool = Executors.newFixedThreadPool(2)
        try {
            val tasks = (1..2).map { pool.submit<BatchSummary> { service(resolver).importFile(file, source) } }
            val results = tasks.map { it.get(15, TimeUnit.SECONDS) }
            assertEquals(1, results.sumOf { it.acceptedRows }); assertEquals(1, results.sumOf { it.duplicateRows }); assertEquals(1, count())
        } finally { pool.shutdownNow() }
    }
    @Test fun `database constraints roll back a failed chunk and reject direct duplicate inserts`() {
        val id = repository.begin(source, "constraint-test.csv")
        val event = EventValidator().validate(RawUsageRecord(2, row()), source).event!!
        assertThrows(DataAccessException::class.java) { repository.commitRows(id, listOf(PreparedRow(2, event.eventId, event), PreparedRow(3, "bad", event.copy(eventId="bad", inputTokens=EventValidator.MAX_TOKENS + 1))), 2) }
        assertEquals(0, count()); assertEquals(0, repository.summary(id).acceptedRows)
        repository.commitRows(id, listOf(PreparedRow(2, event.eventId, event)), 1)
        assertThrows(DataAccessException::class.java) {
            jdbc.update("INSERT INTO usage.usage_events SELECT gen_random_uuid(),organization_id,source,event_id,user_id,project_id,provider,model,tool,input_tokens,output_tokens,cached_input_tokens,occurred_at,agent_run_id,workflow_type,import_batch_id,schema_version,payload_fingerprint,created_at FROM usage.usage_events WHERE source=?", source)
        }
        assertEquals(1, count())
        assertThrows(DataAccessException::class.java) { jdbc.queryForList("SELECT id FROM business.users LIMIT 1") }
    }
    @Test fun `abandoned leases become truthful partial reports and cannot resume writes`() {
        val id = repository.begin(source, "interrupted.csv")
        val event = EventValidator().validate(RawUsageRecord(2, row()), source).event!!
        repository.commitRows(id, listOf(PreparedRow(2, event.eventId, event)), 1)
        jdbc.update("UPDATE usage.import_batches SET heartbeat_at=CURRENT_TIMESTAMP - INTERVAL '16 minutes' WHERE id=?", id)
        repository.recoverStale()
        assertEquals("partial", repository.summary(id).status); assertEquals("IMPORT_INTERRUPTED", repository.summary(id).failureCode)
        assertThrows(ImportFailure::class.java) { repository.commitRows(id, listOf(PreparedRow(3, "second", event.copy(eventId="second"))), 2) }
        val retry = service().importFile(csv(listOf(row(), row("second"))), source)
        assertEquals(1, retry.duplicateRows); assertEquals(1, retry.acceptedRows)
    }
}
