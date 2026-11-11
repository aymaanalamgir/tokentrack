package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import com.tokentrack.usage.domain.UsageReference
import com.tokentrack.usage.domain.sha256
import com.tokentrack.usage.references.ReferenceResolver
import org.springframework.dao.DuplicateKeyException
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.support.TransactionTemplate
import java.nio.file.Files
import java.nio.file.Path
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID

data class AgentAttempt(val id:String,val number:Int,val startedAt:Instant,val completedAt:Instant?,val status:String,val errorCategory:String?)
data class AgentRecord(
    val organizationId:UUID,val source:String,val runId:String,val agentKey:String,val agentName:String,val description:String?,
    val workflowType:String,val ownerUserId:UUID,val agentProjectId:UUID?,val agentStatus:String,val userId:UUID,val projectId:UUID?,
    val startedAt:Instant,val completedAt:Instant?,val status:String,val outcome:String,val outcomeSource:String,val attempts:List<AgentAttempt>
) {
    private fun canonical(values:List<Any?>)=values.joinToString(""){ value->value?.toString()?.let{"${it.toByteArray().size}:$it"}?:"-1:" }
    fun definitionFingerprint()=sha256(canonical(listOf("1",organizationId,source,agentKey,agentName,description,workflowType,ownerUserId,agentProjectId,agentStatus)))
    fun fingerprint()=sha256(canonical(listOf("1",organizationId,source,runId,agentKey,userId,projectId,startedAt,completedAt,status,outcome,outcomeSource)+attempts.flatMap{listOf(it.id,it.number,it.startedAt,it.completedAt,it.status,it.errorCategory)}))
}

