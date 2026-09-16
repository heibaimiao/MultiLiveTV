import Combine
import SwiftUI

@MainActor
final class WatchHistoryController: ObservableObject {
    let store: WatchHistoryStore
    @Published private(set) var records: [WatchHistoryRecord] = []

    init(store: WatchHistoryStore) {
        self.store = store
        reload()
    }

    func reload() {
        records = store.getAll()
    }

    func save(_ record: WatchHistoryRecord) {
        store.save(record)
        reload()
    }
}

struct HistoryView: View {
    @EnvironmentObject private var vod: VodService
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var history: WatchHistoryController
    @State private var playbackRequest: PlaybackRequest?
    @State private var loadingId: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if history.records.isEmpty {
                    AppEmptyStateView(
                        title: "暂无观看记录",
                        subtitle: "播放过的影片会出现在这里，可以从断点继续",
                        systemImage: "clock"
                    )
                } else {
                    listContent
                }
            }
            .screenBackground()
            .navigationTitle("历史")
            .onAppear { history.reload() }
            .fullScreenCover(item: $playbackRequest) { request in
                PlayerView(request: request)
                    .environmentObject(vod)
                    .environmentObject(downloads)
                    .environmentObject(history)
            }
        }
    }

    private var listContent: some View {
        List {
            ForEach(history.records) { record in
                Button {
                    play(record)
                } label: {
                    HistoryRow(record: record, isLoading: loadingId == record.videoId)
                }
                .buttonStyle(.plain)
            }
        }
        .cinemaListChrome()
        .tvFocusSection()
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding()
            }
        }
    }

    private func play(_ record: WatchHistoryRecord) {
        guard loadingId == nil else { return }
        loadingId = record.videoId
        errorMessage = nil
        Task {
            defer { loadingId = nil }
            do {
                let sourceId = record.sourceId > 0
                    ? record.sourceId
                    : Int(record.videoId.split(separator: ":").first.map(String.init) ?? "") ?? 0
                let vodId = record.vodId.isEmpty
                    ? record.videoId.split(separator: ":").dropFirst().joined(separator: ":")
                    : record.vodId
                guard sourceId > 0, !vodId.isEmpty else {
                    errorMessage = "历史记录不完整，无法继续播放"
                    return
                }
                let detail = try await vod.detail(sourceId: sourceId, vodId: vodId)
                guard let playback = WatchHistoryResume.playbackRequest(detail: detail, record: record) else {
                    errorMessage = "无法恢复上次播放的剧集"
                    return
                }
                playbackRequest = PlaybackRequest(playback)
            } catch {
                errorMessage = RequestFailure.userFacingMessage(for: error)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: WatchHistoryRecord
    var isLoading: Bool

    var body: some View {
        HStack(spacing: 16) {
            VodPosterView(
                sourceId: record.sourceId,
                vodId: record.vodId,
                initialURL: record.cover,
                cornerRadius: AppTheme.posterRadius
            )
            .frame(width: posterWidth, height: posterWidth * 1.5)

            VStack(alignment: .leading, spacing: 6) {
                Text(record.title.isEmpty ? "未命名影片" : record.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if let episode = WatchHistoryDisplay.episodeLine(title: record.title, episodeTitle: record.episodeTitle) {
                    Text(episode)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                }
                Text(WatchHistoryProgress.progressLabel(record))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                if isLoading {
                    Text("正在打开…")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var posterWidth: CGFloat {
        #if os(tvOS)
        92
        #else
        64
        #endif
    }
}
