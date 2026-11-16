package com.tokentrack.usage.cli

import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.UsageEngineApplication
import com.tokentrack.usage.domain.ImportFailure
import com.tokentrack.usage.pricing.PricingRepository
import com.tokentrack.usage.pricing.PricingService
import com.tokentrack.usage.delivery.DeliveryWorker
import com.tokentrack.usage.delivery.OutboxRepository
import com.tokentrack.usage.delivery.FinancialReconciler
import com.tokentrack.usage.generation.SyntheticGenerator
import com.tokentrack.usage.generation.EnterpriseDemoGenerator
import com.tokentrack.usage.ingestion.IngestionService
import com.tokentrack.usage.persistence.UsageRepository
import com.tokentrack.usage.references.RailsReferenceResolver
import com.tokentrack.usage.agents.AgentExecutionGenerator
import com.tokentrack.usage.agents.AgentExecutionService
import org.springframework.boot.WebApplicationType
import org.springframework.boot.builder.SpringApplicationBuilder
import org.springframework.dao.DataAccessException
import java.nio.file.Files
import java.nio.file.Path
import java.time.LocalDate
import java.util.UUID
import kotlin.system.exitProcess

private val help = """
TokenTrack usage CLI
  bin/usage import FILE [FILE ...] --source STABLE_SOURCE   (each file is its own batch)
  bin/usage report BATCH_UUID [--offset 0] [--limit 100]
  bin/usage list
  bin/usage load-prices [--file CATALOGUE.json]
  bin/usage price [--source SOURCE]
  bin/usage close-rate --id RATE_UUID --until ISO_TIMESTAMP
  bin/usage pricing-report [--source SOURCE]
  bin/usage deliver [--limit 1000] [--workers 4] [--retry-dead true]
  bin/usage delivery-report
  bin/usage reconcile [--source SOURCE]
  bin/usage snapshot --output FILE.json [--organizations alset,northline-financial,memento-ai]
  bin/usage generate-enterprise-demo --spec FILE.json --snapshot FILE.json --output-dir DIR --seed 42 [--profile demo|smoke] [--start YYYY-MM-DD] [--company slug,...]
  bin/usage generate --snapshot FILE.json --output FILE.csv --seed 42 --from YYYY-MM-DD --to YYYY-MM-DD [--invalid-output FILE.csv]
  bin/usage agent-import FILE [FILE ...] --source STABLE_SOURCE   (each file is its own batch)
  bin/usage agent-report BATCH_UUID
  bin/usage generate-agent-executions --output FILE.jsonl --seed 42 [--source STABLE_SOURCE] [--invalid-output FILE.jsonl]
Exit codes: 0 completed/duplicates/report; 2 completed with rejected rows; 3 failed/partial/infrastructure; 64 invalid arguments.
""".trimIndent()

