package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.JsonNode
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.ResponseEntity
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Isolation
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RestController
import java.security.MessageDigest
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID

@RestController
class AgentAnalyticsController(private val analytics:AgentAnalytics,private val insights:AgentInsights,@param:Value("\${tokentrack.analytics.token:}") private val token:String) {
    private fun guarded(authorization:String?,work:()->Any):ResponseEntity<Any> {
        val supplied=authorization?.removePrefix("Bearer ")?:""
        if(token.length<32||authorization?.startsWith("Bearer ")!=true||!MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(token.toByteArray()),MessageDigest.getInstance("SHA-256").digest(supplied.toByteArray()))) return ResponseEntity.status(401).header("Cache-Control","no-store").body(mapOf("error" to "unauthorized"))
        return try { ResponseEntity.ok().header("Cache-Control","no-store").body(work()) } catch (_:IllegalArgumentException) { ResponseEntity.badRequest().header("Cache-Control","no-store").body(mapOf("error" to "invalid_agent_analytics_request")) }
    }
    @PostMapping("/internal/v1/agent-analytics")
    fun report(@RequestHeader(value="Authorization",required=false) authorization:String?,@RequestBody body:JsonNode)=guarded(authorization){analytics.report(body)}
    @PostMapping("/internal/v1/agent-cohort")
    fun cohort(@RequestHeader(value="Authorization",required=false) authorization:String?,@RequestBody body:JsonNode)=guarded(authorization){analytics.cohort(body)}
    @PostMapping("/internal/v1/agent-insights")
    fun insights(@RequestHeader(value="Authorization",required=false) authorization:String?,@RequestBody body:JsonNode)=guarded(authorization){insights.report(body)}
}

