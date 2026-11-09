package com.tokentrack.usage.ingestion

import com.tokentrack.usage.domain.*
import com.tokentrack.usage.persistence.UsageRepository
import com.tokentrack.usage.references.ReferenceResolver
import com.tokentrack.usage.validation.EventValidator
import org.springframework.dao.DataAccessException
import org.springframework.stereotype.Service
import java.io.StringReader
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.file.Files
import java.nio.file.Path

@Service
class IngestionService(private val validator: EventValidator, private val resolver: ReferenceResolver, private val repository: UsageRepository) {
    fun importFile(path: Path, source: String, chunkSize: Int = 250): BatchSummary {
        require(EventValidator.SOURCE.matches(source)) { "source must be a stable lowercase identifier (1–64 characters)" }
        require(chunkSize in 1..500)
        repository.recoverStale()
        val label = path.fileName.toString().replace(Regex("[^A-Za-z0-9._-]"), "_").take(120)
        val id = repository.begin(source, label)
        var observed = 0
        var complete = false
        val pending = mutableListOf<PreparedRow>()
        // Import-local, bounded, exact-reference cache. Event time is part of the
        // key; a present-day membership never stands in for a historical one.
        val cache = object : LinkedHashMap<String, ValidationError?>() {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ValidationError?>?) = size > 4096
        }
        fun flush() {
            if (pending.isEmpty()) return
            val refs = pending.mapNotNull { it.event?.reference() }.distinct()
            val missing = refs.filter { !cache.containsKey(it.key()) }
            val results = resolver.validate(missing)
            if (results.keys != missing.map { it.key() }.toSet()) throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true)
            // Keep this chunk's results outside the LRU as a chunk could evict an
            // earlier cached reference while filling the cache.
            val resolved = refs.associate { it.key() to (if (cache.containsKey(it.key())) cache[it.key()] else results[it.key()]) }
            results.forEach { (key, value) -> cache[key] = value }
            repository.commitRows(id, pending.map { row -> row.event?.reference()?.let { row.copy(error = resolved[it.key()]) } ?: row }, observed)
            pending.clear()
        }
        var failure: ImportFailure? = null
        try {
            if (!Files.isRegularFile(path)) throw ImportFailure("FILE_UNREADABLE")
            val bytes = Files.newInputStream(path).use { it.readNBytes(UsageCsvReader.MAX_BYTES + 1) }
            if (bytes.size > UsageCsvReader.MAX_BYTES) throw ImportFailure("FILE_TOO_LARGE")
            val text = try { Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString() }
                catch (_: java.nio.charset.CharacterCodingException) { throw ImportFailure("INVALID_UTF8") }
            UsageCsvReader(StringReader(text)).use { csv ->
                while (true) {
                    val record = csv.next() ?: break
                    observed++
                    pending += record.second ?: validator.validate(requireNotNull(record.first), source)
                    if (pending.size >= chunkSize) flush()
                }
                complete = true
            }
            flush()
            if (observed == 0) throw ImportFailure("EMPTY_DATASET")
        } catch (error: ImportFailure) {
            failure = error
            if (!error.retryable) {
                try { flush(); repository.fileError(id, if (error.code in setOf("EMPTY_FILE", "INVALID_HEADERS", "UNSUPPORTED_COLUMNS")) 1 else observed + 2, error.code) }
                catch (infra: ImportFailure) { failure = infra }
                catch (_: DataAccessException) { failure = ImportFailure("DATABASE_PERSISTENCE_FAILURE", true) }
            }
        } catch (_: DataAccessException) { failure = ImportFailure("DATABASE_PERSISTENCE_FAILURE", true) }
        catch (_: java.io.IOException) {
            failure = ImportFailure("FILE_UNREADABLE")
            repository.fileError(id, observed + 2, failure.code)
        }
        catch (_: Exception) { failure = ImportFailure("IMPORT_EXECUTION_FAILURE", true) }
        try { return repository.finish(id, observed, complete, failure) }
        catch (_: DataAccessException) { throw ImportFailure("DATABASE_PERSISTENCE_FAILURE", true, id) }
    }
}
