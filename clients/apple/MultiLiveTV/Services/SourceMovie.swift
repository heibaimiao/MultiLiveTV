import Foundation

/// Source-level normalized movie — not the final App `VodItem`.
struct SourceMovie: Hashable {
    let sourceId: String
    let numericSourceId: Int
    let sourceMovieId: String
    let title: String
    let year: String
    let poster: String
    let remarks: String
    let area: String
    let genre: String
    let blurb: String
    let content: String
    let actors: [String]
    let director: String
    let typeId: Int
    let typeName: String
    let playFrom: String
    let playURL: String
    let updatedAt: Int

    func toVodItemRaw() -> VodItemRaw {
        VodItemRaw(
            vodId: sourceMovieId,
            vodName: title,
            vodPic: poster,
            vodRemarks: remarks,
            vodYear: year,
            vodArea: area,
            vodClass: genre,
            vodBlurb: blurb,
            vodContent: content,
            vodActor: actors.joined(separator: ","),
            vodDirector: director,
            vodPlayFrom: playFrom,
            vodPlayURL: playURL,
            typeId: typeId,
            typeName: typeName,
            vodTime: updatedAt
        )
    }

    var completenessScore: Int {
        var score = 0
        if !poster.isEmpty { score += 4 }
        if !actors.isEmpty { score += 3 }
        if !content.isEmpty { score += 2 } else if !blurb.isEmpty { score += 1 }
        if !year.isEmpty { score += 1 }
        if !director.isEmpty { score += 1 }
        return score
    }
}

struct SourcePage: Hashable {
    let page: Int
    let pageCount: Int
    let total: Int
    let list: [SourceMovie]
}

enum MacCMSSourceParser {
    static func parseActors(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ",，/、|")
        return trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func toSourceMovie(source: Source, raw: VodItemRaw) -> SourceMovie {
        SourceMovie(
            sourceId: source.sourceId,
            numericSourceId: source.numericId,
            sourceMovieId: raw.vodId,
            title: raw.vodName,
            year: raw.vodYear,
            poster: raw.vodPic,
            remarks: raw.vodRemarks,
            area: raw.vodArea,
            genre: raw.vodClass,
            blurb: raw.vodBlurb,
            content: raw.vodContent,
            actors: parseActors(raw.vodActor),
            director: raw.vodDirector.trimmingCharacters(in: .whitespacesAndNewlines),
            typeId: raw.typeId,
            typeName: raw.typeName,
            playFrom: raw.vodPlayFrom,
            playURL: raw.vodPlayURL,
            updatedAt: raw.vodTime
        )
    }
}
