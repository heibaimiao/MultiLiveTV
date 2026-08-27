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

        for item in items {
            let key = buildVodMergeKey(item.item)
            groups[key, default: []].append(item)
        }

        return groups.values.map { group in
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

    static func fetchMergedVodDetail(store: SourceStore, source: Source, vodId: String) async throws -> DetailResponse? {
        let primaryData = try await MacCMSClient.fetchDetail(source: source, ids: vodId)
        guard let primary = primaryData.list.first else { return nil }

        let mergeKey = buildVodMergeKey(primary)
        struct Match {
            let source: Source
            let vodId: String
        }

        var matches: [Match] = []
        var seen = Set<String>()

        func addMatch(_ src: Source, _ id: String) {
            let key = "\(src.id):\(id)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            matches.append(Match(source: src, vodId: id))
        }

        addMatch(source, vodId)

        for searchSource in store.enabled() {
            if matches.count >= maxVariants { break }
            guard let data = try? await MacCMSClient.search(source: searchSource, keyword: primary.vodName, page: 1) else {
                continue
            }
            for item in data.list {
                if buildVodMergeKey(item) != mergeKey { continue }
                addMatch(searchSource, item.vodId)
                if matches.count >= maxVariants { break }
            }
        }

        var vodsWithSource: [PlayParser.VodWithSource] = []
        for match in matches {
            if match.source.id == source.id && match.vodId == vodId {
                vodsWithSource.append(PlayParser.VodWithSource(source: match.source, vod: primary))
                continue
            }
            guard let data = try? await MacCMSClient.fetchDetail(source: match.source, ids: match.vodId),
                  let vod = data.list.first else { continue }
            vodsWithSource.append(PlayParser.VodWithSource(source: match.source, vod: vod))
        }

        let playSources = PlayParser.mergePlaySources(from: vodsWithSource)
        let vodItems = vodsWithSource.map(\.vod)
        let bestVod = pickBestVodMetadata(vodItems)

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
            variants: variants,
            primarySourceId: source.id
        )

        return DetailResponse(vod: vod, playSources: playSources, variants: variants, merged: true)
    }

    static func toVodItems(_ merged: [MergedVodItem]) -> [VodItem] {
        merged.map { entry in
            entry.item.toVodItem(variants: entry.variants, primarySourceId: entry.primarySourceId)
        }
    }

    static func buildVodMergeKey(_ item: VodItemRaw) -> String {
        HomeFeed.normalizeTitle(item.vodName)
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
