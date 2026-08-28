import Foundation

enum VodMergeService {
    private static let maxVariants = 10

    struct MergedVodItem {
        let item: VodItemRaw
        let variants: [VodVariant]
        let primarySourceId: Int
    }

    static func mergeVodItems(_ items: [MergeableVodItem], store: SourceStore) -> [MergedVodItem] {
        let sourceOrder = Dictionary(uniqueKeysWithValues: store.enabled().enumerated().map { ($1.id, $0) })
        var groups: [String: [MergeableVodItem]] = [:]
        var order: [String] = []

        for item in items {
            let key = buildVodMergeKey(item.item)
            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(item)
        }

        return order.map { key in
            let group = groups[key] ?? []
            let primary = pickPrimaryItem(group, sourceOrder: sourceOrder)
            let variants = buildVariants(group)
            var primarySourceId = primary.sourceId
            if primarySourceId == 0, let first = variants.first {
                primarySourceId = first.sourceId
            }
            return MergedVodItem(
                item: primary.item,
                variants: variants,
                primarySourceId: primarySourceId
            )
        }
    }

    static func makeDetailResponse(
        source: Source,
        primary: VodItemRaw,
        extras: [PlayParser.VodWithSource]
    ) -> DetailResponse {
        var vodsWithSource: [PlayParser.VodWithSource] = [
            PlayParser.VodWithSource(source: source, vod: primary)
        ]
        for extra in extras where !(extra.source.id == source.id && extra.vod.vodId == primary.vodId) {
            vodsWithSource.append(extra)
        }

        let playSources = PlayParser.mergePlaySources(from: vodsWithSource)
        let bestVod = pickBestVodMetadata(vodsWithSource.map(\.vod))
        let variants = vodsWithSource.map { entry in
            VodVariant(sourceId: entry.source.id, sourceName: entry.source.name, vodId: entry.vod.vodId)
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
        let primaryData = try await MacCMSClient.fetchDetail(source: source, ids: vodId)
        guard let primary = primaryData.list.first else { return nil }
        return (primary, makeDetailResponse(source: source, primary: primary, extras: []))
    }

    static func enrichMergedVodDetail(
        store: SourceStore,
        source: Source,
        vodId: String,
        primary: VodItemRaw
    ) async -> DetailResponse {
        let mergeKey = buildVodMergeKey(primary)
        let enabled = store.enabled()

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
            for (index, searchSource) in enabled.enumerated() {
                group.addTask {
                    guard let data = try? await MacCMSClient.search(
                        source: searchSource,
                        keyword: primary.vodName,
                        page: 1
                    ) else {
                        return (index, [])
                    }
                    let found = data.list.compactMap { item -> Match? in
                        guard buildVodMergeKey(item) == mergeKey else { return nil }
                        return Match(source: searchSource, vodId: item.vodId)
                    }
                    return (index, found)
                }
            }
            var buckets = Array(repeating: [Match](), count: enabled.count)
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

        let extras: [PlayParser.VodWithSource] = await withTaskGroup(of: (Int, PlayParser.VodWithSource?).self) { group in
            for (index, match) in matches.enumerated() {
                group.addTask {
                    if match.source.id == source.id && match.vodId == vodId {
                        return (index, PlayParser.VodWithSource(source: match.source, vod: primary))
                    }
                    guard let data = try? await MacCMSClient.fetchDetail(source: match.source, ids: match.vodId),
                          let vod = data.list.first else {
                        return (index, nil)
                    }
                    return (index, PlayParser.VodWithSource(source: match.source, vod: vod))
                }
            }
            var ordered = Array<PlayParser.VodWithSource?>(repeating: nil, count: matches.count)
            for await (index, entry) in group {
                ordered[index] = entry
            }
            return ordered.compactMap { $0 }
        }

        let extraOnly = extras.filter { !($0.source.id == source.id && $0.vod.vodId == primary.vodId) }
        return makeDetailResponse(source: source, primary: primary, extras: extraOnly)
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

    private static func pickPrimaryItem(_ items: [MergeableVodItem], sourceOrder: [Int: Int]) -> MergeableVodItem {
        items.max { a, b in
            let aPic = a.item.vodPic.isEmpty ? 0 : 1
            let bPic = b.item.vodPic.isEmpty ? 0 : 1
            if aPic != bPic { return aPic < bPic }

            if a.item.vodTime != b.item.vodTime {
                return a.item.vodTime < b.item.vodTime
            }

            let aLines = countPlayLines(a.item)
            let bLines = countPlayLines(b.item)
            if aLines != bLines { return aLines < bLines }

            let aOrder = sourceOrder[a.sourceId] ?? 999
            let bOrder = sourceOrder[b.sourceId] ?? 999
            return aOrder > bOrder
        } ?? items[0]
    }

    private static func buildVariants(_ items: [MergeableVodItem]) -> [VodVariant] {
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
        return variants
    }

    private static func pickBestVodMetadata(_ items: [VodItemRaw]) -> VodItemRaw {
        items.max { a, b in
            let aPic = a.vodPic.isEmpty ? 0 : 1
            let bPic = b.vodPic.isEmpty ? 0 : 1
            if aPic != bPic { return aPic < bPic }

            let aContent = a.vodContent.isEmpty ? a.vodBlurb.count : a.vodContent.count
            let bContent = b.vodContent.isEmpty ? b.vodBlurb.count : b.vodContent.count
            return aContent < bContent
        } ?? items[0]
    }
}
