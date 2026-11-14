package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.JsonNode
import org.springframework.beans.factory.annotation.Value
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Component
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Isolation
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.math.RoundingMode
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

/**
 * The single home of every anomaly threshold (Slice 9B). Rails reads these from the insight response for its
 * cost rules and the UI only displays them, so no other layer hardcodes a threshold. Demonstration defaults,
 * not statistical truths; override under `tokentrack.agent-insights` in application.yml.
 */
@Component
class InsightThresholds(
    @param:Value("\${tokentrack.agent-insights.min-runs:20}") val minRuns:Int=20,
    @param:Value("\${tokentrack.agent-insights.min-runs-limited:8}") val minRunsLimited:Int=8,
    @param:Value("\${tokentrack.agent-insights.retry-rate-increase-points:10}") val retryRateIncreasePoints:BigDecimal=BigDecimal(10),
    @param:Value("\${tokentrack.agent-insights.success-rate-decrease-points:10}") val successRateDecreasePoints:BigDecimal=BigDecimal(10),
    @param:Value("\${tokentrack.agent-insights.tokens-per-run-increase-percent:30}") val tokensPerRunIncreasePercent:BigDecimal=BigDecimal(30),
    @param:Value("\${tokentrack.agent-insights.duration-increase-percent:30}") val durationIncreasePercent:BigDecimal=BigDecimal(30),
    @param:Value("\${tokentrack.agent-insights.cost-per-success-increase-percent:25}") val costPerSuccessIncreasePercent:BigDecimal=BigDecimal(25),
    @param:Value("\${tokentrack.agent-insights.model-cost-share-percent:70}") val modelCostSharePercent:BigDecimal=BigDecimal(70),
    @param:Value("\${tokentrack.agent-insights.failed-run-cost-share-percent:20}") val failedRunCostSharePercent:BigDecimal=BigDecimal(20),
    @param:Value("\${tokentrack.agent-insights.critical-multiplier:2}") val criticalMultiplier:BigDecimal=BigDecimal(2)
) {
    init { require(minRunsLimited in 1..minRuns&&listOf(retryRateIncreasePoints,successRateDecreasePoints,tokensPerRunIncreasePercent,durationIncreasePercent,costPerSuccessIncreasePercent,modelCostSharePercent,failedRunCostSharePercent).all{it.signum()>0}&&criticalMultiplier>BigDecimal.ONE) }
    fun toMap()=mapOf("min_runs" to minRuns,"min_runs_limited" to minRunsLimited,"retry_rate_increase_points" to retryRateIncreasePoints.toPlainString(),"success_rate_decrease_points" to successRateDecreasePoints.toPlainString(),
        "tokens_per_run_increase_percent" to tokensPerRunIncreasePercent.toPlainString(),"duration_increase_percent" to durationIncreasePercent.toPlainString(),"cost_per_success_increase_percent" to costPerSuccessIncreasePercent.toPlainString(),
        "model_cost_share_percent" to modelCostSharePercent.toPlainString(),"failed_run_cost_share_percent" to failedRunCostSharePercent.toPlainString(),"critical_multiplier" to criticalMultiplier.toPlainString())
}

data class Period(val start:Instant,val end:Instant) { fun toMap()=mapOf("start" to start.toString(),"end" to end.toString()) }
data class Comparison(val mode:String,val current:Period,val baseline:Period,val partial:Boolean,val basis:String)

