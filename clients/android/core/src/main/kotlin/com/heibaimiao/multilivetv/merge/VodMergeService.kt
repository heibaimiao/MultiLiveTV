package com.heibaimiao.multilivetv.merge

import com.heibaimiao.multilivetv.home.HomeFeed
import com.heibaimiao.multilivetv.maccms.MergeableVodItem
import com.heibaimiao.multilivetv.maccms.VodItemRaw
import com.heibaimiao.multilivetv.model.DetailResponse
import com.heibaimiao.multilivetv.model.Source
import com.heibaimiao.multilivetv.model.VodItem
import com.heibaimiao.multilivetv.model.VodVariant
import com.heibaimiao.multilivetv.parser.PlayLineWeighting
import com.heibaimiao.multilivetv.parser.PlayParser
import com.heibaimiao.multilivetv.source.SourceCapability
import com.heibaimiao.multilivetv.source.SourceCollector
import com.heibaimiao.multilivetv.source.SourceStore
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

object VodMergeService {
    private const val MAX_VARIANTS = 16
    const val SEARCH_SOURCE_LIMIT = 6

    data class MergedVodItem(
        val item: VodItemRaw,
        val variants: List<VodVariant>,
        val primarySourceId: Int,
    )

    data class EnrichPlan(
        val known: List<VodVariant>,
        val searchSourceIds: List<Int>,
    )

    fun isCompatibleVodMatch(primary: VodItemRaw, candidate: VodItemRaw): Boolean {
        val primaryTitle = HomeFeed.titleKeyForMatch(primary.vodName)
        val candidateTitle = HomeFeed.titleKeyForMatch(candidate.vodName)
        if (primaryTitle.isEmpty() || candidateTitle.isEmpty() || primaryTitle != candidateTitle) return false
        val primaryYear = HomeFeed.normalizeYear(primary.vodYear)
            .ifEmpty { yearSuffix(primary.vodName) }
        val candidateYear = HomeFeed.normalizeYear(candidate.vodYear)
            .ifEmpty { yearSuffix(candidate.vodName) }
        if (primaryYear.isEmpty() || candidateYear.isEmpty()) return true
        return primaryYear == candidateYear
    }

    fun enrichPlan(
        primarySourceId: Int,
        primaryVodId: String,
        knownVariants: List<VodVariant>,
        searchableSourceIds: List<Int>,
        searchLimit: Int = SEARCH_SOURCE_LIMIT,
    ): EnrichPlan {
        val known = LinkedHashMap<String, VodVariant>()
        fun add(variant: VodVariant) {
            if (variant.vodId.isEmpty()) return
            known.putIfAbsent("${variant.sourceId}:${variant.vodId}", variant)
        }
        add(VodVariant(primarySourceId, "", primaryVodId))
        knownVariants.forEach(::add)
        val knownSourceIds = known.values.map { it.sourceId }.toSet()
        val search = if (knownSourceIds.size >= searchLimit) {
            emptyList()
        } else {
            searchableSourceIds.filter { it !in knownSourceIds }.take(searchLimit)
        }
        return EnrichPlan(known.values.toList(), search)
    }

    private fun yearSuffix(name: String): String {
        val match = Regex("""((?:19|20)\d{2})$""").find(HomeFeed.normalizeTitle(name)) ?: return ""
        return HomeFeed.normalizeYear(match.groupValues[1])
    }

    fun mergeVodItems(items: List<MergeableVodItem>, store: SourceStore): List<MergedVodItem> {
        val sourceOrder = store.enabled().mapIndexed { index, source -> source.id to index }.toMap()
        val (groups, order) = groupMergeableItems(items)
        return order.map { key ->
            val group = groups[key].orEmpty()
            val primary = pickPrimaryItem(group, store, sourceOrder)
            val variants = buildVariants(group, store)
            var primarySourceId = primary.sourceId
            if (primarySourceId == 0) primarySourceId = variants.firstOrNull()?.sourceId ?: 0
            val mergedMeta = mergeMetadataFields(group, store, primary.item)
            val latestTime = group.maxOfOrNull { it.item.vodTime } ?: 0
            val stamped = if (latestTime > mergedMeta.vodTime) mergedMeta.withVodTime(latestTime) else mergedMeta
            MergedVodItem(stamped, variants, primarySourceId)
        }
    }

