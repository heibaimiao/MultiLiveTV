package com.heibaimiao.multilivetv.history

import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

interface WatchHistoryPersistence {
    fun load(): String?
    fun save(json: String)
}

class MemoryWatchHistoryPersistence : WatchHistoryPersistence {
    @Volatile
    private var json: String? = null

    override fun load(): String? = json

    override fun save(json: String) {
        this.json = json
    }
}

class FileWatchHistoryPersistence(private val file: File) : WatchHistoryPersistence {
    override fun load(): String? = runCatching {
        if (file.exists()) file.readText() else null
    }.getOrNull()

    override fun save(json: String) {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.writeText(json)
            if (!tmp.renameTo(file)) {
                file.writeText(json)
                tmp.delete()
            }
        }
    }
}

class WatchHistoryStore(
    private val persistence: WatchHistoryPersistence,
    private val maxSize: Int = DEFAULT_MAX_SIZE,
) {
    private val lock = Any()

    fun save(record: WatchHistoryRecord) {
        val normalized = WatchHistoryProgress.normalize(record)
        if (normalized.videoId.isBlank()) return
        synchronized(lock) {
            val next = loadUnlocked().filterNot { it.videoId == normalized.videoId }.toMutableList()
            next.add(0, normalized)
            persistUnlocked(trim(next))
        }
    }

    fun getAll(): List<WatchHistoryRecord> = synchronized(lock) { loadUnlocked() }

    fun getByVideoId(videoId: String): WatchHistoryRecord? {
        val key = videoId.trim()
        if (key.isEmpty()) return null
        return getAll().firstOrNull { it.videoId == key }
    }

    fun delete(videoId: String) {
        val key = videoId.trim()
        if (key.isEmpty()) return
        synchronized(lock) {
            persistUnlocked(loadUnlocked().filterNot { it.videoId == key })
        }
    }

    fun clear() {
        synchronized(lock) { persistUnlocked(emptyList()) }
    }

    private fun loadUnlocked(): List<WatchHistoryRecord> {
        val raw = persistence.load()?.trim().orEmpty()
        if (raw.isEmpty()) return emptyList()
        val parsed = runCatching { json.decodeFromString<WatchHistoryDocument>(raw) }.getOrNull()
            ?: runCatching { WatchHistoryDocument(json.decodeFromString<List<WatchHistoryRecord>>(raw)) }.getOrNull()
            ?: return emptyList()
        return trim(parsed.records.map(WatchHistoryProgress::normalize).filter { it.videoId.isNotBlank() })
    }

    private fun persistUnlocked(records: List<WatchHistoryRecord>) {
        val payload = runCatching { json.encodeToString(WatchHistoryDocument(records)) }.getOrNull() ?: return
        persistence.save(payload)
    }

    private fun trim(records: List<WatchHistoryRecord>): List<WatchHistoryRecord> {
        return records
            .sortedByDescending { it.lastPlayTime }
            .distinctBy { it.videoId }
            .take(maxSize.coerceAtLeast(1))
    }

    companion object {
        const val DEFAULT_MAX_SIZE = 100
        private val json = Json { ignoreUnknownKeys = true; isLenient = true; encodeDefaults = true }
    }
}

@Serializable
private data class WatchHistoryDocument(
    val records: List<WatchHistoryRecord> = emptyList(),
)
