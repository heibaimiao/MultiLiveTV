package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.category.CategoryListService
import com.heibaimiao.multilivetv.category.UnifiedFetchPlan
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.net.VodClientException
import com.heibaimiao.multilivetv.source.SourceHealthStore
import com.heibaimiao.multilivetv.source.SourceMovie
import com.heibaimiao.multilivetv.source.SourcePage
import com.heibaimiao.multilivetv.source.SourceStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

class CategoryListServiceTest {
    private val sourceA = source(1, "A", priority = 300)
    private val sourceB = source(2, "B", priority = 200)
    private val sourceC = source(3, "C", priority = 100)
    private val store = SourceStore(listOf(sourceA, sourceB, sourceC))

    @Test
    fun allSources_should_finish_when_one_source_never_returns() = runBlocking {
        val started = CompletableDeferred<Unit>()
        val hung = CompletableDeferred<SourcePage>()
        try {
            val result = withTimeout(12.seconds) {
                CategoryListService.fetchUnifiedList(
                    store = store,
                    slug = null,
                    page = 1,
                    health = SourceHealthStore(),
                ) { source, _, _, _ ->
                    when (source.id) {
                        1 -> page(source, "影片A")
                        2 -> page(source, "影片B")
                        else -> {
                            started.complete(Unit)
                            withContext(NonCancellable) { hung.await() }
                        }
                    }
                }
            }
            assertTrue(started.isCompleted)
            assertEquals(setOf("影片A", "影片B"), result.list.map { it.item.vodName }.toSet())
            assertTrue(result.list.isNotEmpty())
        } finally {
            hung.cancel()
        }
    }

    @Test
    fun allSources_should_merge_when_all_succeed() = runBlocking {
        val result = withTimeout(12.seconds) {
            CategoryListService.fetchUnifiedList(
                store = store,
                slug = null,
                page = 1,
                health = SourceHealthStore(),
            ) { source, _, _, _ ->
                page(source, "影片${source.name}")
            }
        }
        assertEquals(setOf("影片A", "影片B", "影片C"), result.list.map { it.item.vodName }.toSet())
    }

    @Test
    fun allSources_should_finish_when_one_source_throws() = runBlocking {
        val result = withTimeout(12.seconds) {
            CategoryListService.fetchUnifiedList(
                store = store,
                slug = null,
                page = 1,
                health = SourceHealthStore(),
            ) { source, _, _, _ ->
                when (source.id) {
                    1 -> page(source, "影片A")
                    2 -> error("source B exploded")
                    else -> page(source, "影片C")
                }
            }
        }
        assertEquals(setOf("影片A", "影片C"), result.list.map { it.item.vodName }.toSet())
    }

    @Test
    fun allSources_should_finish_when_one_source_empty() = runBlocking {
        val result = withTimeout(12.seconds) {
            CategoryListService.fetchUnifiedList(
                store = store,
                slug = null,
                page = 1,
                health = SourceHealthStore(),
            ) { source, _, _, _ ->
                when (source.id) {
                    1 -> page(source, "影片A")
                    2 -> SourcePage(page = 1, pageCount = 1, total = 0, list = emptyList())
                    else -> page(source, "影片C")
                }
            }
        }
        assertEquals(setOf("影片A", "影片C"), result.list.map { it.item.vodName }.toSet())
    }

    @Test
    fun allSources_should_finish_when_one_source_times_out() = runBlocking {
        val result = withTimeout(12.seconds) {
            CategoryListService.fetchUnifiedList(
                store = store,
                slug = null,
                page = 1,
                health = SourceHealthStore(),
            ) { source, _, _, _ ->
                when (source.id) {
                    1 -> page(source, "影片A")
                    2 -> page(source, "影片B")
                    else -> {
                        kotlinx.coroutines.delay(UnifiedFetchPlan.PER_CALL_TIMEOUT_MS + 2_000)
                        page(source, "影片C-late")
                    }
                }
            }
        }
        assertEquals(setOf("影片A", "影片B"), result.list.map { it.item.vodName }.toSet())
        assertTrue(result.list.none { it.item.vodName == "影片C-late" })
    }

    @Test
    fun allSources_should_error_when_every_source_fails() = runBlocking<Unit> {
        assertFailsWith<VodClientException> {
            withTimeout(12.seconds) {
                CategoryListService.fetchUnifiedList(
                    store = store,
                    slug = null,
                    page = 1,
                    health = SourceHealthStore(),
                ) { _, _, _, _ -> error("down") }
            }
        }
    }

    private fun source(id: Int, name: String, priority: Int) = Source.legacy(
        id = id,
        name = name,
        url = "https://example.com/$id/",
        metadataPriority = priority,
    )

    private fun page(source: Source, vararg titles: String) = SourcePage(
        page = 1,
        pageCount = 1,
        total = titles.size,
        list = titles.mapIndexed { index, title ->
            SourceMovie(
                sourceId = source.sourceId,
                numericSourceId = source.numericId,
                sourceMovieId = "${source.id}-$index",
                title = title,
                year = "2024",
                poster = "https://example.com/${source.id}.jpg",
                remarks = "",
                area = "",
                genre = "动作",
                blurb = "",
                content = "",
                actors = emptyList(),
                director = "",
                typeId = 1,
                typeName = "电影",
                playFrom = "",
                playURL = "",
                updatedAt = 1_700_000_000,
            )
        },
    )
}