    fun groupMergeableItems(
        items: List<MergeableVodItem>,
    ): Pair<Map<String, List<MergeableVodItem>>, List<String>> {
        val byTitle = linkedMapOf<String, MutableList<MergeableVodItem>>()
        for (item in items) {
            val title = HomeFeed.normalizeTitle(item.item.vodName)
            if (title.isEmpty()) continue
            byTitle.getOrPut(title) { mutableListOf() } += item
        }
        val groups = linkedMapOf<String, List<MergeableVodItem>>()
        val order = mutableListOf<String>()
        for ((title, group) in byTitle) {
            val concreteYears = orderedUniqueYears(group)
            if (concreteYears.size <= 1) {
                val key = concreteYears.firstOrNull()?.let { "$title|$it" } ?: title
                order += key
                groups[key] = group
                continue
            }
            val byYear = linkedMapOf<String, MutableList<MergeableVodItem>>()
            val emptyYear = mutableListOf<MergeableVodItem>()
            for (entry in group) {
                val year = HomeFeed.normalizeYear(entry.item.vodYear)
                if (year.isEmpty()) {
                    emptyYear += entry
                    continue
                }
                byYear.getOrPut(year) { mutableListOf() } += entry
            }
            if (emptyYear.isNotEmpty()) {
                val targetYear = byYear.maxByOrNull { (_, rows) -> rows.maxOf { it.item.vodTime } }?.key
                    ?: byYear.keys.first()
                byYear.getOrPut(targetYear) { mutableListOf() } += emptyYear
            }
            for ((year, rows) in byYear) {
                val key = "$title|$year"
                order += key
                groups[key] = rows
            }
        }
        return groups to order
    }

    fun sortMergedByUpdatedDesc(items: List<MergedVodItem>): List<MergedVodItem> =
        items.mapIndexed { index, item -> index to item }
            .sortedWith(
                compareByDescending<Pair<Int, MergedVodItem>> {
                    HomeFeed.sortYearValue(it.second.item.vodYear, it.second.item.vodTime)
                }
                    .thenByDescending { it.second.item.vodTime }
                    .thenBy { it.first },
            )
            .map { it.second }

    fun makeDetailResponse(
        source: Source,
        primary: VodItemRaw,
        extras: List<PlayParser.VodWithSource>,
        store: SourceStore? = null,
    ): DetailResponse {
        val vodsWithSource = mutableListOf(PlayParser.VodWithSource(source, primary))
        for (extra in extras) {
            if (extra.source.id == source.id && extra.vod.vodId == primary.vodId) continue
            vodsWithSource += extra
        }
        val playSources = PlayParser.mergePlaySources(vodsWithSource)
        val mergeable = vodsWithSource.map {
            MergeableVodItem(it.vod, it.source.id, it.source.name)
        }
        val bestVod = if (store != null && mergeable.isNotEmpty()) {
            mergeMetadataFields(mergeable, store, primary)
        } else {
            pickBestVodMetadata(vodsWithSource)
        }
        val variants = vodsWithSource
            .map { VodVariant(it.source.id, it.source.name, it.vod.vodId) }
            .sortedByDescending {
                store?.metadataPriority(it.sourceId) ?: PlayLineWeighting.sourceWeight(it.sourceId)
            }
        val vod = VodItem(
            vodId = primary.vodId,
            vodName = primary.vodName,
            vodPic = bestVod.vodPic,
            vodRemarks = bestVod.vodRemarks.ifEmpty { null },
            vodBlurb = bestVod.vodBlurb.ifEmpty { null },
            vodContent = bestVod.vodContent.ifEmpty { null },
            typeName = bestVod.typeName.ifEmpty { null },
            vodClass = bestVod.vodClass.ifEmpty { null },
            vodYear = bestVod.vodYear.ifEmpty { null },
            variants = variants,
            primarySourceId = source.id,
            vodTime = bestVod.vodTime,
        )
        return DetailResponse(vod, playSources, variants, merged = extras.isNotEmpty())
    }

