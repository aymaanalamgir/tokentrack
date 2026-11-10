package com.tokentrack.usage.analytics

import com.fasterxml.jackson.databind.JsonNode
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.ResponseEntity
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.web.bind.annotation.*
import java.security.MessageDigest
import java.time.Instant
import java.time.Duration
import java.sql.Timestamp
import java.util.UUID

@RestController
class AnalyticsController(private val analytics: UsageAnalytics, @param:Value("\${tokentrack.analytics.token:}") private val token:String) {
    @PostMapping("/internal/v1/analytics")
    fun report(@RequestHeader(value="Authorization",required=false) authorization:String?, @RequestBody body:JsonNode):ResponseEntity<Any> {
        val supplied=authorization?.removePrefix("Bearer ") ?: ""
        if(token.length<32 || authorization?.startsWith("Bearer ")!=true || !MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(token.toByteArray()),MessageDigest.getInstance("SHA-256").digest(supplied.toByteArray())))
            return ResponseEntity.status(401).header("Cache-Control","no-store").body(mapOf("error" to "unauthorized"))
        return try { ResponseEntity.ok().header("Cache-Control","no-store").body(analytics.report(body)) }
        catch (_:IllegalArgumentException) { ResponseEntity.badRequest().header("Cache-Control","no-store").body(mapOf("error" to "invalid_analytics_request")) }
    }
}

@org.springframework.stereotype.Service
class UsageAnalytics(private val jdbc:JdbcTemplate) {
    @org.springframework.transaction.annotation.Transactional(readOnly=true,isolation=org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
    fun report(body:JsonNode):Map<String,Any?> {
        val keys=setOf("organization_id","all_users","scope_users","scope_projects","filter_users","start","end","granularity","project_id","user_id","provider","model","tool")
        require(body.isObject && body.properties().map { it.key }.toSet()==keys)
        fun uuid(n:JsonNode):String { require(n.isTextual && n.asText().matches(Regex("[0-9a-fA-F-]{36}")));return UUID.fromString(n.asText()).toString() }
        fun ids(key:String,max:Int,nullable:Boolean=false):List<String>? { val n=body[key];if(nullable && n.isNull)return null;require(n.isArray && n.size()<=max);return n.map(::uuid).also { require(it.distinct().size==it.size) } }
        val org=uuid(body["organization_id"]);require(body["all_users"].isBoolean)
        val users=ids("scope_users",200)!!;val projects=ids("scope_projects",100)!!;val filterUsers=ids("filter_users",200,true)
        val start=try { Instant.parse(body["start"].asText()) } catch (_:Exception) { throw IllegalArgumentException() }
        val end=try { Instant.parse(body["end"].asText()) } catch (_:Exception) { throw IllegalArgumentException() }
        require(start<end && Duration.between(start,end).seconds<=366L*86400 && start>=Instant.parse("2000-01-01T00:00:00Z") && end<Instant.parse("2100-01-01T00:00:00Z"))
        val grain=body["granularity"].asText();require(grain in setOf("day","week","month"))
        val args=mutableListOf<Any>(UUID.fromString(org))
        fun list(column:String,values:List<String>):String { if(values.isEmpty())return "FALSE"; args.addAll(values.map(UUID::fromString));return "$column IN (${values.joinToString(","){"?"}})" }
        val population=if(body["all_users"].asBoolean()) "TRUE" else "(${list("e.user_id",users)} OR ${list("e.project_id",projects)})"
        val predicates=mutableListOf("e.organization_id=?::uuid",population)
        if(filterUsers!=null)predicates+=list("e.user_id",filterUsers)
        for(key in listOf("project_id","user_id","provider","model","tool")) {
            val node=body[key];if(node.isNull)continue
            val value=if(key.endsWith("_id")) UUID.fromString(uuid(node)) else node.asText().also { require(node.isTextual && it.length in 1..200 && !it.contains('\u0000')) }
            predicates+="e.$key=?";args+=value
        }
        val scopeWhere=predicates.joinToString(" AND ")
        val range=jdbc.queryForMap("SELECT MIN(e.occurred_at) AS start,MAX(e.occurred_at) AS end FROM usage.usage_events e WHERE $scopeWhere",*args.toTypedArray())
        args+=Timestamp.from(start);args+=Timestamp.from(end)
        val base="FROM usage.usage_events e LEFT JOIN usage.priced_usage_events p ON p.usage_event_id=e.id LEFT JOIN usage.pricing_failures f ON f.usage_event_id=e.id LEFT JOIN usage.delivery_outbox o ON o.priced_usage_event_id=p.id WHERE $scopeWhere AND e.occurred_at>=? AND e.occurred_at<?"
        val metrics="COUNT(*) AS events,COUNT(p.id) AS priced_events,COUNT(*)-COUNT(p.id) AS unpriced_events,COALESCE(SUM(e.input_tokens),0) AS input_tokens,COALESCE(SUM(e.output_tokens),0) AS output_tokens,COALESCE(SUM(e.cached_input_tokens),0) AS cached_input_tokens,COUNT(DISTINCT e.user_id) AS active_users,COUNT(DISTINCT e.project_id) AS attributed_projects,COUNT(*) FILTER(WHERE f.code='UNSUPPORTED_PROFILE' AND p.id IS NULL) AS unsupported_profiles,COUNT(*) FILTER(WHERE f.code='MISSING_RATE' AND p.id IS NULL) AS missing_rates,COUNT(*) FILTER(WHERE p.id IS NOT NULL AND o.status IS DISTINCT FROM 'delivered') AS pending_delivery"
        fun rows(sql:String)=jdbc.queryForList(sql,*args.toTypedArray()).map { row -> row.mapValues { (key,v)->if(key=="bucket")v.toString().take(10)+"T00:00:00Z" else if(v is java.math.BigDecimal)v.toPlainString() else v } }
        val totals=rows("SELECT $metrics $base").single()
        fun groups(expression:String,columns:String=expression)=rows("SELECT $columns,$metrics $base GROUP BY $expression ORDER BY events DESC LIMIT 201").also { require(it.size<=200) { "Scope has too many groups; narrow filters" } }
        return mapOf("schema_version" to 1,"available_range" to range.mapValues { (_,value)->if(value is Timestamp)value.toInstant().toString() else value?.toString() },"totals" to totals,
            "timeseries" to rows("SELECT date_trunc('$grain',e.occurred_at AT TIME ZONE 'UTC')::text AS bucket,$metrics $base GROUP BY bucket ORDER BY bucket"),
            "employees" to groups("e.user_id","e.user_id::text AS id"),"projects" to groups("e.project_id","e.project_id::text AS id"),
            "models" to groups("e.provider,e.model,p.pricing_provider,p.pricing_model,p.billing_basis","e.provider,e.model,p.pricing_provider,p.pricing_model,p.billing_basis"),
            "tools" to groups("e.tool","e.tool AS id"))
    }
}
