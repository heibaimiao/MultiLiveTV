import Foundation

enum VodMergeService {
    private static let maxVariants = 16

    struct MergedVodItem {
        let item: VodItemRaw
        let variants: [VodVariant]
        let primarySourceId: Int
    }

    static func isCompatibleVodMatch(_ primary: VodItemRaw, _ candidate: VodItemRaw) -> Bool {
        let primaryTitle = HomeFeed.normalizeTitle(primary.vodName)
        let candidateTitle = HomeFeed.normalizeTitle(candidate.vodName)
        guard primaryTitle == candidateTitle, !primaryTitle.isEmpty else { return false }
        let primaryYear = HomeFeed.normalizeYear(primary.vodYear)
        let candidateYear = HomeFeed.normalizeYear(candidate.vodYear)
        if primaryYear.isEmpty || candidateYear.isEmpty { return true }
        return primaryYear == candidateYear
    }

    static func mergeVodItems(_ items: [MergeableVodItem], store: SourceStore) -> [MergedVodItem] {
        let sourceOrder = Dictionary(uniqueKeysWithValues: store.enabled().enumerated().map { ($1.id, $0) })
        let (groups, order) = groupMergeableItems(items)

        return order.map { key in
            let group = groups[key] ?? []
            let primary = pickPrimaryItem(group, store: store, sourceOrder: sourceOrder)
            let variants = buildVariants(group, store: store)
            var primarySourceId = primary.sourceId
            if primarySourceId == 0, let first = variants.first {
                primarySourceId = first.sourceId
            }
            let mergedMeta = mergeMetadataFields(group, store: store, primary: primary.item)
            let latestTime = group.map(\.item.vodTime).max() ?? 0
            let stamped =
                latestTime > mergedMeta.vodTime
                ? mergedMeta.withVodTime(latestTime)
                : mergedMeta
            return MergedVodItem(
                item: stamped,
                variants: variants,
                primarySourceId: primarySourceId
            )
        }
    }

    /// Group by title; keep different concrete years apart; fold empty-year rows into the only / newest year.
    static func groupMergeableItems(
        _ items: [MergeableVodItem]
    ) -> (groups: [String: [MergeableVodItem]], order: [String]) {
        var byTitle: [String: [MergeableVodItem]] = [:]
        var titleOrder: [String] = []
        for item in items {
            let title = HomeFeed.normalizeTitle(item.item.vodName)
            guard !title.isEmpty else { continue }
            if byTitle[title] == nil {
                titleOrder.append(title)
            }
            byTitle[title, default: []].append(item)
        }

        var groups: [String: [MergeableVodItem]] = [:]
        var order: [String] = []

        for title in titleOrder {
            guard let group = byTitle[title] else { continue }
            let concreteYears = orderedUniqueYears(in: group)
            if concreteYears.count <= 1 {
                let key = concreteYears.first.map { "\(title)|\($0)" } ?? title
                order.append(key)
                groups[key] = group
                continue
            }

            var byYear: [String: [MergeableVodItem]] = [:]
            var emptyYear: [MergeableVodItem] = []
            var yearOrder: [String] = []
            for entry in group {
                let year = HomeFeed.normalizeYear(entry.item.vodYear)
                if year.isEmpty {
                    emptyYear.append(entry)
                    continue
                }
                if byYear[year] == nil {
                    yearOrder.append(year)
                }
                byYear[year, default: []].append(entry)
            }

            if !emptyYear.isEmpty {
                let targetYear = yearOrder.max { lhs, rhs in
                    let lt = byYear[lhs]?.map(\.item.vodTime).max() ?? 0
                    let rt = byYear[rhs]?.map(\.item.vodTime).max() ?? 0
                    if lt != rt { return lt < rt }
                    return false
                } ?? yearOrder[0]
                byYear[targetYear, default: []].append(contentsOf: emptyYear)
            }

            for year in yearOrder {
                let key = "\(title)|\(year)"
                order.append(key)
                groups[key] = byYear[year]
            }
        }

        return (groups, order)
    }