fun main(args: Array<String>) {
    System.setProperty("spring.devtools.restart.enabled", "false")
    if (args.isEmpty() || args[0] in listOf("help", "--help", "-h")) { println(help); return }
    val command = args[0]
    val positional = mutableListOf<String>()
    val options = mutableMapOf<String, String>()
    var index = 1
    while (index < args.size) {
        val arg = args[index++]
        if (arg.startsWith("--")) {
            if (index == args.size || options.put(arg, args[index++]) != null) { System.err.println("Invalid CLI options\n$help"); exitProcess(64) }
        } else positional += arg
    }
    val allowed = when (command) {
        "import" -> setOf("--source")
        "report" -> setOf("--offset", "--limit")
        "snapshot" -> setOf("--output", "--organizations")
        "generate-enterprise-demo" -> setOf("--spec", "--snapshot", "--output-dir", "--seed", "--profile", "--start", "--company")
        "generate" -> setOf("--snapshot", "--output", "--seed", "--from", "--to", "--invalid-output")
        "agent-import" -> setOf("--source")
        "agent-report" -> emptySet()
        "generate-agent-executions" -> setOf("--output", "--seed", "--source", "--invalid-output")
        "list", "delivery-report" -> emptySet()
        "load-prices" -> setOf("--file")
        "close-rate" -> setOf("--id","--until")
        "price", "pricing-report", "reconcile" -> setOf("--source")
        "deliver" -> setOf("--limit", "--workers", "--retry-dead")
        else -> { System.err.println(help); exitProcess(64) }
    }
    if (!allowed.containsAll(options.keys) || !(when (command) { "import", "agent-import" -> positional.size in 1..500; "report", "agent-report" -> positional.size == 1; else -> positional.isEmpty() })) { System.err.println(help); exitProcess(64) }
    fun option(name: String) = options[name] ?: throw IllegalArgumentException("Required option $name is missing")
    var exit = 0
    try {
        SpringApplicationBuilder(UsageEngineApplication::class.java).web(WebApplicationType.NONE)
            .properties("logging.config=classpath:logback-cli.xml", "spring.main.banner-mode=off", "logging.level.root=WARN", "spring.main.register-shutdown-hook=true")
            .run().use { context ->
                val mapper = context.getBean(ObjectMapper::class.java)
                val repository = context.getBean(UsageRepository::class.java)
                fun print(value: Any) = println(mapper.writerWithDefaultPrettyPrinter().writeValueAsString(value))
                when (command) {
                    "agent-import" -> {
                        // Several files share one JVM start; each remains an independent, idempotent batch.
                        val results=positional.map { file -> context.getBean(AgentExecutionService::class.java).importFile(Path.of(file),option("--source")) }
                        print(results.singleOrNull() ?: results)
                        if(results.any { it["batch"].toString().contains("completed_with_rejections") })exit=2
                    }
                    "agent-report" -> print(context.getBean(AgentExecutionService::class.java).report(UUID.fromString(positional.single())))
                    "generate-agent-executions" -> print(context.getBean(AgentExecutionGenerator::class.java).generate(Path.of(option("--output")),option("--seed").toLong(),options["--invalid-output"]?.let(Path::of),options["--source"]?:"demo-synthetic-v1"))
                    "generate-enterprise-demo" -> print(context.getBean(EnterpriseDemoGenerator::class.java).generate(mapper.readTree(Path.of(option("--spec")).toFile()), mapper.readTree(Path.of(option("--snapshot")).toFile()),
                        EnterpriseDemoGenerator.Options(option("--seed").toLong(), options["--profile"] ?: "demo", options["--start"]?.let(LocalDate::parse), options["--company"]?.split(",")?.toSet(), Path.of(option("--output-dir")))).let { it - "companies" + mapOf("companies" to (it["companies"] as Map<*, *>).mapValues { (_, v) -> (v as Map<*, *>) - "files" }) })
                    "close-rate" -> print(context.getBean(PricingRepository::class.java).closeRate(UUID.fromString(option("--id")),java.time.Instant.parse(option("--until"))))
                    "load-prices" -> print(context.getBean(PricingRepository::class.java).loadCatalogue(options["--file"]?.let(Path::of)))
                    "price" -> {
                        val result=context.getBean(PricingService::class.java).price(options["--source"])
                        print(result)
                        if(listOf("missing_rate","insufficient_billing_metadata","unsupported_profile","failed_calculations").any { (result[it] as Number).toInt()>0 }) exit=2
                    }
                    "pricing-report" -> print(context.getBean(PricingRepository::class.java).counts(options["--source"]))
                    "deliver" -> {
                        val result=context.getBean(DeliveryWorker::class.java).deliver(options["--limit"]?.toInt()?:1000,options["--workers"]?.toInt()?:4,options["--retry-dead"]?.toBooleanStrict()?:false)
                        print(result)
                        if((result["retry"] as Int)>0 || (result["dead"] as Int)>0 || (result["lease_lost"] as Int)>0) exit=2
                    }
                    "delivery-report" -> print(context.getBean(OutboxRepository::class.java).report())
                    "reconcile" -> {
                        val result=context.getBean(FinancialReconciler::class.java).reconcile(options["--source"]);print(result)
                        exit=when(result["status"]) { "reconciled"->0;"discrepancy"->3;else->2 }
                    }
                    "import" -> {
                        // Several files share one JVM start; each remains an independent, idempotent batch.
                        val results = positional.map { file ->
                            val result = context.getBean(IngestionService::class.java).importFile(Path.of(file), option("--source"))
                            exit = maxOf(exit, when (result.status) { "completed" -> 0; "completed_with_rejections" -> 2; else -> 3 })
                            mapOf("batch" to result, "errors" to repository.errors(result.id), "rejections" to repository.rejections(result.id))
                        }
                        print(results.singleOrNull() ?: results)
                    }
                    "report" -> {
                        repository.recoverStale()
                        val id = UUID.fromString(positional.single())
                        print(mapOf("batch" to repository.summary(id), "errors" to repository.errors(id), "rejections" to repository.rejections(id, options["--offset"]?.toInt() ?: 0, options["--limit"]?.toInt() ?: 100)))
                    }
                    "list" -> { repository.recoverStale(); print(repository.recent()) }
                    "snapshot" -> {
                        val snapshot = context.getBean(RailsReferenceResolver::class.java).demoSnapshot(options["--organizations"]?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() })
                        val path = Path.of(option("--output")); path.toAbsolutePath().parent?.let { Files.createDirectories(it) }
                        mapper.writerWithDefaultPrettyPrinter().writeValue(path.toFile(), snapshot)
                        print(mapOf("snapshot" to path.toString(), "users" to snapshot.path("users").size(), "policy_version" to "membership-period-v1"))
                    }
                    "generate" -> {
                        val generator = context.getBean(SyntheticGenerator::class.java)
                        val snapshot = mapper.readTree(Path.of(option("--snapshot")).toFile())
                        val dataset = generator.generate(snapshot, option("--seed").toLong(), LocalDate.parse(option("--from")), LocalDate.parse(option("--to")))
                        val output = Path.of(option("--output")); generator.write(output, dataset.rows)
                        mapper.writerWithDefaultPrettyPrinter().writeValue(Path.of("$output.manifest.json").toFile(), dataset.manifest)
                        options["--invalid-output"]?.let { generator.write(Path.of(it), generator.invalidRows(dataset.rows)) }
                        print(dataset.manifest)
                    }
                }
            }
    } catch (error: IllegalArgumentException) { System.err.println("CLI_ARGUMENT: check options and identifiers with bin/usage help"); exit = 64 }
    catch (error: ImportFailure) { System.err.println("${error.code}: retryable=${error.retryable}; batch=${error.batchId ?: "unavailable"}"); exit = 3 }
    catch (_: org.springframework.dao.EmptyResultDataAccessException) { System.err.println("BATCH_NOT_FOUND: no stored batch matches that ID"); exit = 64 }
    catch (_: DataAccessException) { System.err.println("DATABASE_OPERATION_FAILED: inspect service health and retry; no raw input was logged"); exit = 3 }
    catch (_: Exception) { System.err.println("CLI_EXECUTION_FAILED: inspect service configuration and health; no input or credential details are printed"); exit = 3 }
    exitProcess(exit)
}
