package com.tokentrack.usage.delivery

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.support.TransactionTemplate
import java.util.UUID

data class DeliveryMessage(val id:UUID,val pricedId:UUID,val payload:String,val token:UUID,val attempt:Int)
@Repository
class OutboxRepository(private val jdbc:JdbcTemplate,manager:PlatformTransactionManager,private val mapper:ObjectMapper) {
    private val transaction=TransactionTemplate(manager)
    fun resetDead():Int=jdbc.update("UPDATE usage.delivery_outbox SET status='pending',cycle_attempts=0,next_attempt_at=CURRENT_TIMESTAMP,last_error_code=NULL WHERE status='dead'")
    fun claim(limit:Int):List<DeliveryMessage> = transaction.execute {
        jdbc.update("""UPDATE usage.delivery_attempts a SET outcome='abandoned',completed_at=CURRENT_TIMESTAMP,error_code='LEASE_EXPIRED' FROM usage.delivery_outbox o
            WHERE a.lease_token=o.lease_token AND o.status='delivering' AND o.lease_until<CURRENT_TIMESTAMP AND a.outcome='in_progress'""")
        jdbc.update("""UPDATE usage.delivery_outbox SET status='dead',last_error_code='RETRY_EXHAUSTED',lease_token=NULL,lease_until=NULL
            WHERE status='delivering' AND lease_until<CURRENT_TIMESTAMP AND cycle_attempts>=8""")
        val records=jdbc.queryForList("""SELECT id,priced_usage_event_id,payload::text,cycle_attempts,attempts FROM usage.delivery_outbox
            WHERE ((status IN('pending','retry') AND next_attempt_at<=CURRENT_TIMESTAMP) OR (status='delivering' AND lease_until<CURRENT_TIMESTAMP))
            AND cycle_attempts<8 ORDER BY next_attempt_at,id LIMIT ? FOR UPDATE SKIP LOCKED""",limit.coerceIn(1,100))
        records.map { row ->
            val id=row["id"] as UUID; val token=UUID.randomUUID(); val attempt=(row["cycle_attempts"] as Number).toInt()+1
            jdbc.update("UPDATE usage.delivery_outbox SET status='delivering',attempts=attempts+1,cycle_attempts=cycle_attempts+1,lease_token=?,lease_until=CURRENT_TIMESTAMP+INTERVAL '60 seconds' WHERE id=?",token,id)
            jdbc.update("INSERT INTO usage.delivery_attempts(id,outbox_id,attempt_number,lease_token) VALUES (?,?,?,?)",UUID.randomUUID(),id,(row["attempts"] as Number).toInt()+1,token)
            DeliveryMessage(id,row["priced_usage_event_id"] as UUID,row["payload"].toString(),token,attempt)
        }
    }!!
    fun finish(message:DeliveryMessage,result:FinancialResponse):String = transaction.execute {
        val payload=mapper.readTree(message.payload)
        val body=result.body
        val acknowledged=result.status in listOf(200,201) && body!=null && body.path("schema_version").asInt()==1 && body.path("status").asText()=="posted" &&
            body.path("priced_event_id").asText()==message.pricedId.toString() && body.path("usage_event_id").asText()==payload["usage_event_id"].asText() &&
            body.path("currency").asText()==payload["currency"].asText() && body.path("amount").isTextual && body.path("amount").asText()==payload["amount"].asText() &&
            runCatching { UUID.fromString(body.path("financial_transaction_id").asText()) }.isSuccess
        val permanent=result.status in listOf(400,401,403,404,409,413,415,422)
        val state=if(acknowledged) "delivered" else if(permanent || message.attempt>=8) "dead" else "retry"
        val error=when {
            acknowledged -> null
            result.status in listOf(401,403) -> "AUTHENTICATION_FAILED"
            result.status==409 -> "PAYLOAD_CONFLICT"
            result.status==202 -> "CHARGE_OWNER_UNRESOLVED"
            permanent -> "PERMANENT_VALIDATION_FAILURE"
            message.attempt>=8 -> "RETRY_EXHAUSTED"
            result.status==0 -> "FINANCIAL_SERVICE_UNAVAILABLE"
            result.status>=500 || result.status in listOf(408,429) -> "TEMPORARY_HTTP_FAILURE"
            else -> "INVALID_ACKNOWLEDGMENT"
        }
        val seconds=(5L shl (message.attempt-1).coerceAtMost(6)).coerceAtMost(300)
        val updated=jdbc.update("""UPDATE usage.delivery_outbox SET status=?,last_error_code=?,last_http_status=?,next_attempt_at=CURRENT_TIMESTAMP+(?*INTERVAL '1 second'),lease_token=NULL,lease_until=NULL,
            acknowledged_transaction_id=?::uuid,delivered_at=CASE WHEN ?='delivered' THEN CURRENT_TIMESTAMP ELSE NULL END WHERE id=? AND status='delivering' AND lease_token=?""",
            state,error,result.status.takeUnless { it==0 },seconds,if(acknowledged) body!!["financial_transaction_id"].asText() else null,state,message.id,message.token)
        val outcome=if(updated==1) state else "lease_lost"
        jdbc.update("UPDATE usage.delivery_attempts SET outcome=?,completed_at=CURRENT_TIMESTAMP,error_code=?,http_status=? WHERE lease_token=? AND outcome='in_progress'",outcome,error,result.status.takeUnless { it==0 },message.token)
        outcome
    }!!
    fun report():Map<String,Any> = mapOf("states" to jdbc.queryForList("SELECT status,COUNT(*) AS count FROM usage.delivery_outbox GROUP BY status ORDER BY status"),
        "failures" to jdbc.queryForList("SELECT last_error_code,COUNT(*) AS count FROM usage.delivery_outbox WHERE last_error_code IS NOT NULL GROUP BY last_error_code ORDER BY last_error_code"),
        "recent_attempts" to jdbc.queryForList("SELECT outbox_id,attempt_number,outcome,error_code,http_status,started_at,completed_at FROM usage.delivery_attempts ORDER BY started_at DESC LIMIT 20"))
}
