package com.tokentrack.usage.delivery

import com.tokentrack.usage.domain.ImportFailure
import com.tokentrack.usage.pricing.DecimalMoney
import com.tokentrack.usage.pricing.PricingRepository
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.util.UUID

@Service
class FinancialReconciler(private val jdbc:JdbcTemplate,private val gateway:FinancialGateway,private val pricing:PricingRepository) {
    fun reconcile(source:String?=null):Map<String,Any> {
        var after:UUID?=null
        var priced=0;var posted=0;var pending=0;var dead=0;var held=0;var missing=0;var mismatches=0;var payloadConflicts=0;var missingOutbox=0
        var expected=BigDecimal.ZERO;var gross=BigDecimal.ZERO;var net=BigDecimal.ZERO;var adjustments=BigDecimal.ZERO
        var integrity=emptyMap<String,Int>()
        while(true) {
            val rows=jdbc.queryForList("""SELECT p.id,p.usage_event_id,p.total_cost,o.status,o.payload_fingerprint,o.acknowledged_transaction_id FROM usage.priced_usage_events p JOIN usage.usage_events e ON e.id=p.usage_event_id
                LEFT JOIN usage.delivery_outbox o ON o.priced_usage_event_id=p.id WHERE (?::uuid IS NULL OR p.id>?::uuid) AND (?::text IS NULL OR e.source=?::text) ORDER BY p.id LIMIT 100""",after,after,source,source)
            if(rows.isEmpty()) break
            val response=gateway.reconcile(rows.map { it["id"].toString() })
            val body=response.body
            if(response.status!=200 || body==null || body.path("schema_version").asInt()!=1 || !body.path("data").isArray) throw ImportFailure("FINANCIAL_RECONCILIATION_UNAVAILABLE",true)
            val records=body["data"].associateBy { it.path("priced_event_id").asText() }
            if(records.keys!=rows.map { it["id"].toString() }.toSet() || body["data"].size()!=rows.size) throw ImportFailure("FINANCIAL_RECONCILIATION_PROTOCOL",true)
            val checks=body.path("integrity")
            val names=setOf("duplicate_expenses","unbalanced_transfers","posted_receipts_missing_transactions","invalid_operation_entries")
            if(!checks.isObject || checks.properties().map { it.key }.toSet()!=names || checks.any { !it.isIntegralNumber || it.asInt()<0 }) throw ImportFailure("FINANCIAL_RECONCILIATION_PROTOCOL",true)
            integrity=checks.properties().associate { it.key to it.value.asInt() }
            rows.forEach { row ->
                priced++; val amount=row["total_cost"] as BigDecimal; expected=expected.add(amount)
                val status=row["status"]?.toString(); if(status==null) missingOutbox++ else if(status!="delivered") pending++
                if(status=="dead") dead++
                val receipt=records.getValue(row["id"].toString())
                if(receipt.path("status").asText()=="unresolved") held++
                if(receipt.path("status").asText()=="posted") {
                    posted++
                    if(listOf("original_amount","original_ledger_amount","adjustment_delta","net_amount").any { !receipt.path(it).isTextual }) throw ImportFailure("FINANCIAL_RECONCILIATION_PROTOCOL",true)
                    if(receipt.path("usage_event_id").asText()!=row["usage_event_id"].toString() || receipt.path("posted_usage_event_id").asText()!=row["usage_event_id"].toString()) payloadConflicts++
                    val original=BigDecimal(receipt.path("original_amount").asText()); val originalLedger=BigDecimal(receipt.path("original_ledger_amount").asText()); val delta=BigDecimal(receipt.path("adjustment_delta").asText());val actual=BigDecimal(receipt.path("net_amount").asText())
                    gross=gross.add(original);net=net.add(actual);adjustments=adjustments.add(delta)
                    if(original.compareTo(amount)!=0 || originalLedger.compareTo(amount)!=0 || originalLedger.add(delta).compareTo(actual)!=0) mismatches++
                    if(status=="delivered" && receipt.path("financial_transaction_id").asText()!=row["acknowledged_transaction_id"].toString()) payloadConflicts++
                    if(receipt.path("payload_fingerprint").asText()!=row["payload_fingerprint"].toString()) payloadConflicts++
                } else if(status=="delivered") missing++
            }
            after=rows.last()["id"] as UUID
        }
        val unpriced=jdbc.queryForObject("SELECT COUNT(*) FROM usage.usage_events e WHERE (?::text IS NULL OR e.source=?::text) AND NOT EXISTS(SELECT 1 FROM usage.priced_usage_events p WHERE p.usage_event_id=e.id)",Long::class.java,source,source)!!
        val discrepancy=mismatches+payloadConflicts+missing+missingOutbox+integrity.values.sum()
        val status=when { discrepancy>0 -> "discrepancy"; pending>0 || held>0 -> "pending_delivery";unpriced>0 -> "balanced_with_unpriced_usage";else -> "reconciled" }
        return mapOf("status" to status,"priced_events" to priced,"posted_events" to posted,"pending_delivery" to pending,"dead_deliveries" to dead,"unresolved_charge_owner" to held,
            "delivered_missing_postings" to missing,"missing_outbox" to missingOutbox,"amount_discrepancies" to mismatches,"payload_conflicts" to payloadConflicts,"ledger_integrity" to integrity,
            "priced_total_usd" to DecimalMoney.text(expected),"posted_original_usd" to DecimalMoney.text(gross),"authorized_adjustment_delta_usd" to DecimalMoney.text(adjustments),"net_expenditure_usd" to DecimalMoney.text(net),"unpriced_events" to unpriced,"pricing" to pricing.counts(source))
    }
}