    suspend fun fetchPrimaryVodDetail(source: Source, vodId: String): Pair<VodItemRaw, DetailResponse>? {
        val movie = SourceCollector.detail(source, vodId)
        val primary = movie.toVodItemRaw()
        return primary to makeDetailResponse(source, primary, extras = emptyList())
    }

    suspend fun enrichMergedVodDetail(
        store: SourceStore,
        source: Source,
        vodId: String,
        primary: VodItemRaw,
        knownVariants: List<VodVariant> = emptyList(),
    ): DetailResponse = coroutineScope {
        val searchable = store.collectable(SourceCapability.SEARCH)
            .sortedByDescending { store.metadataPriority(it.id) + store.playPriority(it.id) }
        val plan = enrichPlan(source.id, vodId, knownVariants, searchable.map { it.id })
        data class Match(val source: Source, val vodId: String)
        val matches = mutableListOf<Match>()
        val seen = mutableSetOf<String>()
        fun addMatch(match: Match) {
            if (matches.size >= MAX_VARIANTS) return
            val key = "${match.source.id}:${match.vodId}"
            if (!seen.add(key)) return
            matches += match
        }
        for (variant in plan.known) {
            val src = store.byID(variant.sourceId) ?: continue
            if (!src.capabilities.detail) continue
            addMatch(Match(src, variant.vodId))
        }
        val keyword = HomeFeed.searchKeyword(primary.vodName)
        val searchSources = plan.searchSourceIds.mapNotNull { store.byID(it) }
        if (searchSources.isNotEmpty()) {
            val searchBatches = searchSources.mapIndexed { index, searchSource ->
                async {
                    val page = runCatching { SourceCollector.search(searchSource, keyword, 1) }.getOrNull()
                    val found = page?.list.orEmpty().mapNotNull { movie ->
                        val item = movie.toVodItemRaw()
                        if (!isCompatibleVodMatch(primary, item)) null
                        else Match(searchSource, movie.sourceMovieId)
                    }
                    index to found
                }
            }.awaitAll().sortedBy { it.first }.map { it.second }
            for (batch in searchBatches) {
                for (match in batch) {
                    addMatch(match)
                    if (matches.size >= MAX_VARIANTS) break
                }
                if (matches.size >= MAX_VARIANTS) break
            }
        }
        val extras = matches.mapIndexed { index, match ->
            async {
                if (match.source.id == source.id && match.vodId == vodId) {
                    index to PlayParser.VodWithSource(match.source, primary)
                } else {
                    val movie = runCatching { SourceCollector.detail(match.source, match.vodId) }.getOrNull()
                    val vod = movie?.toVodItemRaw()
                    if (vod != null && isCompatibleVodMatch(primary, vod)) {
                        index to PlayParser.VodWithSource(match.source, vod)
                    } else {
                        index to null
                    }
                }
            }
        }.awaitAll().sortedBy { it.first }.mapNotNull { it.second }
        val extraOnly = extras.filter { !(it.source.id == source.id && it.vod.vodId == primary.vodId) }
        makeDetailResponse(source, primary, extraOnly, store)
    }

    fun toVodItems(merged: List<MergedVodItem>): List<VodItem> =
        merged.map { it.item.toVodItem(it.variants, it.primarySourceId) }

