package com.heibaimiao.multilivetv

import com.heibaimiao.multilivetv.maccms.VodItemRaw
import com.heibaimiao.multilivetv.model.Episode
import com.heibaimiao.multilivetv.model.PlaySource
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.parser.PlayLineWeighting
import com.heibaimiao.multilivetv.parser.PlayParser
import com.heibaimiao.multilivetv.parser.VodPlaybackFailover
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class PlayParserTest {
    private fun source(id: Int, name: String) = Source.legacy(id, name, "https://example.com/$id/")

    private fun playRaw(from: String, url: String) = VodItemRaw(
        vodId = "1",
        vodName = "归来之刃",
        vodPic = "",
        vodRemarks = "",
        vodYear = "2026",
        vodArea = "",
        vodClass = "",
        vodBlurb = "",
        vodContent = "",
        vodPlayFrom = from,
        vodPlayURL = url,
        typeId = 6,
        typeName = "电影",
        vodTime = 0,
    )

    @Test
    fun huyaYunAndM3u8UseDifferentLineNames() {
        val sources = PlayParser.parsePlayURL(
            "hyyun\$\$\$hym3u8",
            "正片\$https://hd.kuktxu.com/play/bDk0qOKa\$\$\$正片\$https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8",
        )
        assertEquals(listOf("虎牙云", "虎牙直链"), sources.map { it.name })
        assertNotEquals(sources[0].name, sources[1].name)
    }

    @Test
    fun mergeKeepsHuyaYunAndDirectAsSeparateChips() {
        val merged = PlayParser.mergePlaySources(
            listOf(
                PlayParser.VodWithSource(
                    source(143, "虎牙"),
                    playRaw(
                        "hyyun\$\$\$hym3u8",
                        "正片\$https://hd.kuktxu.com/play/bDk0qOKa\$\$\$正片\$https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8",
                    ),
                ),
            ),
        )
        assertEquals(setOf("虎牙云", "虎牙直链"), merged.map { it.name }.toSet())
        val preferred = merged[PlayLineWeighting.preferredPlayableIndex(merged)]
        assertEquals("虎牙直链", preferred.name)
        assertEquals("https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8", preferred.episodes.first().url)
    }

    @Test
    fun displayNameDoesNotRepeatHuyaPrefix() {
        assertEquals("虎牙直链", PlayParser.displayPlaySourceName("虎牙", "虎牙直链"))
        assertEquals("虎牙云", PlayParser.displayPlaySourceName("虎牙", "虎牙云"))
        assertEquals("速播 · 虎牙直链", PlayParser.displayPlaySourceName("速播", "虎牙直链"))
        assertEquals("猫眼", PlayParser.displayPlaySourceName("猫眼", "猫眼"))
    }

    @Test
    fun extractDirectMediaURLFromDPlayerSharePage() {
        val html = """
            <div id="dplayer"></div>
            <script>
                const vid = 'https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8';
                const videoConfig = { url: vid, type: 'hls' };
            </script>
        """.trimIndent()
        assertEquals(
            "https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8",
            PlayParser.extractDirectMediaURL(html),
        )
    }

    @Test
    fun extractDirectMediaURLIgnoresJxIframeWithoutM3u8() {
        val html = """
            <iframe src="playm3u8.php?url=https://hd.kuktxu.com/play/bDk0qOKa"></iframe>
        """.trimIndent()
        assertEquals(null, PlayParser.extractDirectMediaURL(html))
    }

    @Test
    fun failoverFromHuyaYunIncludesDirectBackup() {
        val ranked = PlayLineWeighting.forDetailDisplay(
            listOf(
                PlaySource(
                    name = "虎牙云",
                    key = "143:虎牙云",
                    episodes = listOf(Episode("正片", "https://hd.kuktxu.com/play/bDk0qOKa")),
                    sourceId = 143,
                    playFrom = "hyyun",
                ),
                PlaySource(
                    name = "虎牙直链",
                    key = "143:虎牙直链",
                    episodes = listOf(Episode("正片", "https://hd.kuktxu.com/play/bDk0qOKa/index.m3u8")),
                    sourceId = 143,
                    playFrom = "hym3u8",
                ),
            ),
        )
        val yunIndex = ranked.indexOfFirst { it.playFrom == "hyyun" }
        val candidates = VodPlaybackFailover.candidates(
            playSources = ranked,
            selectedIndex = yunIndex,
            episode = ranked[yunIndex].episodes.first(),
            fallbackSourceId = 143,
        )
        assertTrue(candidates.any { it.episode.url.endsWith("/index.m3u8") })
    }
}