/** Parses the Rails-supplied tenant/permission population and filters once; every agent query reuses it. */
class AgentQuery(private val body:JsonNode,extraKeys:Set<String>) {
    companion object {
        val baseKeys=setOf("organization_id","all_users","scope_users","scope_projects","filter_users","start","end","agent_id","run_id","project_id","user_id","workflow_type","status","outcome","retried")
        const val METRICS="COUNT(*) runs,COUNT(*) FILTER(WHERE outcome='success') successful_runs,COUNT(*) FILTER(WHERE outcome='failure') failed_runs,COUNT(*) FILTER(WHERE outcome='cancelled') cancelled_runs,COUNT(*) FILTER(WHERE outcome='unknown') incomplete_runs,COUNT(*) FILTER(WHERE retries>0) retried_runs,COALESCE(SUM(attempts),0) attempts,COALESCE(SUM(retries),0) retries,COALESCE(AVG(retries),0) average_retries,COALESCE(AVG(duration_seconds) FILTER(WHERE duration_seconds IS NOT NULL),0) average_duration_seconds,COALESCE(SUM(input_tokens),0) input_tokens,COALESCE(SUM(output_tokens),0) output_tokens,COALESCE(SUM(cached_input_tokens),0) cached_input_tokens,COALESCE(SUM(usage_events),0) usage_events,COALESCE(SUM(priced_events),0) priced_events,COALESCE(SUM(unpriced_events),0) unpriced_events,COALESCE(SUM(pending_delivery),0) pending_delivery"
        fun facts(select:String,where:String)="""WITH scoped AS (SELECT r.*,d.agent_key,d.name agent_name,d.workflow_type$select FROM usage.agent_runs r JOIN usage.agent_definitions d ON d.id=r.agent_definition_id WHERE $where),
          attempt_stats AS (SELECT a.agent_run_id,COUNT(*) attempts,COUNT(*)-1 retries FROM usage.agent_attempts a JOIN scoped s ON s.id=a.agent_run_id GROUP BY a.agent_run_id),
          usage_stats AS (SELECT s.id run_uuid,COUNT(e.id) usage_events,COUNT(p.id) priced_events,COUNT(e.id)-COUNT(p.id) unpriced_events,COALESCE(SUM(e.input_tokens),0) input_tokens,COALESCE(SUM(e.output_tokens),0) output_tokens,COALESCE(SUM(e.cached_input_tokens),0) cached_input_tokens,COUNT(*) FILTER(WHERE p.id IS NOT NULL AND o.status IS DISTINCT FROM 'delivered') pending_delivery FROM scoped s LEFT JOIN usage.usage_events e ON e.organization_id=s.organization_id AND e.source=s.source AND e.agent_run_id=s.external_run_id LEFT JOIN usage.priced_usage_events p ON p.usage_event_id=e.id LEFT JOIN usage.delivery_outbox o ON o.priced_usage_event_id=p.id GROUP BY s.id),
          facts AS (SELECT s.*,COALESCE(a.attempts,0) attempts,COALESCE(a.retries,0) retries,u.usage_events,u.priced_events,u.unpriced_events,u.input_tokens,u.output_tokens,u.cached_input_tokens,u.pending_delivery,EXTRACT(EPOCH FROM (s.completed_at-s.started_at)) duration_seconds FROM scoped s LEFT JOIN attempt_stats a ON a.agent_run_id=s.id JOIN usage_stats u ON u.run_uuid=s.id) """
    }
    val org:UUID
    /** Tenant, permission population and entity filters, without any time window. */
    val filterSql:String
    val filterArgs:List<Any>
    val hasAgentFilter:Boolean
    private fun uuid(n:JsonNode):UUID { require(n.isTextual);return UUID.fromString(n.asText()) }
    init {
        require(body.isObject&&body.properties().map{it.key}.toSet()==baseKeys+extraKeys)
        fun ids(key:String,max:Int,nullable:Boolean=false):List<UUID>? { val n=body[key];if(nullable&&n.isNull)return null;require(n.isArray&&n.size()<=max);return n.map(::uuid).also{require(it.distinct().size==it.size)} }
        org=uuid(body["organization_id"]);require(body["all_users"].isBoolean);val users=ids("scope_users",200)!!;val projects=ids("scope_projects",100)!!;val filterUsers=ids("filter_users",200,true)
        val args=mutableListOf<Any>(org)
        fun list(column:String,values:List<UUID>):String { if(values.isEmpty())return "FALSE";args.addAll(values);return "$column IN (${values.joinToString(","){"?"}})" }
        val predicates=mutableListOf("r.organization_id=?")
        if(!body["all_users"].asBoolean())predicates+="(${list("r.user_id",users)} OR ${list("r.project_id",projects)})"
        if(filterUsers!=null)predicates+=list("r.user_id",filterUsers)
        fun optionalId(key:String,column:String) { if(!body[key].isNull){args+=uuid(body[key]);predicates+="$column=?"} }
        optionalId("agent_id","r.agent_definition_id");optionalId("project_id","r.project_id");optionalId("user_id","r.user_id")
        for((key,column,allowed) in listOf(Triple("workflow_type","d.workflow_type",emptySet<String>()),Triple("status","r.status",setOf("running","completed","failed","cancelled")),Triple("outcome","r.outcome",setOf("success","failure","cancelled","unknown")))) if(!body[key].isNull){val value=body[key].asText();require(body[key].isTextual&&value.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,63}"))&&(allowed.isEmpty()||value in allowed));args+=value;predicates+="$column=?"}
        if(!body["run_id"].isNull){val value=body["run_id"].asText();require(value.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")));args+=value;predicates+="r.external_run_id=?"}
        if(!body["retried"].isNull){require(body["retried"].isBoolean);predicates+=(if(body["retried"].asBoolean())"" else "NOT ")+"EXISTS(SELECT 1 FROM usage.agent_attempts ra WHERE ra.agent_run_id=r.id AND ra.attempt_number>1)"}
        filterSql=predicates.joinToString(" AND ");filterArgs=args;hasAgentFilter=!body["agent_id"].isNull
    }
    fun instant(key:String):Instant? { val n=body[key];if(n.isNull)return null;require(n.isTextual);return try { Instant.parse(n.asText()) } catch (_:java.time.DateTimeException) { throw IllegalArgumentException("Invalid timestamp") } }
    fun window():Pair<Instant,Instant> { val start=requireNotNull(instant("start"));val end=requireNotNull(instant("end"));require(start<end&&Duration.between(start,end).seconds<=366L*86400);return start to end }
    fun int(key:String,range:IntRange):Int { val n=body[key];require(n.isIntegralNumber&&n.asInt() in range);return n.asInt() }
    fun text(key:String,allowed:Set<String>):String { val n=body[key];require(n.isTextual&&n.asText() in allowed);return n.asText() }
    fun node(key:String):JsonNode=body[key]
}

@Service
class AgentAnalytics(private val jdbc:JdbcTemplate) {
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    fun report(body:JsonNode):Map<String,Any?> {
        val q=AgentQuery(body,setOf("limit","offset"));val (start,end)=q.window();val limit=q.int("limit",1..100);val offset=q.int("offset",0..100_000)
        val args=q.filterArgs+listOf(Timestamp.from(start),Timestamp.from(end));val cte=AgentQuery.facts("","${q.filterSql} AND r.started_at>=? AND r.started_at<?");val metricSql=AgentQuery.METRICS
        fun rows(sql:String,vararg extra:Any)=jdbc.queryForList(sql,*(args+extra).toTypedArray()).map{row->row.mapValues{(_,v)->if(v is java.math.BigDecimal)v.toPlainString() else v}}
        val totals=rows(cte+"SELECT $metricSql FROM facts").single().toMutableMap();val runCount=(totals["runs"] as Number).toLong();totals["retry_rate_percent"]=if(runCount==0L)null else java.math.BigDecimal((totals["retried_runs"] as Number).toString()).multiply(java.math.BigDecimal(100)).divide(java.math.BigDecimal(runCount),6,java.math.RoundingMode.HALF_UP).toPlainString()
        val agents=rows(cte+"SELECT agent_definition_id::text id,agent_key,agent_name name,workflow_type,$metricSql FROM facts GROUP BY agent_definition_id,agent_key,agent_name,workflow_type ORDER BY runs DESC,agent_name LIMIT 200").map { row->row.toMutableMap().also { mutable->val count=(mutable["runs"] as Number).toLong();mutable["retry_rate_percent"]=if(count==0L)null else java.math.BigDecimal((mutable["retried_runs"] as Number).toString()).multiply(java.math.BigDecimal(100)).divide(java.math.BigDecimal(count),6,java.math.RoundingMode.HALF_UP).toPlainString() } }
        val total=rows(cte+"SELECT COUNT(*) total FROM facts").single()["total"]
        val runs=rows(cte+"SELECT id::text id,agent_definition_id::text agent_id,agent_key,agent_name,workflow_type,source,external_run_id run_id,user_id::text,project_id::text,started_at,completed_at,status,outcome,outcome_source,attempts,retries,duration_seconds,input_tokens,output_tokens,cached_input_tokens,usage_events,priced_events,unpriced_events,pending_delivery FROM facts ORDER BY started_at DESC,id LIMIT ? OFFSET ?",limit,offset).map{it.toMutableMap()}
        val runIds=runs.map{UUID.fromString(it["id"].toString())};val attemptMap=if(runIds.isEmpty()) emptyMap() else jdbc.queryForList("SELECT agent_run_id::text run_uuid,external_attempt_id attempt_id,attempt_number,started_at,completed_at,status,error_category FROM usage.agent_attempts WHERE agent_run_id IN (${runIds.joinToString(","){"?"}}) ORDER BY agent_run_id,attempt_number",*runIds.toTypedArray()).groupBy{it["run_uuid"].toString()}
        runs.forEach{it["attempt_records"]=attemptMap[it["id"]]?:emptyList<Map<String,Any?>>()}
        val timeseries=rows(cte+"SELECT date_trunc('day',started_at AT TIME ZONE 'UTC')::date::text bucket,$metricSql FROM facts GROUP BY bucket ORDER BY bucket")
        val synthetic=rows(cte+"SELECT COUNT(*) FILTER(WHERE outcome_source='synthetic_fixture') synthetic_runs FROM facts").single()["synthetic_runs"]
        val available=jdbc.queryForMap("SELECT MIN(started_at) start,MAX(started_at) end FROM usage.agent_runs WHERE organization_id=?",q.org).mapValues{(_,v)->(v as? Timestamp)?.toInstant()?.toString()}
        return mapOf("schema_version" to 2,"available_range" to available,"totals" to totals+mapOf("synthetic_runs" to synthetic),"timeseries" to timeseries,"agents" to agents,"runs" to mapOf("rows" to runs,"total" to total,"limit" to limit,"offset" to offset))
    }

    /**
     * Bounded keyset page of the authorized run cohort. Rails walks every page to attach ledger cost, so
     * cohort size is no longer capped and no page exceeds [batch] rows. Ordered by (started_at,id) on the scope index.
     */
    @Transactional(readOnly=true)
    fun cohort(body:JsonNode):Map<String,Any?> {
        val q=AgentQuery(body,setOf("after_started_at","after_id","batch","bucket"));val (start,end)=q.window();val batch=q.int("batch",1..1000);val bucket=q.text("bucket",setOf("day","week"))
        val afterAt=q.instant("after_started_at");val afterId=q.node("after_id").let{if(it.isNull)null else {require(it.isTextual);UUID.fromString(it.asText())}};require((afterAt==null)==(afterId==null))
        val args=(q.filterArgs+listOf(Timestamp.from(start),Timestamp.from(end))).toMutableList<Any>();var cursor=""
        if(afterAt!=null){cursor=" AND (r.started_at,r.id)>(?,?)";args+=Timestamp.from(afterAt);args+=afterId!!}
        args+=batch
        val rows=jdbc.queryForList("SELECT r.id::text id,r.source,r.external_run_id run_id,r.agent_definition_id::text agent_id,r.outcome,r.started_at,date_trunc('$bucket',r.started_at AT TIME ZONE 'UTC')::date::text bucket,EXISTS(SELECT 1 FROM usage.agent_attempts a WHERE a.agent_run_id=r.id AND a.attempt_number>1) retried FROM usage.agent_runs r JOIN usage.agent_definitions d ON d.id=r.agent_definition_id WHERE ${q.filterSql} AND r.started_at>=? AND r.started_at<?$cursor ORDER BY r.started_at,r.id LIMIT ?",*args.toTypedArray())
        val last=rows.lastOrNull();val next=if(rows.size<batch||last==null)null else mapOf("after_started_at" to (last["started_at"] as Timestamp).toInstant().toString(),"after_id" to last["id"])
        return mapOf("schema_version" to 1,"rows" to rows.map{it-"started_at"-"id"},"next" to next)
    }
}