/** UTC, half-open comparison windows. Partial calendar periods compare equivalent elapsed portions. */
object Periods {
    val modes=setOf("previous_period","week","month")
    fun resolve(mode:String,start:Instant?,end:Instant?,availableEnd:Instant?,now:Instant):Comparison {
        require(mode in modes&&(start==null)==(end==null))
        // Simulated demo data may lie in the future or the past, so "now" for defaults is the day after the last recorded run.
        val dataEnd=(availableEnd?:now).truncatedTo(ChronoUnit.DAYS).plus(1,ChronoUnit.DAYS)
        if(mode=="previous_period") {
            val e=end?:dataEnd;val s=start?:e.minus(14,ChronoUnit.DAYS);require(s<e&&Duration.between(s,e).seconds<=366L*86400)
            return Comparison(mode,Period(s,e),Period(s.minus(Duration.between(s,e)),s),false,"equal_length_preceding_period")
        }
        val anchor=if(end==null)dataEnd else minOf(end,dataEnd).let{if(it<=(start?:it.minusSeconds(1)))end else it}
        val day=anchor.minusMillis(1).atZone(ZoneOffset.UTC).toLocalDate()
        val first=if(mode=="week")day.with(TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY)) else day.withDayOfMonth(1)
        val periodStart=first.atStartOfDay(ZoneOffset.UTC).toInstant()
        val fullEnd=(if(mode=="week")first.plusWeeks(1) else first.plusMonths(1)).atStartOfDay(ZoneOffset.UTC).toInstant()
        val previousStart=(if(mode=="week")first.minusWeeks(1) else first.minusMonths(1)).atStartOfDay(ZoneOffset.UTC).toInstant()
        val currentEnd=minOf(fullEnd,anchor);val partial=currentEnd<fullEnd
        val baselineEnd=if(partial)minOf(previousStart.plus(Duration.between(periodStart,currentEnd)),periodStart) else periodStart
        return Comparison(mode,Period(periodStart,currentEnd),Period(previousStart,baselineEnd),partial,if(partial)"equivalent_elapsed_portion" else "complete_calendar_period")
    }
}