    private static func orderedUniqueYears(in group: [MergeableVodItem]) -> [String] {
        var seen = Set<String>()
        var years: [String] = []
        for entry in group {
            let year = HomeFeed.normalizeYear(entry.item.vodYear)
            guard !year.isEmpty, !seen.contains(year) else { continue }
            seen.insert(year)
            years.append(year)
        }
        return years
    }

    /// Release year first (future placeholders rank with update-time year), then update time.
    static func sortMergedByUpdatedDesc(_ items: [MergedVodItem]) -> [MergedVodItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let ly = HomeFeed.sortYearValue(lhs.element.item.vodYear, vodTime: lhs.element.item.vodTime)
                let ry = HomeFeed.sortYearValue(rhs.element.item.vodYear, vodTime: rhs.element.item.vodTime)
                if ly != ry {
                    return ly > ry
                }
                if lhs.element.item.vodTime != rhs.element.item.vodTime {
                    return lhs.element.item.vodTime > rhs.element.item.vodTime
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func makeDetailResponse(
        source: Source,
        primary: VodItemRaw,
        extras: [PlayParser.VodWithSource],
        store: SourceStore? = nil
    ) -> DetailResponse {
        var vodsWithSource: [PlayParser.VodWithSource] = [
            PlayParser.VodWithSource(source: source, vod: primary)
        ]
        for extra in extras where !(extra.source.id == source.id && extra.vod.vodId == primary.vodId) {
            vodsWithSource.append(extra)
        }

        let playSources = PlayParser.mergePlaySources(from: vodsWithSource)
        let mergeable = vodsWithSource.map {
            MergeableVodItem(item: $0.vod, sourceId: $0.source.id, sourceName: $0.source.name)
        }
        let bestVod: VodItemRaw
        if let store, !mergeable.isEmpty {
            bestVod = mergeMetadataFields(mergeable, store: store, primary: primary)
        } else {
            bestVod = pickBestVodMetadata(vodsWithSource)
        }
        let variants = vodsWithSource
            .map { entry in
                VodVariant(sourceId: entry.source.id, sourceName: entry.source.name, vodId: entry.vod.vodId)
            }
            .sorted {
                let lhs = store?.metadataPriority(for: $0.sourceId) ?? PlayLineWeighting.sourceWeight($0.sourceId)
                let rhs = store?.metadataPriority(for: $1.sourceId) ?? PlayLineWeighting.sourceWeight($1.sourceId)
                return lhs > rhs
            }
        let vod = VodItem(
            vodId: primary.vodId,
            vodName: primary.vodName,
            vodPic: bestVod.vodPic,
            vodRemarks: bestVod.vodRemarks.isEmpty ? nil : bestVod.vodRemarks,
            vodBlurb: bestVod.vodBlurb.isEmpty ? nil : bestVod.vodBlurb,
            vodContent: bestVod.vodContent.isEmpty ? nil : bestVod.vodContent,
            typeName: bestVod.typeName.isEmpty ? nil : bestVod.typeName,
            vodClass: bestVod.vodClass.isEmpty ? nil : bestVod.vodClass,
            vodYear: bestVod.vodYear.isEmpty ? nil : bestVod.vodYear,
            variants: variants,
            primarySourceId: source.id,
            vodTime: bestVod.vodTime
        )
        return DetailResponse(
            vod: vod,
            playSources: playSources,
            variants: variants,
            merged: !extras.isEmpty
        )
    }

    static func fetchPrimaryVodDetail(source: Source, vodId: String) async throws -> (VodItemRaw, DetailResponse)? {
        let movie = try await SourceCollector.detail(source: source, sourceMovieId: vodId)
        let primary = movie.toVodItemRaw()
        return (primary, makeDetailResponse(source: source, primary: primary, extras: []))
    }

    static func enrichMergedVodDetail(
        store: SourceStore,
        source: Source,
        vodId: String,
        primary: VodItemRaw
    ) async -> DetailResponse {
        let searchable = store.collectable(capability: \.search)

        struct Match {
            let source: Source
            let vodId: String
        }

        var matches: [Match] = [Match(source: source, vodId: vodId)]
        var seen: Set<String> = ["\(source.id):\(vodId)"]

        func addMatch(_ src: Source, _ id: String) {
            let key = "\(src.id):\(id)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            matches.append(Match(source: src, vodId: id))
        }

        let searchBatches = await withTaskGroup(of: (Int, [Match]).self) { group in
            for (index, searchSource) in searchable.enumerated() {
                group.addTask {
                    guard let page = try? await SourceCollector.search(
                        source: searchSource,
                        keyword: primary.vodName,
                        page: 1
                    ) else {
                        return (index, [])
                    }
                    let found = page.list.compactMap { movie -> Match? in
                        let item = movie.toVodItemRaw()
                        guard isCompatibleVodMatch(primary, item) else { return nil }
                        return Match(source: searchSource, vodId: movie.sourceMovieId)
                    }
                    return (index, found)
                }
            }
            var buckets = Array(repeating: [Match](), count: searchable.count)
            for await (index, batch) in group {
                buckets[index] = batch
            }
            return buckets
        }

        for batch in searchBatches {
            for match in batch {
                if matches.count >= maxVariants { break }
                addMatch(match.source, match.vodId)
            }
            if matches.count >= maxVariants { break }
        }

        let detailCapable = matches.filter { $0.source.capabilities.detail }
        let extras: [PlayParser.VodWithSource] = await withTaskGroup(of: (Int, PlayParser.VodWithSource?).self) { group in
            for (index, match) in detailCapable.enumerated() {
                group.addTask {
                    if match.source.id == source.id && match.vodId == vodId {
                        return (index, PlayParser.VodWithSource(source: match.source, vod: primary))
                    }
                    guard let movie = try? await SourceCollector.detail(
                        source: match.source,
                        sourceMovieId: match.vodId
                    ) else {
                        return (index, nil)
                    }
                    let vod = movie.toVodItemRaw()
                    guard isCompatibleVodMatch(primary, vod) else { return (index, nil) }
                    return (index, PlayParser.VodWithSource(source: match.source, vod: vod))
                }
            }
            var ordered = Array<PlayParser.VodWithSource?>(repeating: nil, count: detailCapable.count)
            for await (index, entry) in group {
                ordered[index] = entry
            }
            return ordered.compactMap { $0 }
        }

        let extraOnly = extras.filter { !($0.source.id == source.id && $0.vod.vodId == primary.vodId) }
        return makeDetailResponse(source: source, primary: primary, extras: extraOnly, store: store)
    }

    static func fetchMergedVodDetail(store: SourceStore, source: Source, vodId: String) async throws -> DetailResponse? {
        guard let (primary, _) = try await fetchPrimaryVodDetail(source: source, vodId: vodId) else {
            return nil
        }
        return await enrichMergedVodDetail(store: store, source: source, vodId: vodId, primary: primary)
    }

    static func toVodItems(_ merged: [MergedVodItem]) -> [VodItem] {
        merged.map { entry in
            entry.item.toVodItem(variants: entry.variants, primarySourceId: entry.primarySourceId)
        }
    }

    static func buildVodMergeKey(_ item: VodItemRaw) -> String {
        HomeFeed.mergeKey(title: item.vodName, year: item.vodYear)
    }

    private static func countPlayLines(_ item: VodItemRaw) -> Int {
        let from = item.vodPlayFrom
        if from.isEmpty { return 0 }
        if from.contains("$$$") { return from.components(separatedBy: "$$$").filter { !$0.isEmpty }.count }
        if from.contains(",") { return from.components(separatedBy: ",").filter { !$0.isEmpty }.count }
        return 1
    }

    private static func pickPrimaryItem(
        _ items: [MergeableVodItem],
        store: SourceStore,
        sourceOrder: [Int: Int]
    ) -> MergeableVodItem {
        items.max { a, b in
            let aPic = a.item.vodPic.isEmpty ? 0 : 1
            let bPic = b.item.vodPic.isEmpty ? 0 : 1
            if aPic != bPic { return aPic < bPic }

            let aWeight = store.metadataPriority(for: a.sourceId)
            let bWeight = store.metadataPriority(for: b.sourceId)
            if aWeight != bWeight { return aWeight < bWeight }

            let aLines = countPlayLines(a.item)
            let bLines = countPlayLines(b.item)
            if aLines != bLines { return aLines < bLines }

            let aOrder = sourceOrder[a.sourceId] ?? 999
            let bOrder = sourceOrder[b.sourceId] ?? 999
            return aOrder > bOrder
        } ?? items[0]
    }

    private static func buildVariants(_ items: [MergeableVodItem], store: SourceStore) -> [VodVariant] {
        var variants: [VodVariant] = []
        var seen = Set<String>()
        for item in items where item.sourceId != 0 {
            let key = "\(item.sourceId):\(item.item.vodId)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            variants.append(VodVariant(
                sourceId: item.sourceId,
                sourceName: item.sourceName,
                vodId: item.item.vodId
            ))
        }
        return variants.sorted {
            store.metadataPriority(for: $0.sourceId) > store.metadataPriority(for: $1.sourceId)
        }
    }

