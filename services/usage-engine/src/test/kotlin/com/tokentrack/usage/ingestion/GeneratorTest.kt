package com.tokentrack.usage.ingestion

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.tokentrack.usage.domain.RawUsageRecord
import com.tokentrack.usage.generation.SyntheticGenerator
import com.tokentrack.usage.validation.EventValidator
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.LocalDate

class GeneratorTest {
    private val mapper = jacksonObjectMapper()
    private val generator = SyntheticGenerator(mapper)
    private val org1 = "11111111-1111-1111-1111-111111111111"
    private val org2 = "22222222-2222-2222-2222-222222222222"
    private val user1 = "33333333-3333-3333-3333-333333333333"
    private val user2 = "44444444-4444-4444-4444-444444444444"
    private val project = "55555555-5555-5555-5555-555555555555"
    private fun snapshot() = mapper.valueToTree<com.fasterxml.jackson.databind.JsonNode>(mapOf(
        "snapshot_version" to 1, "policy_version" to "membership-period-v1", "organizations" to listOf(mapOf("id" to org1), mapOf("id" to org2)),
        "users" to listOf(mapOf("id" to user1, "organization_id" to org1, "job_function" to "Engineering", "primary_unit_id" to "platform"), mapOf("id" to user2, "organization_id" to org2, "job_function" to "Design", "primary_unit_id" to "design")),
        "projects" to listOf(mapOf("id" to project, "organization_id" to org1)), "memberships" to listOf(mapOf("user_id" to user1, "organization_id" to org1, "project_id" to project, "joined_at" to "2026-11-05T00:00:00Z", "left_at" to "2026-11-20T00:00:00Z"))))
    @Test fun `seed snapshot and explicit window determine identical records`() {
        val first = generator.generate(snapshot(), 42, LocalDate.parse("2026-11-01"), LocalDate.parse("2026-12-01"))
        val again = generator.generate(snapshot(), 42, LocalDate.parse("2026-11-01"), LocalDate.parse("2026-12-01"))
        val different = generator.generate(snapshot(), 43, LocalDate.parse("2026-11-01"), LocalDate.parse("2026-12-01"))
        assertEquals(first, again); assertNotEquals(first.rows, different.rows)
        assertEquals(setOf(org1, org2), first.rows.map { it["organization_id"] }.toSet())
        assertTrue(first.rows.any { it["project_id"] == project }); assertTrue(first.rows.any { it["project_id"].isNullOrEmpty() })
        first.rows.forEach { row ->
            assertNull(EventValidator().validate(RawUsageRecord(2, row), "test-source").error)
            val time = Instant.parse(row.getValue("occurred_at"))
            assertTrue(time >= Instant.parse("2026-11-01T00:00:00Z") && time < Instant.parse("2026-12-01T00:00:00Z"))
            if (!row["project_id"].isNullOrEmpty()) {
                assertEquals(user1, row["user_id"]); assertEquals(org1, row["organization_id"])
                assertTrue(time >= Instant.parse("2026-11-05T00:00:00Z") && time < Instant.parse("2026-11-20T00:00:00Z"))
            }
        }
        assertTrue(first.rows.any { it["agent_run_id"]!!.isNotEmpty() })
        assertTrue(first.rows.any { it["workflow_type"] == "user-research" })
    }
    @Test fun `old unrecorded memberships are never invented`() {
        val dataset = generator.generate(snapshot(), 42, LocalDate.parse("2026-10-01"), LocalDate.parse("2026-11-01"))
        assertTrue(dataset.rows.all { it["project_id"].isNullOrEmpty() })
    }
}