/** Pure, database-free derivations and detection rules so every formula is unit-testable and defined once. */
object InsightRules {
    private val hundred=BigDecimal(100)
    private fun num(row:Map<String,Any?>,key:String)=row[key]?.toString()?.toBigDecimalOrNull()?:BigDecimal.ZERO
    private fun count(row:Map<String,Any?>,key:String)=num(row,key).toLong()
    fun plain(value:BigDecimal):String=value.setScale(4,RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
    private fun ratio(n:BigDecimal,d:BigDecimal,scale:BigDecimal=BigDecimal.ONE)=if(d.signum()==0)null else n.multiply(scale).divide(d,6,RoundingMode.HALF_UP)

    /** Adds the rate and per-run metrics that 9A defines; missing denominators yield null, never zero. */
    fun derive(row:Map<String,Any?>):MutableMap<String,Any?> {
        val out=row.toMutableMap();val concluded=num(row,"successful_runs")+num(row,"failed_runs")+num(row,"cancelled_runs");val linked=num(row,"linked_runs")
        out["concluded_runs"]=concluded.toLong()
        out["success_rate_percent"]=ratio(num(row,"successful_runs"),concluded,hundred)?.let(::plain)
        out["retry_rate_percent"]=ratio(num(row,"retried_runs"),num(row,"runs"),hundred)?.let(::plain)
        out["input_tokens_per_run"]=ratio(num(row,"input_tokens"),linked)?.let(::plain)
        out["output_tokens_per_run"]=ratio(num(row,"output_tokens"),linked)?.let(::plain)
        out["cached_input_tokens_per_run"]=ratio(num(row,"cached_input_tokens"),linked)?.let(::plain)
        out["total_tokens_per_run"]=ratio(num(row,"input_tokens")+num(row,"output_tokens"),linked)?.let(::plain)
        out["pricing_coverage_percent"]=ratio(num(row,"priced_events"),num(row,"usage_events"),hundred)?.let(::plain)
        out["median_duration_seconds"]=row["median_duration_seconds"]?.toString()?.toBigDecimalOrNull()?.let(::plain)
        out["average_duration_seconds"]=if(count(row,"timed_runs")==0L)null else plain(num(row,"average_duration_seconds"))
        return out
    }

    /** A period with no runs: explicit zero counts and null rates, so "no activity" is never confused with a missing field. */
    fun empty():MutableMap<String,Any?> =derive(listOf("runs","successful_runs","failed_runs","cancelled_runs","incomplete_runs","retried_runs","attempts","retries","input_tokens","output_tokens","cached_input_tokens","usage_events","priced_events","unpriced_events","pending_delivery","linked_runs","timed_runs","synthetic_runs").associateWith{0L})

    fun quality(baseline:Long,current:Long,t:InsightThresholds)=when {
        baseline==0L&&current==0L->"no_data"
        baseline==0L||current==0L->"unsupported_comparison"
        minOf(baseline,current)<t.minRunsLimited->"insufficient_data"
        minOf(baseline,current)<t.minRuns->"limited_sample"
        else->"sufficient"
    }
    fun reason(quality:String,baseline:Long,current:Long,noun:String,t:InsightThresholds)=when(quality) {
        "sufficient"->"$current current and $baseline comparison $noun meet the ${t.minRuns}-per-period minimum."
        "limited_sample"->"$current current and $baseline comparison $noun; ${t.minRuns} per period are required for a definitive finding."
        "insufficient_data"->"Insufficient data: $current current and $baseline comparison $noun, below the ${t.minRunsLimited}-per-period floor for any comparison."
        "no_data"->"No $noun in either period."
        else->"No $noun in the ${if(baseline==0L)"comparison" else "current"} period, so a change cannot be measured."
    }

    /**
     * One deterministic rule. `points` compares an absolute change in percentage points; `percent` a relative change
     * and is skipped for a zero baseline (never an infinite percentage). `direction` is -1 for a deterioration that is a decrease.
     */
    fun evaluate(type:String,metric:String,unit:String,kind:String,threshold:BigDecimal,baseline:BigDecimal?,current:BigDecimal?,baselineSample:Long,currentSample:Long,sampleBasis:String,t:InsightThresholds,direction:Int=1):MutableMap<String,Any?>? {
        if(baseline==null||current==null)return null
        val q=quality(baselineSample,currentSample,t);if(q!="sufficient"&&q!="limited_sample")return null
        val delta=current-baseline;val percent=if(baseline.signum()>0)delta.multiply(hundred).divide(baseline,6,RoundingMode.HALF_UP) else null
        val measure=(if(kind=="points")delta else percent?:return null).multiply(BigDecimal(direction))
        if(measure<threshold)return null
        val severity=if(q=="limited_sample")"info" else if(measure>=threshold.multiply(t.criticalMultiplier))"critical" else "warning"
        return mutableMapOf("type" to type,"metric" to metric,"unit" to unit,"baseline" to plain(baseline),"current" to plain(current),"absolute_change" to plain(delta),"percent_change" to percent?.let(::plain),
            "threshold" to mapOf("kind" to kind,"value" to threshold.toPlainString()),"severity" to severity,"evidence_quality" to q,"quality_reason" to reason(q,baselineSample,currentSample,sampleBasis,t),
            "sample_size" to mapOf("baseline_runs" to baselineSample,"current_runs" to currentSample,"basis" to sampleBasis))
    }

    /** Operational findings for one agent from two derived period rows. Cost findings are added by Rails. */
    fun detect(baseline:Map<String,Any?>,current:Map<String,Any?>,errors:Map<String,Map<String,Long>>,t:InsightThresholds):List<MutableMap<String,Any?>> {
        fun dec(row:Map<String,Any?>,key:String)=row[key]?.toString()?.toBigDecimalOrNull()
        fun pick(row:Map<String,Any?>,vararg keys:String)=keys.associateWith{row[it]}
        val found=mutableListOf<MutableMap<String,Any?>>()
        evaluate("retry_increase","retry_rate_percent","percent","points",t.retryRateIncreasePoints,dec(baseline,"retry_rate_percent"),dec(current,"retry_rate_percent"),count(baseline,"runs"),count(current,"runs"),"runs",t)?.also {
            it["evidence"]=mapOf("baseline" to pick(baseline,"runs","retried_runs","retries","attempts")+mapOf("failed_attempts_by_error" to (errors["baseline"]?:emptyMap())),"current" to pick(current,"runs","retried_runs","retries","attempts")+mapOf("failed_attempts_by_error" to (errors["current"]?:emptyMap())),"source" to "Recorded attempt history; retries are never inferred from usage-event counts.")
            found+=it }
        evaluate("success_rate_decline","success_rate_percent","percent","points",t.successRateDecreasePoints,dec(baseline,"success_rate_percent"),dec(current,"success_rate_percent"),count(baseline,"concluded_runs"),count(current,"concluded_runs"),"concluded runs",t,-1)?.also {
            it["evidence"]=mapOf("baseline" to pick(baseline,"runs","successful_runs","failed_runs","cancelled_runs","incomplete_runs"),"current" to pick(current,"runs","successful_runs","failed_runs","cancelled_runs","incomplete_runs"),"source" to "Explicit imported outcomes; running/unknown runs are excluded from the rate, not counted as failures.")
            found+=it }
        for((type,metric) in listOf("input_token_spike" to "input_tokens_per_run","output_token_spike" to "output_tokens_per_run")) evaluate(type,metric,"tokens","percent",t.tokensPerRunIncreasePercent,dec(baseline,metric),dec(current,metric),count(baseline,"linked_runs"),count(current,"linked_runs"),"runs with linked usage",t)?.also {
            val keys=arrayOf("runs","linked_runs","input_tokens","output_tokens","cached_input_tokens","input_tokens_per_run","output_tokens_per_run","total_tokens_per_run","success_rate_percent")
            it["evidence"]=mapOf("baseline" to pick(baseline,*keys),"current" to pick(current,*keys),"source" to "Canonical usage events linked by organization, source and run ID, normalized by runs with linked usage.")
            found+=it }
        evaluate("duration_increase","median_duration_seconds","seconds","percent",t.durationIncreasePercent,dec(baseline,"median_duration_seconds"),dec(current,"median_duration_seconds"),count(baseline,"timed_runs"),count(current,"timed_runs"),"completed runs",t)?.also {
            it["evidence"]=mapOf("baseline" to pick(baseline,"timed_runs","median_duration_seconds","average_duration_seconds"),"current" to pick(current,"timed_runs","median_duration_seconds","average_duration_seconds"),"source" to "Median completion minus start; the median limits distortion from a few extreme runs.")
            found+=it }
        return found
    }

    /**
     * Hypothetical rate-only comparison: the model's recorded priced tokens re-rated under another published schedule.
     * Linear in tokens, so aggregate sums give the exact same result as per-event re-rating.
     */
    fun rateScenario(model:Map<String,Any?>,rates:List<Map<String,Any?>>):Map<String,Any?>? {
        val provider=model["pricing_provider"]?:return null;val name=model["pricing_model"];val tier=model["pricing_tier"]
        if(count(model,"pricing_profiles")!=1L||count(model,"priced_events")==0L)return null
        val input=num(model,"priced_input_tokens");val cached=num(model,"priced_cached_input_tokens");val output=num(model,"priced_output_tokens");val recorded=num(model,"modeled_cost")
        val million=BigDecimal(1_000_000)
        val best=rates.filter{it["pricing_tier"]==tier&&!(it["provider"]==provider&&it["model"]==name)}.map { rate->
            rate to ((input-cached)*num(rate,"input_rate")+cached*num(rate,"cached_input_rate")+output*num(rate,"output_rate")).divide(million,15,RoundingMode.HALF_UP)
        }.minWithOrNull(compareBy<Pair<Map<String,Any?>,BigDecimal>>{it.second}.thenBy{"${it.first["provider"]}/${it.first["model"]}"})?:return null
        if(best.second>=recorded)return null
        fun money(v:BigDecimal)=v.setScale(15,RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
        return mapOf("label" to "Hypothetical rate-only comparison","recorded_pricing_model" to "$provider/$name","alternative_pricing_model" to "${best.first["provider"]}/${best.first["model"]}",
            "priced_events" to count(model,"priced_events"),"input_tokens" to input.toPlainString(),"cached_input_tokens" to cached.toPlainString(),"output_tokens" to output.toPlainString(),
            "modeled_cost_at_recorded_rates" to money(recorded),"modeled_cost_at_alternative_rates" to money(best.second),"modeled_difference" to money(recorded-best.second),
            "basis" to "Recorded priced-snapshot cost before ledger corrections; not actual ledger expenditure.")
    }
}

@Service
class AgentInsights(private val jdbc:JdbcTemplate,private val thresholds:InsightThresholds) {
    private val metrics=AgentQuery.METRICS+",COUNT(*) FILTER(WHERE usage_events>0) linked_runs,COUNT(*) FILTER(WHERE duration_seconds IS NOT NULL) timed_runs,percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_seconds) FILTER(WHERE duration_seconds IS NOT NULL) median_duration_seconds,COUNT(*) FILTER(WHERE outcome_source='synthetic_fixture') synthetic_runs"

    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    fun report(body:JsonNode,now:Instant=Instant.now()):Map<String,Any?> {
        val q=AgentQuery(body,setOf("compare"))
        val available=jdbc.queryForMap("SELECT MIN(started_at) start,MAX(started_at) end FROM usage.agent_runs WHERE organization_id=?",q.org).mapValues{(_,v)->(v as? Timestamp)?.toInstant()}
        val cmp=Periods.resolve(q.text("compare",Periods.modes),q.instant("start"),q.instant("end"),available["end"],now)
        val (b,c)=cmp.baseline to cmp.current
        val visible=!q.hasAgentFilter||jdbc.queryForObject("SELECT EXISTS(SELECT 1 FROM usage.agent_runs r JOIN usage.agent_definitions d ON d.id=r.agent_definition_id WHERE ${q.filterSql})",Boolean::class.java,*q.filterArgs.toTypedArray())==true
        val span=Duration.between(minOf(b.start,c.start),c.end).toDays();val bucket=if(span>62)"week" else "day"
        val cte=AgentQuery.facts(",CASE WHEN r.started_at>=? AND r.started_at<? THEN 'current' ELSE 'baseline' END period","${q.filterSql} AND ((r.started_at>=? AND r.started_at<?) OR (r.started_at>=? AND r.started_at<?))")
        val args=listOf<Any>(Timestamp.from(c.start),Timestamp.from(c.end))+q.filterArgs+listOf(b.start,b.end,c.start,c.end).map(Timestamp::from)
        fun rows(sql:String)=jdbc.queryForList(cte+sql,*args.toTypedArray()).map{row->row.mapValues{(_,v)->when(v){is BigDecimal->v.toPlainString();is Double->BigDecimal.valueOf(v).setScale(3,RoundingMode.HALF_UP).toPlainString();else->v}}}
        val agentRows=rows("SELECT agent_definition_id::text id,agent_key,agent_name name,workflow_type,period,$metrics FROM facts GROUP BY agent_definition_id,agent_key,agent_name,workflow_type,period ORDER BY agent_name,agent_definition_id,period LIMIT 401")
        require(agentRows.size<=400){"Too many agent definitions; narrow filters"}
        val totals=rows("SELECT period,$metrics FROM facts GROUP BY period").associate{it["period"].toString() to InsightRules.derive(it-"period")}
        val trend=rows("SELECT date_trunc('$bucket',started_at AT TIME ZONE 'UTC')::date::text bucket,period,$metrics FROM facts GROUP BY bucket,period ORDER BY bucket,period").map{InsightRules.derive(it)}
        val link="JOIN usage.usage_events e ON e.organization_id=s.organization_id AND e.source=s.source AND e.agent_run_id=s.external_run_id LEFT JOIN usage.priced_usage_events p ON p.usage_event_id=e.id"
        val modelRows=rows("SELECT s.agent_definition_id::text agent_id,s.period,e.provider,e.model,MAX(p.pricing_provider) pricing_provider,MAX(p.pricing_model) pricing_model,MAX(p.pricing_tier) pricing_tier,COUNT(DISTINCT (p.pricing_provider,p.pricing_model,p.pricing_tier)) FILTER(WHERE p.id IS NOT NULL) pricing_profiles,COUNT(e.id) events,COUNT(p.id) priced_events,SUM(e.input_tokens) input_tokens,SUM(e.output_tokens) output_tokens,SUM(e.cached_input_tokens) cached_input_tokens,COALESCE(SUM(p.input_tokens),0) priced_input_tokens,COALESCE(SUM(p.cached_input_tokens),0) priced_cached_input_tokens,COALESCE(SUM(p.output_tokens),0) priced_output_tokens,COALESCE(SUM(p.total_cost),0) modeled_cost,string_agg(DISTINCT p.pricing_rate_id::text,',') rate_ids FROM scoped s $link GROUP BY s.agent_definition_id,s.period,e.provider,e.model ORDER BY e.provider,e.model")
        val errorRows=rows("SELECT s.agent_definition_id::text agent_id,s.period,a.error_category,COUNT(*) failed_attempts FROM scoped s JOIN usage.agent_attempts a ON a.agent_run_id=s.id WHERE a.status='failed' GROUP BY s.agent_definition_id,s.period,a.error_category")
        val at=Timestamp.from(c.end.minusSeconds(1))
        val rates=jdbc.queryForList("SELECT provider,model,pricing_tier,input_rate_per_million input_rate,cached_input_rate_per_million cached_input_rate,output_rate_per_million output_rate FROM usage.model_pricing_rates WHERE NOT synthetic AND currency='USD' AND effective_from<=? AND (effective_until IS NULL OR effective_until>?) ORDER BY provider,model",at,at)
        val empty=InsightRules.empty()
        val insights=mutableListOf<Map<String,Any?>>()
        val agents=agentRows.groupBy{it["id"].toString()}.map { (id,periods)->
            val first=periods.first();val baseline=periods.firstOrNull{it["period"]=="baseline"}?.let{InsightRules.derive(it-setOf("id","agent_key","name","workflow_type","period"))}?:empty
            val current=periods.firstOrNull{it["period"]=="current"}?.let{InsightRules.derive(it-setOf("id","agent_key","name","workflow_type","period"))}?:empty
            val bRuns=(baseline["runs"]?.toString()?.toLong())?:0L;val cRuns=(current["runs"]?.toString()?.toLong())?:0L;val state=InsightRules.quality(bRuns,cRuns,thresholds)
            val errors=errorRows.filter{it["agent_id"]==id}.groupBy{it["period"].toString()}.mapValues{(_,v)->v.associate{it["error_category"].toString() to (it["failed_attempts"] as Number).toLong()}}
            InsightRules.detect(baseline,current,errors,thresholds).forEach{insights+=it+mapOf("agent_id" to id)}
            val models=modelRows.filter{it["agent_id"]==id}.groupBy{"${it["provider"]}/${it["model"]}"}.map { (_,rowsForModel)->
                fun side(period:String):Map<String,Any?>? { val row=rowsForModel.firstOrNull{it["period"]==period}?:return null
                    val all=modelRows.filter{it["agent_id"]==id&&it["period"]==period}.sumOf{BigDecimal(it["input_tokens"].toString())+BigDecimal(it["output_tokens"].toString())}
                    val own=BigDecimal(row["input_tokens"].toString())+BigDecimal(row["output_tokens"].toString())
                    return mapOf("events" to row["events"],"priced_events" to row["priced_events"],"input_tokens" to row["input_tokens"],"output_tokens" to row["output_tokens"],"cached_input_tokens" to row["cached_input_tokens"],"token_share_percent" to if(all.signum()==0)null else InsightRules.plain(own.multiply(BigDecimal(100)).divide(all,6,RoundingMode.HALF_UP)),"rate_ids" to (row["rate_ids"]?.toString()?.split(',')?.sorted()?:emptyList<String>())) }
                val any=rowsForModel.first();val cur=rowsForModel.firstOrNull{it["period"]=="current"};val bSide=side("baseline");val cSide=side("current")
                val bRates=bSide?.get("rate_ids") as List<*>?;val cRates=cSide?.get("rate_ids") as List<*>?
                mapOf("provider" to any["provider"],"model" to any["model"],"pricing_provider" to rowsForModel.firstNotNullOfOrNull{it["pricing_provider"]},"pricing_model" to rowsForModel.firstNotNullOfOrNull{it["pricing_model"]},"baseline" to bSide,"current" to cSide,
                    "rate_schedule_changed" to (!bRates.isNullOrEmpty()&&!cRates.isNullOrEmpty()&&bRates!=cRates),"rate_only_scenario" to cur?.let{InsightRules.rateScenario(it,rates)})
            }
            mapOf("id" to id,"agent_key" to first["agent_key"],"name" to first["name"],"workflow_type" to first["workflow_type"],"baseline" to baseline,"current" to current,
                "evidence_state" to state,"evidence_reason" to InsightRules.reason(state,bRuns,cRuns,"runs",thresholds),"models" to models)
        }
        val order=mapOf("critical" to 0,"warning" to 1,"info" to 2)
        return mapOf("schema_version" to 1,"analysis_version" to 1,"compare" to cmp.mode,"current_period" to c.toMap(),"comparison_period" to b.toMap(),"partial_current_period" to cmp.partial,"comparison_basis" to cmp.basis,"trend_bucket" to bucket,
            "available_range" to available.mapValues{(_,v)->v?.toString()},"agent_visible" to visible,"thresholds" to thresholds.toMap(),"totals" to mapOf("baseline" to (totals["baseline"]?:empty),"current" to (totals["current"]?:empty)),
            "trend" to trend,"agents" to agents,"insights" to insights.sortedWith(compareBy({order[it["severity"]]},{it["agent_id"].toString()},{it["type"].toString()})))
    }
}
