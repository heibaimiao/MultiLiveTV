import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var vod: VodService
    @EnvironmentObject private var downloads: DownloadManager
    @State private var playbackRequest: PlaybackRequest?
    @State private var confirmDelete: DownloadRecord?

    var body: some View {
        NavigationStack {
            Group {
                if downloads.records.isEmpty {
                    AppEmptyStateView(
                        title: "暂无下载",
                        subtitle: tvHint,
                        systemImage: "arrow.down.circle"
                    )
                } else {
                    listContent
                }
            }
            .screenBackground()
            .navigationTitle("下载")
            .fullScreenCover(item: $playbackRequest) { request in
                PlayerView(sourceId: request.sourceId, episode: request.episode)
                    .environmentObject(vod)
                    .environmentObject(downloads)
            }
            .confirmationDialog(
                "删除本集下载？",
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let record = confirmDelete {
                        downloads.delete(id: record.id)
                    }
                    confirmDelete = nil
                }
                Button("取消", role: .cancel) { confirmDelete = nil }
            }
        }
    }

    private var tvHint: String {
        #if os(tvOS)
        "下载的影片会出现在这里。下载时请保持本 App 在前台。"
        #else
        "在详情页点下载后选择要下的集即可"
        #endif
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            #if os(tvOS)
            Section {
                Text("下载时请保持本 App 在前台")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            #endif
            ForEach(downloads.groupedRecords()) { group in
                Section(group.vodName) {
                    ForEach(group.items) { record in
                        DownloadRow(record: record) {
                            handleTap(record)
                        } onRetry: {
                            downloads.resume(id: record.id)
                        } onPause: {
                            downloads.pause(id: record.id)
                        } onDelete: {
                            confirmDelete = record
                        }
                    }
                }
            }
        }
        .cinemaListChrome()
        .tvFocusSection()
    }

    private func handleTap(_ record: DownloadRecord) {
        switch record.status {
        case .completed:
            playbackRequest = PlaybackRequest(
                sourceId: record.sourceId,
                episode: Episode(name: record.episodeName, url: record.originalURL)
            )
        case .failed, .evicted, .paused:
            downloads.resume(id: record.id)
        case .queued, .resolving, .downloading:
            break
        }
    }
}

private struct DownloadRow: View {
    let record: DownloadRecord
    let onPlay: () -> Void
    let onRetry: () -> Void
    let onPause: () -> Void
    let onDelete: () -> Void

    var body: some View {
        #if os(tvOS)
        tvRow
        #else
        ipadRow
        #endif
    }

    #if os(tvOS)
    private var tvRow: some View {
        Button(action: onPlay) {
            rowLabel
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .contextMenu {
            if record.status == .downloading || record.status == .resolving {
                Button("暂停", action: onPause)
            }
            if record.status == .failed || record.status == .evicted || record.status == .paused {
                Button("重试", action: onRetry)
            }
            Button("删除", role: .destructive, action: onDelete)
        }
    }
    #endif

    #if os(iOS)
    private var ipadRow: some View {
        HStack(spacing: 16) {
            Button(action: onPlay) {
                rowLabel
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                if record.status == .downloading || record.status == .resolving {
                    Button("暂停", action: onPause)
                }
                if record.status == .failed || record.status == .evicted || record.status == .paused {
                    Button("重试", action: onRetry)
                }
                Button("删除", role: .destructive, action: onDelete)
            }
        }
    }
    #endif

    private var rowLabel: some View {
        HStack(spacing: 14) {
            poster

            VStack(alignment: .leading, spacing: 4) {
                Text(record.episodeName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(record.playSourceName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
                Text(record.statusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
                if record.status == .downloading {
                    ProgressView(value: record.fraction)
                        .tint(AppTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var poster: some View {
        RemoteImageView(url: RemoteMediaURL.parse(record.posterURL)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                AppTheme.tertiaryFill
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(AppTheme.textTertiary)
                    }
            }
        }
        .frame(width: 52, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var statusColor: Color {
        switch record.status {
        case .failed, .evicted:
            return .red.opacity(0.9)
        case .completed:
            return AppTheme.accent
        default:
            return AppTheme.textSecondary
        }
    }
}