@Service
class AgentExecutionService(private val jdbc:JdbcTemplate,private val tx:TransactionTemplate,private val mapper:ObjectMapper,private val references:ReferenceResolver) {
    private val sourcePattern=Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,63}")
    private val keyPattern=Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
    fun importFile(path:Path,expectedSource:String):Map<String,Any?> {
        require(expectedSource.matches(sourcePattern) && Files.isRegularFile(path) && Files.size(path)<=20_000_000)
        val batch=UUID.randomUUID();jdbc.update("INSERT INTO usage.agent_import_batches(id,source,input_label,status) VALUES (?::uuid,?,?,'running')",batch,expectedSource,path.fileName.toString())
        val parsed=mutableListOf<Pair<Int,AgentRecord>>();var total=0;var rejected=0
        Files.newBufferedReader(path).useLines { lines->lines.forEach { raw->
            total++;try { require(raw.toByteArray().size<=256_000);parsed+=total to parse(mapper.readTree(raw),expectedSource) }
            catch (_:Exception) { reject(batch,total,"INVALID_AGENT_EXECUTION","record");rejected++ }
        }}
        val validation=try { references.validate(parsed.flatMap{(_,r)->listOf(UsageReference(r.organizationId,r.userId,r.projectId,r.startedAt),UsageReference(r.organizationId,r.ownerUserId,r.agentProjectId,r.startedAt))}) }
        catch (error:Exception) { jdbc.update("UPDATE usage.agent_import_batches SET status='failed',total_rows=?,rejected_rows=?,completed_at=now(),failure_code='REFERENCE_SERVICE_UNAVAILABLE' WHERE id=?",total,rejected,batch);throw error }
        var imported=0;var duplicates=0;var unlinked=0
        parsed.forEach { (line,record)->
            val invalid=validation[UsageReference(record.organizationId,record.userId,record.projectId,record.startedAt).key()]
                ?:validation[UsageReference(record.organizationId,record.ownerUserId,record.agentProjectId,record.startedAt).key()]
            if(invalid!=null) { reject(batch,line,invalid.code,invalid.field);rejected++;return@forEach }
            try {
                val result=tx.execute<Map<String,Int>> { persist(record) }!!;imported+=result.getValue("imported");duplicates+=result.getValue("duplicate");unlinked+=result.getValue("unlinked")
            } catch (_:IllegalStateException) { reject(batch,line,"IDENTITY_CONFLICT","run_id");rejected++ }
              catch (_:DuplicateKeyException) { reject(batch,line,"IDENTITY_CONFLICT","run_id");rejected++ }
        }
        val status=if(rejected==0)"completed" else "completed_with_rejections"
        jdbc.update("UPDATE usage.agent_import_batches SET status=?,total_rows=?,imported_rows=?,duplicate_rows=?,rejected_rows=?,unlinked_rows=?,completed_at=now() WHERE id=?",status,total,imported,duplicates,rejected,unlinked,batch)
        return report(batch)
    }
    fun report(id:UUID):Map<String,Any?> {
        val batch=jdbc.queryForMap("SELECT id::text,source,input_label,status,total_rows,imported_rows,duplicate_rows,rejected_rows,unlinked_rows,started_at,completed_at,failure_code FROM usage.agent_import_batches WHERE id=?",id)
        val rows=jdbc.queryForList("SELECT line_number,code,field FROM usage.agent_import_rejections WHERE batch_id=? ORDER BY line_number LIMIT 100",id)
        return mapOf("schema_version" to 1,"batch" to batch,"rejections" to rows)
    }
    private fun reject(batch:UUID,line:Int,code:String,field:String)=jdbc.update("INSERT INTO usage.agent_import_rejections(batch_id,line_number,code,field) VALUES (?,?,?,?)",batch,line,code,field)
    private fun persist(r:AgentRecord):Map<String,Int> {
        val definitionId=stableUuid("agent/${r.organizationId}/${r.source}/${r.agentKey}")
        val existingDefinition=jdbc.queryForList("SELECT fingerprint FROM usage.agent_definitions WHERE organization_id=? AND source=? AND agent_key=?",r.organizationId,r.source,r.agentKey).firstOrNull()
        if(existingDefinition==null) jdbc.update("INSERT INTO usage.agent_definitions(id,organization_id,source,agent_key,name,description,workflow_type,owner_user_id,project_id,status,fingerprint) VALUES (?,?,?,?,?,?,?,?,?,?,?)",definitionId,r.organizationId,r.source,r.agentKey,r.agentName,r.description,r.workflowType,r.ownerUserId,r.agentProjectId,r.agentStatus,r.definitionFingerprint())
        else check(existingDefinition["fingerprint"]==r.definitionFingerprint())
        val existing=jdbc.queryForList("SELECT fingerprint FROM usage.agent_runs WHERE organization_id=? AND source=? AND external_run_id=?",r.organizationId,r.source,r.runId).firstOrNull()
        if(existing!=null) { check(existing["fingerprint"]==r.fingerprint());return mapOf("imported" to 0,"duplicate" to 1,"unlinked" to 0) }
        val runUuid=stableUuid("run/${r.organizationId}/${r.source}/${r.runId}")
        jdbc.update("INSERT INTO usage.agent_runs(id,organization_id,agent_definition_id,source,external_run_id,user_id,project_id,started_at,completed_at,status,outcome,outcome_source,fingerprint) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",runUuid,r.organizationId,definitionId,r.source,r.runId,r.userId,r.projectId,Timestamp.from(r.startedAt),r.completedAt?.let(Timestamp::from),r.status,r.outcome,r.outcomeSource,r.fingerprint())
        r.attempts.forEach { a->jdbc.update("INSERT INTO usage.agent_attempts(id,organization_id,agent_run_id,external_attempt_id,attempt_number,started_at,completed_at,status,error_category,fingerprint) VALUES (?,?,?,?,?,?,?,?,?,?)",stableUuid("attempt/$runUuid/${a.id}"),r.organizationId,runUuid,a.id,a.number,Timestamp.from(a.startedAt),a.completedAt?.let(Timestamp::from),a.status,a.errorCategory,sha256("${a.id}/${a.number}/${a.startedAt}/${a.completedAt}/${a.status}/${a.errorCategory}")) }
        val linked=jdbc.queryForObject("SELECT EXISTS(SELECT 1 FROM usage.usage_events WHERE organization_id=? AND source=? AND agent_run_id=?)",Boolean::class.java,r.organizationId,r.source,r.runId)?:false
        return mapOf("imported" to 1,"duplicate" to 0,"unlinked" to if(linked)0 else 1)
    }
    private fun parse(root:JsonNode,expectedSource:String):AgentRecord {
        require(root.isObject && root.properties().map{it.key}.toSet()==setOf("schema_version","source","organization_id","run_id","agent","user_id","project_id","started_at","completed_at","status","outcome","outcome_source","attempts"))
        require(root["schema_version"].asInt()==1 && root["source"].asText()==expectedSource)
        fun text(node:JsonNode,key:String,max:Int):String=node[key].also{require(it?.isTextual==true && it.asText().length in 1..max && !it.asText().contains('\u0000'))}.asText()
        fun uuid(node:JsonNode,key:String,nullable:Boolean=false):UUID? { val value=node[key];if(nullable&&value.isNull)return null;return UUID.fromString(text(node,key,36)) }
        fun time(node:JsonNode,key:String,nullable:Boolean=false):Instant? { val value=node[key];if(nullable&&value.isNull)return null;return Instant.parse(text(node,key,40)) }
        val agent=root["agent"];require(agent.isObject&&agent.properties().map{it.key}.toSet()==setOf("key","name","description","workflow_type","owner_user_id","project_id","status"))
        val source=text(root,"source",64);require(source.matches(sourcePattern));val runId=text(root,"run_id",128);require(runId.matches(keyPattern));val agentKey=text(agent,"key",128);require(agentKey.matches(keyPattern))
        val started=time(root,"started_at")!!;val completed=time(root,"completed_at",true);val status=text(root,"status",16);val outcome=text(root,"outcome",16)
        require((status=="running"&&completed==null&&outcome=="unknown")||(status=="completed"&&completed!=null&&outcome=="success")||(status=="failed"&&completed!=null&&outcome=="failure")||(status=="cancelled"&&completed!=null&&outcome=="cancelled"));require(completed==null||completed>=started)
        val attempts=root["attempts"];require(attempts.isArray&&attempts.size() in 1..100)
        val parsedAttempts=attempts.map { n->
            require(n.isObject&&n.properties().map{it.key}.toSet()==setOf("attempt_id","attempt_number","started_at","completed_at","status","error_category"))
            val number=n["attempt_number"].asInt();require(n["attempt_number"].isIntegralNumber&&number in 1..100);val aStart=time(n,"started_at")!!;val aEnd=time(n,"completed_at",true);val aStatus=text(n,"status",16);val error=if(n["error_category"].isNull)null else text(n,"error_category",32)
            require(aStart>=started&&(completed==null||aStart<=completed));require(aEnd==null||aEnd>=aStart);require((aStatus=="running"&&aEnd==null&&error==null)||(aStatus=="failed"&&aEnd!=null&&error in setOf("timeout","provider_error","validation_failure","tool_execution_error","unknown_failure"))||(aStatus in setOf("succeeded","cancelled")&&aEnd!=null&&error==null))
            AgentAttempt(text(n,"attempt_id",128),number,aStart,aEnd,aStatus,error)
        }.sortedBy{it.number};require(parsedAttempts.map{it.number}==(1..parsedAttempts.size).toList()&&parsedAttempts.map{it.id}.distinct().size==parsedAttempts.size)
        val description=if(agent["description"].isNull)null else text(agent,"description",1000)
        return AgentRecord(uuid(root,"organization_id")!!,source,runId,agentKey,text(agent,"name",160),description,text(agent,"workflow_type",64),uuid(agent,"owner_user_id")!!,uuid(agent,"project_id",true),text(agent,"status",16),uuid(root,"user_id")!!,uuid(root,"project_id",true),started,completed,status,outcome,text(root,"outcome_source",32),parsedAttempts).also { require(it.agentStatus in setOf("active","inactive")&&it.outcomeSource in setOf("observed","synthetic_fixture")) }
    }
    private fun stableUuid(value:String)=UUID.nameUUIDFromBytes(value.toByteArray())
}