    fun mergeMetadataFields(
        items: List<MergeableVodItem>,
        store: SourceStore,
        primary: VodItemRaw,
    ): VodItemRaw {
        if (items.isEmpty()) return primary
        fun ranked(pick: (VodItemRaw) -> String): String {
            val candidates = items.map {
                Triple(store.metadataPriority(it.sourceId), pick(it.item), it.item)
            }.filter { it.second.isNotEmpty() }
            val best = candidates.maxWithOrNull(
                compareBy<Triple<Int, String, VodItemRaw>> { it.first }.thenBy { it.second.length },
            )
            return best?.second ?: pick(primary)
        }
        val pic = ranked { it.vodPic }
        val remarks = ranked { it.vodRemarks }
        val year = ranked { it.vodYear }
        val area = ranked { it.vodArea }
        val vodClass = ranked { it.vodClass }
        val blurb = ranked { it.vodBlurb }
        val content = ranked { it.vodContent }
        val actor = ranked { it.vodActor }
        val director = ranked { it.vodDirector }
        val typeName = ranked { it.typeName }
        return VodItemRaw(
            vodId = primary.vodId,
            vodName = primary.vodName.ifEmpty { ranked { it.vodName } },
            vodPic = pic.ifEmpty { primary.vodPic },
            vodRemarks = remarks.ifEmpty { primary.vodRemarks },
            vodYear = year.ifEmpty { primary.vodYear },
            vodArea = area.ifEmpty { primary.vodArea },
            vodClass = vodClass.ifEmpty { primary.vodClass },
            vodBlurb = blurb.ifEmpty { primary.vodBlurb },
            vodContent = content.ifEmpty { primary.vodContent },
            vodActor = actor.ifEmpty { primary.vodActor },
            vodDirector = director.ifEmpty { primary.vodDirector },
            vodPlayFrom = primary.vodPlayFrom,
            vodPlayURL = primary.vodPlayURL,
            typeId = primary.typeId,
            typeName = typeName.ifEmpty { primary.typeName },
            vodTime = primary.vodTime,
        )
    }

    private fun orderedUniqueYears(group: List<MergeableVodItem>): List<String> {
        val years = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        for (entry in group) {
            val year = HomeFeed.normalizeYear(entry.item.vodYear)
            if (year.isEmpty() || !seen.add(year)) continue
            years += year
        }
        return years
    }

    private fun countPlayLines(item: VodItemRaw): Int {
        val from = item.vodPlayFrom
        if (from.isEmpty()) return 0
        if (from.contains("$$$")) return from.split("$$$").count { it.isNotEmpty() }
        if (from.contains(",")) return from.split(",").count { it.isNotEmpty() }
        return 1
    }

    private fun pickPrimaryItem(
        items: List<MergeableVodItem>,
        store: SourceStore,
        sourceOrder: Map<Int, Int>,
    ): MergeableVodItem = items.maxWith(
        compareBy<MergeableVodItem> { if (it.item.vodPic.isEmpty()) 0 else 1 }
            .thenBy { store.metadataPriority(it.sourceId) }
            .thenBy { countPlayLines(it.item) }
            .thenByDescending { sourceOrder[it.sourceId] ?: 999 }
            .reversed()
            .thenBy { sourceOrder[it.sourceId] ?: 999 },
    )

    private fun buildVariants(items: List<MergeableVodItem>, store: SourceStore): List<VodVariant> {
        val variants = mutableListOf<VodVariant>()
        val seen = mutableSetOf<String>()
        for (item in items) {
            if (item.sourceId == 0) continue
            val key = "${item.sourceId}:${item.item.vodId}"
            if (!seen.add(key)) continue
            variants += VodVariant(item.sourceId, item.sourceName, item.item.vodId)
        }
        return variants.sortedByDescending { store.metadataPriority(it.sourceId) }
    }

    private fun pickBestVodMetadata(entries: List<PlayParser.VodWithSource>): VodItemRaw =
        entries.maxWith(
            compareBy<PlayParser.VodWithSource> { it.source.priority.metadataPriority }
                .thenBy { if (it.vod.vodPic.isEmpty()) 0 else 1 }
                .thenBy { if (it.vod.vodContent.isEmpty()) it.vod.vodBlurb.length else it.vod.vodContent.length },
        ).vod
}
