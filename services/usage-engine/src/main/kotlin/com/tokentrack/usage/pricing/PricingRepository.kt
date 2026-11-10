package com.tokentrack.usage.pricing

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.domain.UsageEvent
import com.tokentrack.usage.domain.sha256
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.support.TransactionTemplate
import java.nio.file.Path
import java.math.BigDecimal
import java.sql.ResultSet
import java.sql.Timestamp
import java.time.Instant
import java.util.TreeMap
import java.util.UUID

data class StoredUsage(val id: UUID, val event: UsageEvent, val fingerprint: String)
@Repository
class PricingRepository(val jdbc: JdbcTemplate, manager: PlatformTransactionManager, private val mapper: ObjectMapper) {
    private val transaction = TransactionTemplate(manager).apply { timeout=30 }
    fun loadCatalogue(path: Path? = null): Map<String,Int> {
        val root = if(path==null) mapper.readTree(javaClass.getResourceAsStream("/pricing/catalogue-v1.json")) else mapper.readTree(path.toFile())
        require(root.path("catalogue_version").asInt()==1 && root.path("rates").isArray && root.path("mappings").isArray)
        require(root["rates"].size()<=1000 && root["mappings"].size()<=1000)
        var rateCount=0; var mapCount=0
        transaction.executeWithoutResult {
            root["rates"].forEach { r ->
                fun s(key:String)=r.path(key).asText().also { require(r.path(key).isTextual) }
                val id=UUID.fromString(s("id"))
                val input=DecimalMoney.rate(s("input_rate_per_million")); val cached=DecimalMoney.rate(s("cached_input_rate_per_million")); val output=DecimalMoney.rate(s("output_rate_per_million"))
                require(s("currency")=="USD")
                rateCount+=jdbc.update("""INSERT INTO usage.model_pricing_rates(id,provider,model,pricing_tier,currency,input_rate_per_million,cached_input_rate_per_million,output_rate_per_million,effective_from,effective_until,source_url,verified_at,synthetic)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING""",id,s("provider"),s("model"),s("pricing_tier"),s("currency"),input,cached,output,
                    Timestamp.from(Instant.parse(s("effective_from"))),r["effective_until"].takeUnless { it.isNull }?.asText()?.let { Timestamp.from(Instant.parse(it)) },s("source_url"),Timestamp.from(Instant.parse(s("verified_at"))),r.path("synthetic").asBoolean())
                val existing=rates().first { it.id==id }
                require(existing.provider==s("provider") && existing.model==s("model") && existing.tier==s("pricing_tier") && existing.currency==s("currency") && existing.input.compareTo(input)==0 && existing.cached.compareTo(cached)==0 && existing.output.compareTo(output)==0 && existing.from==Instant.parse(s("effective_from")) && existing.until==r["effective_until"].takeUnless { it.isNull }?.asText()?.let(Instant::parse) && existing.sourceUrl==s("source_url") && existing.verifiedAt==Instant.parse(s("verified_at")) && existing.synthetic==r.path("synthetic").asBoolean()) { "CATALOGUE_ID_CONFLICT" }
            }
            root["mappings"].forEach { m ->
                fun s(key:String)=m.path(key).asText().also { require(m.path(key).isTextual) }
                val id=UUID.fromString(s("id"))
                require(s("currency")=="USD")
                mapCount+=jdbc.update("""INSERT INTO usage.pricing_model_mappings(id,source,source_provider,source_model,target_provider,target_model,pricing_tier,currency,billing_basis,description,max_input_tokens,max_output_tokens,max_context_tokens)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING""",id,s("source"),s("source_provider"),s("source_model"),s("target_provider"),s("target_model"),s("pricing_tier"),s("currency"),s("billing_basis"),s("description"),m.path("max_input_tokens").asLong(),m.path("max_output_tokens").asLong(),m.path("max_context_tokens").asLong())
                val e=mappings().first { it.id==id }
                require(e==PricingMapping(id,s("source"),s("source_provider"),s("source_model"),s("target_provider"),s("target_model"),s("pricing_tier"),s("currency"),s("billing_basis"),s("description"),m.path("max_input_tokens").asLong(),m.path("max_output_tokens").asLong(),m.path("max_context_tokens").asLong())) { "MAPPING_ID_CONFLICT" }
            }
        }
        return mapOf("rates_inserted" to rateCount,"mappings_inserted" to mapCount)
    }
    fun closeRate(id:UUID,until:Instant):Map<String,String> = transaction.execute {
        val rate=rates().firstOrNull { it.id==id } ?: throw IllegalArgumentException("Unknown pricing rate")
        val key="${rate.provider}/${rate.model}/${rate.currency}/${rate.tier}"
        jdbc.queryForList("SELECT pg_advisory_xact_lock(hashtextextended(?,51001))",key)
        jdbc.update("UPDATE usage.model_pricing_rates SET effective_until=? WHERE id=?",Timestamp.from(until),id)
        mapOf("rate_id" to id.toString(),"effective_until" to DecimalMoney.time(until))
    }!!
    fun rates(): List<PricingRate> = jdbc.query("SELECT * FROM usage.model_pricing_rates ORDER BY provider,model,effective_from",{r,_->PricingRate(r.getObject("id",UUID::class.java),r.getString("provider"),r.getString("model"),r.getString("pricing_tier"),r.getString("currency"),r.getBigDecimal("input_rate_per_million"),r.getBigDecimal("cached_input_rate_per_million"),r.getBigDecimal("output_rate_per_million"),r.getTimestamp("effective_from").toInstant(),r.getTimestamp("effective_until")?.toInstant(),r.getString("source_url"),r.getTimestamp("verified_at").toInstant(),r.getBoolean("synthetic"))})
    fun mappings(): List<PricingMapping> = jdbc.query("SELECT * FROM usage.pricing_model_mappings ORDER BY id",{r,_->PricingMapping(r.getObject("id",UUID::class.java),r.getString("source"),r.getString("source_provider"),r.getString("source_model"),r.getString("target_provider"),r.getString("target_model"),r.getString("pricing_tier"),r.getString("currency"),r.getString("billing_basis"),r.getString("description"),r.getLong("max_input_tokens"),r.getLong("max_output_tokens"),r.getLong("max_context_tokens"))})
    fun <T> batch(after: UUID?, source: String?, work: (List<StoredUsage>)->T): Pair<List<StoredUsage>,T> {
        return transaction.execute {
            val records=jdbc.query("""SELECT e.* FROM usage.usage_events e WHERE (?::uuid IS NULL OR e.id>?::uuid) AND (?::text IS NULL OR e.source=?::text)
                AND NOT EXISTS(SELECT 1 FROM usage.priced_usage_events p WHERE p.usage_event_id=e.id) ORDER BY e.id LIMIT 100 FOR UPDATE OF e SKIP LOCKED""",{r,_->stored(r)},after,after,source,source)
            records to work(records)
        }!!
    }
    private fun stored(r:ResultSet)=StoredUsage(r.getObject("id",UUID::class.java),UsageEvent(r.getObject("organization_id",UUID::class.java),r.getString("source"),r.getString("event_id"),r.getObject("user_id",UUID::class.java),r.getObject("project_id",UUID::class.java),r.getString("provider"),r.getString("model"),r.getString("tool"),r.getLong("input_tokens"),r.getLong("output_tokens"),r.getLong("cached_input_tokens"),r.getTimestamp("occurred_at").toInstant(),r.getString("agent_run_id"),r.getString("workflow_type")),r.getString("payload_fingerprint"))
    fun fail(event: StoredUsage, code: String) {
        jdbc.update("INSERT INTO usage.pricing_failures(usage_event_id,code) VALUES (?,?) ON CONFLICT(usage_event_id) DO UPDATE SET code=EXCLUDED.code,attempts=pricing_failures.attempts+1,last_attempt_at=CURRENT_TIMESTAMP",event.id,code)
    }
    fun persist(stored: StoredUsage, mapping: PricingMapping, rate: PricingRate, cost: Cost): UUID? {
        val id=UUID.randomUUID(); val e=stored.event
        val inserted=jdbc.update("""INSERT INTO usage.priced_usage_events(id,usage_event_id,organization_id,pricing_rate_id,pricing_mapping_id,provider,model,pricing_provider,pricing_model,pricing_tier,billing_basis,currency,
            input_tokens,cached_input_tokens,output_tokens,input_rate_snapshot,cached_input_rate_snapshot,output_rate_snapshot,effective_from_snapshot,effective_until_snapshot,source_url_snapshot,verified_at_snapshot,input_cost,cached_input_cost,output_cost,total_cost,calculation_version)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1) ON CONFLICT(usage_event_id) DO NOTHING""",id,stored.id,e.organizationId,rate.id,mapping.id,e.provider,e.model,rate.provider,rate.model,rate.tier,mapping.basis,rate.currency,e.inputTokens,e.cachedInputTokens,e.outputTokens,rate.input,rate.cached,rate.output,Timestamp.from(rate.from),rate.until?.let(Timestamp::from),rate.sourceUrl,Timestamp.from(rate.verifiedAt),cost.input,cost.cached,cost.output,cost.total)
        if(inserted==0) return null
        val payload=payload(id,stored,mapping,rate,cost)
        val json=mapper.writeValueAsString(TreeMap(payload))
        jdbc.update("INSERT INTO usage.delivery_outbox(id,priced_usage_event_id,payload,payload_fingerprint) VALUES (?,?,?::jsonb,?)",UUID.randomUUID(),id,json,sha256(json))
        jdbc.update("DELETE FROM usage.pricing_failures WHERE usage_event_id=?",stored.id)
        return id
    }
    fun payload(id:UUID,s:StoredUsage,m:PricingMapping,r:PricingRate,c:Cost): Map<String,Any?> {
        val e=s.event
        return mapOf("schema_version" to 1,"calculation_version" to 1,"priced_event_id" to id.toString(),"usage_event_id" to s.id.toString(),"organization_id" to e.organizationId.toString(),"user_id" to e.userId.toString(),"project_id" to e.projectId?.toString(),
            "source" to e.source,"source_event_id" to e.eventId,"usage_fingerprint" to s.fingerprint,"provider" to e.provider,"model" to e.model,"tool" to e.tool,"agent_run_id" to e.agentRunId,"workflow_type" to e.workflowType,
            "pricing_provider" to r.provider,"pricing_model" to r.model,"pricing_rate_id" to r.id.toString(),"pricing_mapping_id" to m.id.toString(),"pricing_tier" to r.tier,"billing_basis" to m.basis,"currency" to r.currency,
            "input_tokens" to e.inputTokens,"cached_input_tokens" to e.cachedInputTokens,"output_tokens" to e.outputTokens,"input_rate" to DecimalMoney.text(r.input),"cached_input_rate" to DecimalMoney.text(r.cached),"output_rate" to DecimalMoney.text(r.output),
            "input_cost" to DecimalMoney.text(c.input),"cached_input_cost" to DecimalMoney.text(c.cached),"output_cost" to DecimalMoney.text(c.output),"amount" to DecimalMoney.text(c.total),"occurred_at" to DecimalMoney.time(e.occurredAt),
            "rate_effective_from" to DecimalMoney.time(r.from),"rate_effective_until" to r.until?.let(DecimalMoney::time),"rate_source_url" to r.sourceUrl,"rate_verified_at" to DecimalMoney.time(r.verifiedAt))
    }
    fun counts(source:String?):Map<String,Any> {
        val p=jdbc.queryForMap("SELECT COUNT(*) AS priced,COALESCE(SUM(p.total_cost),0)::text AS total FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id WHERE (?::text IS NULL OR e.source=?::text)",source,source)
        val errors=jdbc.queryForList("SELECT f.code,COUNT(*) AS count FROM usage.pricing_failures f JOIN usage.usage_events e ON e.id=f.usage_event_id WHERE (?::text IS NULL OR e.source=?::text) GROUP BY f.code ORDER BY f.code",source,source)
        return mapOf("priced" to p["priced"]!!,"total_usd" to DecimalMoney.text(BigDecimal(p["total"].toString())),"unpriced_errors" to errors,"examples" to jdbc.queryForList("SELECT e.id AS usage_event_id,e.source,e.provider,e.model,e.occurred_at::text,f.code FROM usage.pricing_failures f JOIN usage.usage_events e ON e.id=f.usage_event_id WHERE (?::text IS NULL OR e.source=?::text) ORDER BY f.last_attempt_at DESC,e.id LIMIT 20",source,source))
    }
}
