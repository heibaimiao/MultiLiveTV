package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.history.FileWatchHistoryPersistence
import com.heibaimiao.multilivetv.history.MemoryWatchHistoryPersistence
import com.heibaimiao.multilivetv.history.WatchHistoryProgress
import com.heibaimiao.multilivetv.history.WatchHistoryRecord
import com.heibaimiao.multilivetv.history.WatchHistoryRecorder
import com.heibaimiao.multilivetv.history.WatchHistoryResume
import com.heibaimiao.multilivetv.history.WatchHistoryStore
import com.heibaimiao.multilivetv.model.DetailResponse
import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.PlaySource
import com.heibaimiao.multilivetv.model.VodItem
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WatchHistoryStoreTest {
    private fun record(
        videoId: String,
        positionMs: Long = 1_000L,
        durationMs: Long = 7_200_000L,
        lastPlayTime: Long = 1_000L,
        episodeId: String = "ep1",
        episodeTitle: String = "第1集",
        episodeIndex: Int = 0,
        title: String = "片名",
    ) = WatchHistoryRecord(
        videoId = videoId,
        vodId = videoId.substringAfterLast(':').ifEmpty { videoId },
        episodeId = episodeId,
        title = title,
        episodeTitle = episodeTitle,
        episodeIndex = episodeIndex,
        cover = "https://cover",
        sourceId = 1,
        sourceName = "线路1",
        positionMs = positionMs,
        durationMs = durationMs,
        lastPlayTime = lastPlayTime,
    )

    @Test
    fun upsertReplacesSameVideoInsteadOfDuplicating() {
        val store = WatchHistoryStore(MemoryWatchHistoryPersistence())
        store.save(record("1:1001", positionMs = 120_000L, lastPlayTime = 10))
        store.save(record("1:1001", positionMs = 860_000L, lastPlayTime = 20))

        val all = store.getAll()
        assertEquals(1, all.size)
        assertEquals(860_000L, all.single().positionMs)
        assertEquals(20L, all.single().lastPlayTime)
    }

    @Test
    fun seriesKeepsOnlyLatestEpisode() {
        val store = WatchHistoryStore(MemoryWatchHistoryPersistence())
        store.save(record("1:dpcq", episodeId = "123", episodeTitle = "第123集", episodeIndex = 122, lastPlayTime = 1))
        store.save(record("1:dpcq", episodeId = "125", episodeTitle = "第125集", episodeIndex = 124, lastPlayTime = 2))

        val saved = store.getByVideoId("1:dpcq")
        assertEquals("125", saved?.episodeId)
        assertEquals("第125集", saved?.episodeTitle)
        assertEquals(1, store.getAll().size)
    }

    @Test
    fun sortsByLastPlayTimeDescending() {
        val store = WatchHistoryStore(MemoryWatchHistoryPersistence())
        store.save(record("a", title = "A", lastPlayTime = 1))
        store.save(record("b", title = "B", lastPlayTime = 2))
        store.save(record("c", title = "C", lastPlayTime = 3))

        assertEquals(listOf("C", "B", "A"), store.getAll().map { it.title })
    }

    @Test
    fun dropsOldestWhenExceedingMaxSize() {
        val store = WatchHistoryStore(MemoryWatchHistoryPersistence(), maxSize = 2)
        store.save(record("a", lastPlayTime = 1))
        store.save(record("b", lastPlayTime = 2))
        store.save(record("c", lastPlayTime = 3))

        assertEquals(listOf("c", "b"), store.getAll().map { it.videoId })
    }

    @Test
    fun deleteAndClearOnlyTouchHistory() {
        val store = WatchHistoryStore(MemoryWatchHistoryPersistence())
        store.save(record("a"))
        store.save(record("b"))
        store.delete("a")
        assertEquals(listOf("b"), store.getAll().map { it.videoId })
        store.clear()
        assertTrue(store.getAll().isEmpty())
    }

    @Test
    fun skipsBlankVideoIdAndSurvivesCorruptJson() {
        val persistence = MemoryWatchHistoryPersistence()
        persistence.save("{not-json")
        val store = WatchHistoryStore(persistence)
        assertTrue(store.getAll().isEmpty())
        store.save(record(" "))
        store.save(record(""))
        assertTrue(store.getAll().isEmpty())
    }

    @Test
    fun filePersistenceSurvivesReload() {
        val dir = File(System.getProperty("java.io.tmpdir"), "watch-history-${System.nanoTime()}")
        dir.mkdirs()
        val file = File(dir, "watch_history.json")
        try {
            WatchHistoryStore(FileWatchHistoryPersistence(file)).save(record("1:1001", positionMs = 5_000L))
            val reloaded = WatchHistoryStore(FileWatchHistoryPersistence(file)).getByVideoId("1:1001")
            assertEquals(5_000L, reloaded?.positionMs)
        } finally {
            file.delete()
            dir.delete()
        }
    }

    @Test
    fun sanitizesPositionAndMarksNearEndCompleted() {
        assertEquals(0L, WatchHistoryProgress.sanitizePosition(-10L, 1_000L))
        assertEquals(800L, WatchHistoryProgress.sanitizePosition(800L, 1_000L))
        assertEquals(1_000L, WatchHistoryProgress.sanitizePosition(2_000L, 1_000L))
        assertEquals(0L, WatchHistoryProgress.sanitizePosition(10L, 0L))
        assertTrue(WatchHistoryProgress.isCompleted(1_790_000L, 1_800_000L))
        assertTrue(!WatchHistoryProgress.isCompleted(1_000L, 10_000L))
        assertTrue(!WatchHistoryProgress.isCompleted(0L, 0L))

        val completed = WatchHistoryProgress.normalize(record("1:1", positionMs = 7_191_000L, durationMs = 7_200_000L))
        assertTrue(completed.completed)
        assertEquals(1.0, completed.progress)
        assertEquals(0L, WatchHistoryResume.resumePositionMs(completed))
        assertEquals(185_000L, WatchHistoryResume.resumePositionMs(record("1:1", positionMs = 185_000L, durationMs = 7_200_000L)))
    }

    @Test
    fun recorderThrottlesUntilForced() {
        val store = WatchHistoryStore(MemoryWatchHistoryPersistence())
        val recorder = WatchHistoryRecorder(store, intervalMs = 8_000L)
        recorder.save(record("1:1", positionMs = 1_000L, lastPlayTime = 10_000L), force = false)
        recorder.save(record("1:1", positionMs = 2_000L, lastPlayTime = 14_000L), force = false)
        assertEquals(1_000L, store.getByVideoId("1:1")?.positionMs)
        recorder.save(record("1:1", positionMs = 3_000L, lastPlayTime = 14_000L), force = true)
        assertEquals(3_000L, store.getByVideoId("1:1")?.positionMs)
        recorder.save(record("1:1", positionMs = 4_000L, lastPlayTime = 22_000L), force = false)
        assertEquals(4_000L, store.getByVideoId("1:1")?.positionMs)
    }

    @Test
    fun resumeFindsEpisodeByIdThenNameThenIndex() {
        val episodes = listOf(Episode("第1集", "u1"), Episode("第3集", "u3"), Episode("第5集", "u5"))
        val detail = DetailResponse(
            vod = VodItem("1001", "斗破苍穹", ""),
            playSources = listOf(PlaySource("线路1", "line1", episodes, sourceId = 7)),
            variants = emptyList(),
            merged = false,
        )
        val matched = WatchHistoryResume.findEpisode(detail, record("7:1001", episodeId = "u3", episodeTitle = "第3集", episodeIndex = 1))
        assertEquals(0, matched?.first)
        assertEquals("u3", matched?.second?.url)

        val byName = WatchHistoryResume.findEpisode(detail, record("7:1001", episodeId = "missing", episodeTitle = "第5集", episodeIndex = 0))
        assertEquals("u5", byName?.second?.url)

        val byIndex = WatchHistoryResume.findEpisode(detail, record("7:1001", episodeId = "", episodeTitle = "", episodeIndex = 0))
        assertEquals("u1", byIndex?.second?.url)

        assertNull(WatchHistoryResume.findEpisode(detail.copy(playSources = emptyList()), record("7:1001")))
    }

    @Test
    fun formatsClockForHistoryAndContinuePrompt() {
        assertEquals("0:00", WatchHistoryProgress.formatClock(0L))
        assertEquals("3:05", WatchHistoryProgress.formatClock(185_000L))
        assertEquals("1:52:30", WatchHistoryProgress.formatClock(6_750_000L))
        assertEquals("0:00", WatchHistoryProgress.formatClock(-1L))
    }
}
