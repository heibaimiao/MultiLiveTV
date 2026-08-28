import Foundation

struct LiveSource: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let url: String
    let flag: Int
}

struct LiveStream: Hashable {
    let url: String
    var headers: [String: String] = [:]
}

struct LiveChannel: Identifiable, Hashable {
    var id: String { "\(group)|\(name)" }
    let name: String
    let group: String
    var logo: String?
    var streams: [LiveStream]
    var urls: [String] { streams.map(\.url) }
}

struct LiveGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var channels: [LiveChannel]
}

enum LiveError: LocalizedError {
    case missingLives
    case notConfigured
    case emptyPlaylist
    case httpFailed

    var errorDescription: String? {
        switch self {
        case .missingLives: return "未找到 lives.json"
        case .notConfigured: return "请在 lives.json 填写 M3U 地址"
        case .emptyPlaylist: return "直播列表为空"
        case .httpFailed: return "直播源无法访问"
        }
    }
}

struct LiveResumePick: Equatable {
    let group: LiveGroup
    let channel: LiveChannel
}

enum LiveResume {
    static func resolve(groups: [LiveGroup], lastChannelId: String?) -> LiveResumePick? {
        if let lastChannelId {
            for group in groups {
                if let channel = group.channels.first(where: { $0.id == lastChannelId }) {
                    return LiveResumePick(group: group, channel: channel)
                }
            }
        }
        guard let group = groups.first, let channel = group.channels.first else { return nil }
        return LiveResumePick(group: group, channel: channel)
    }
}

enum LiveChannelNumber {
    static func displayIndex(in group: LiveGroup, channelId: String) -> Int? {
        guard let index = group.channels.firstIndex(where: { $0.id == channelId }) else { return nil }
        return index + 1
    }
}

enum LiveWatchMemory {
    static let key = "live.lastChannelId"

    static func load(from defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key)
    }

    static func save(_ id: String, to defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: key)
    }
}

enum LiveChannelZap {
    static func neighbor(groups: [LiveGroup], currentId: String?, delta: Int) -> LiveResumePick? {
        guard !groups.isEmpty else { return nil }
        if let currentId {
            for group in groups {
                if let index = group.channels.firstIndex(where: { $0.id == currentId }) {
                    return wrappedPick(in: group, from: index, delta: delta)
                }
            }
        }
        return LiveResume.resolve(groups: groups, lastChannelId: nil)
    }

    private static func wrappedPick(in group: LiveGroup, from index: Int, delta: Int) -> LiveResumePick? {
        let count = group.channels.count
        guard count > 0 else { return nil }
        let next = ((index + delta) % count + count) % count
        return LiveResumePick(group: group, channel: group.channels[next])
    }
}

enum LiveRemoteDirection: Equatable {
    case up, down, left, right
}

enum LiveRemoteEvent: Equatable {
    case move(LiveRemoteDirection)
    case select
    case menu
    case playPause
}

enum LiveRemoteEffect: Equatable {
    case zap(Int)
    case showGuide
    case hideGuide
    case togglePause
    case cycleStream
    case none
}

enum LiveRemoteRouter {
    static func effect(showGuide: Bool, event: LiveRemoteEvent) -> LiveRemoteEffect {
        if showGuide {
            switch event {
            case .menu, .move(.right):
                return .hideGuide
            case .playPause:
                return .togglePause
            case .move, .select:
                return .none
            }
        }
        switch event {
        case .move(.up):
            return .zap(-1)
        case .move(.down):
            return .zap(1)
        case .move(.left), .select, .menu:
            return .showGuide
        case .move(.right):
            return .cycleStream
        case .playPause:
            return .togglePause
        }
    }
}

enum LiveGuideFocus {
    static let dismissId = "dismiss"

    static func groupName(fromFocusId id: String?) -> String? {
        guard let id, id.hasPrefix("g:") else { return nil }
        return String(id.dropFirst(2))
    }

    static func shouldDismissGuide(focusedId: String?) -> Bool {
        focusedId == dismissId
    }
}