@Service
class AgentExecutionGenerator(private val jdbc:JdbcTemplate,private val mapper:ObjectMapper) {
    fun generate(output:Path,seed:Long,invalidOutput:Path?=null,source:String="demo-synthetic-v1"):Map<String,Any> {
        require(source.matches(Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,63}")))
        val rows=jdbc.queryForList("""WITH ranked AS (SELECT organization_id,source,agent_run_id,COALESCE(workflow_type,'general') workflow_type,user_id,project_id,MIN(occurred_at) OVER(PARTITION BY organization_id,source,agent_run_id) started_at,MAX(occurred_at) OVER(PARTITION BY organization_id,source,agent_run_id) ended_at,ROW_NUMBER() OVER(PARTITION BY organization_id,source,agent_run_id ORDER BY occurred_at,event_id) choice FROM usage.usage_events WHERE agent_run_id IS NOT NULL AND source=?) SELECT organization_id::text,source,agent_run_id,workflow_type,user_id::text,project_id::text,started_at,ended_at FROM ranked WHERE choice=1 ORDER BY organization_id,source,agent_run_id""",source)
        val owners=rows.groupBy{Triple(it["organization_id"],it["source"],"${it["workflow_type"]}:${it["project_id"]}")}.mapValues{(_,v)->v.minOf{it["user_id"].toString()}}
        output.toAbsolutePath().parent?.let(Files::createDirectories)
        Files.newBufferedWriter(output).use { writer->rows.forEachIndexed { index,row->
            val hash=(sha256("$seed/${row["organization_id"]}/${row["source"]}/${row["agent_run_id"]}").take(8).toLong(16)%100).toInt()
            val outcome=when { hash<70->"success";hash<85->"failure";hash<92->"cancelled";else->"unknown" };val status=mapOf("success" to "completed","failure" to "failed","cancelled" to "cancelled","unknown" to "running").getValue(outcome)
            val started=(row["started_at"] as Timestamp).toInstant().minusSeconds(20+(hash%50).toLong());val ended=if(outcome=="unknown")null else (row["ended_at"] as Timestamp).toInstant().plusSeconds(5+(hash%20).toLong())
            val retries=if(hash%4==0)1 else if(hash%17==0)2 else 0;val project=row["project_id"]?.toString();val workflow=row["workflow_type"].toString();val defKey="${workflow.replace(Regex("[^A-Za-z0-9._:-]"),"-")}-${project?.take(8)?:"unassigned"}"
            val attempts=(0..retries).map { attempt->val aStart=started.plusSeconds((attempt*12).toLong());val final=attempt==retries;mapOf("attempt_id" to "${row["agent_run_id"]}-a${attempt+1}","attempt_number" to attempt+1,"started_at" to aStart.toString(),"completed_at" to if(final&&outcome=="unknown")null else aStart.plusSeconds(10).toString(),"status" to if(!final||outcome=="failure")"failed" else if(outcome=="cancelled")"cancelled" else if(outcome=="unknown")"running" else "succeeded","error_category" to if(!final||outcome=="failure")listOf("timeout","provider_error","tool_execution_error")[hash%3] else null) }
            val agent=mapOf("key" to defKey,"name" to workflow.split('-','_').joinToString(" "){word->word.replaceFirstChar{c->c.uppercase()}},"description" to "Deterministic demo agent for $workflow workflows","workflow_type" to workflow,"owner_user_id" to owners.getValue(Triple(row["organization_id"],row["source"],"$workflow:$project")),"project_id" to project,"status" to "active")
            val record=mapOf("schema_version" to 1,"source" to row["source"],"organization_id" to row["organization_id"],"run_id" to row["agent_run_id"],"agent" to agent,"user_id" to row["user_id"],"project_id" to project,"started_at" to started.toString(),"completed_at" to ended?.toString(),"status" to status,"outcome" to outcome,"outcome_source" to "synthetic_fixture","attempts" to attempts)
            writer.append(mapper.writeValueAsString(record)).append('\n')
        }}
        invalidOutput?.let { Files.writeString(it,"{\"schema_version\":1,\"invalid\":true}\n") }
        return mapOf("schema_version" to 1,"seed" to seed,"source" to source,"records" to rows.size,"output" to output.toString(),"uses_existing_run_ids" to true)
    }
}