    /// Field-level merge: higher metadata_priority wins; ties broken by completeness.
    static func mergeMetadataFields(
        _ items: [MergeableVodItem],
        store: SourceStore,
        primary: VodItemRaw
    ) -> VodItemRaw {
        guard !items.isEmpty else { return primary }

        func ranked(_ pick: (VodItemRaw) -> String) -> String {
            let candidates = items
                .map { (priority: store.metadataPriority(for: $0.sourceId), value: pick($0.item), item: $0.item) }
                .filter { !$0.value.isEmpty }
            guard let best = candidates.max(by: { a, b in
                if a.priority != b.priority { return a.priority < b.priority }
                return a.value.count < b.value.count
            }) else {
                return pick(primary)
            }
            return best.value
        }

        let pic = ranked(\.vodPic)
        let remarks = ranked(\.vodRemarks)
        let year = ranked(\.vodYear)
        let area = ranked(\.vodArea)
        let vodClass = ranked(\.vodClass)
        let blurb = ranked(\.vodBlurb)
        let content = ranked(\.vodContent)
        let actor = ranked(\.vodActor)
        let director = ranked(\.vodDirector)
        let typeName = ranked(\.typeName)

        return VodItemRaw(
            vodId: primary.vodId,
            vodName: primary.vodName.isEmpty ? ranked(\.vodName) : primary.vodName,
            vodPic: pic.isEmpty ? primary.vodPic : pic,
            vodRemarks: remarks.isEmpty ? primary.vodRemarks : remarks,
            vodYear: year.isEmpty ? primary.vodYear : year,
            vodArea: area.isEmpty ? primary.vodArea : area,
            vodClass: vodClass.isEmpty ? primary.vodClass : vodClass,
            vodBlurb: blurb.isEmpty ? primary.vodBlurb : blurb,
            vodContent: content.isEmpty ? primary.vodContent : content,
            vodActor: actor.isEmpty ? primary.vodActor : actor,
            vodDirector: director.isEmpty ? primary.vodDirector : director,
            vodPlayFrom: primary.vodPlayFrom,
            vodPlayURL: primary.vodPlayURL,
            typeId: primary.typeId,
            typeName: typeName.isEmpty ? primary.typeName : typeName,
            vodTime: primary.vodTime
        )
    }

    private static func pickBestVodMetadata(_ entries: [PlayParser.VodWithSource]) -> VodItemRaw {
        entries.max { a, b in
            let aPri = a.source.priority.metadataPriority
            let bPri = b.source.priority.metadataPriority
            if aPri != bPri { return aPri < bPri }

            let aPic = a.vod.vodPic.isEmpty ? 0 : 1
            let bPic = b.vod.vodPic.isEmpty ? 0 : 1
            if aPic != bPic { return aPic < bPic }

            let aContent = a.vod.vodContent.isEmpty ? a.vod.vodBlurb.count : a.vod.vodContent.count
            let bContent = b.vod.vodContent.isEmpty ? b.vod.vodBlurb.count : b.vod.vodContent.count
            return aContent < bContent
        }?.vod ?? entries[0].vod
    }
}
