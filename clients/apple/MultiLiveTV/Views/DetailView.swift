import SwiftUI

struct DetailView: View {
    let item: VodItem

    @EnvironmentObject private var vod: VodService
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var history: WatchHistoryController
    @State private var detail: DetailResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSourceIndex = 0
    @State private var sourcesExpanded = false
    @State private var allowResolveFallback = true
    @State private var playbackRequest: PlaybackRequest?
    @State private var showDownloadPicker = false
    @State private var continueRecord: WatchHistoryRecord?
    @State private var episodePageIndex = 0
    @FocusState private var focusedEpisode: String?
    @FocusState private var focusedSource: Int?
    @FocusState private var focusedAction: String?
    @FocusState private var focusedContinue: String?

    var body: some View {
        Group {
            if let detail {
                detailContent(detail)
            } else if isLoading {
                AppLoadingView()
            } else if let errorMessage {
                AppErrorView(message: errorMessage) {
                    Task { await loadDetail() }
                }
            }
        }
        .navigationTitle(displayTitle)
        .screenBackground()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .task { await loadDetail() }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerView(request: request)
                .environmentObject(vod)
                .environmentObject(downloads)
                .environmentObject(history)
        }
        .sheet(isPresented: $showDownloadPicker) {
            if let detail, let playSource = currentPlaySource(detail) {
                DownloadEpisodePicker(
                    vod: detail.vod,
                    playSource: playSource,
                    sourceId: episodeSourceId(detail)
                )
                .environmentObject(downloads)
            }
        }
        .overlay {
            if let continueRecord {
                ContinuePlaybackDialog(
                    record: continueRecord,
                    focusedAction: $focusedContinue,
                    onContinue: { playFromHistory(restart: false) },
                    onRestart: { playFromHistory(restart: true) }
                )
                #if os(tvOS)
                .onExitCommand { self.continueRecord = nil }
                #endif
            }
        }
    }

    private var displayTitle: String {
        detail?.vod.vodName ?? item.vodName
    }

    @ViewBuilder
    private func detailContent(_ detail: DetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                cinematicHeader(detail)
                if detail.playSources.isEmpty {
                    Text("暂无播放线路")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, AppTheme.screenPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    sourcePicker(detail.playSources)
                    episodeSection(detail)
                }
            }
            .padding(.bottom, AppTheme.screenPadding)
        }
        .screenBackground()
    }

    @ViewBuilder
    private func cinematicHeader(_ detail: DetailResponse) -> some View {
        let vod = detail.vod
        ZStack(alignment: .bottomLeading) {
            CinemaBackdrop(urlString: vod.vodPic, height: headerHeight)

            HStack(alignment: .bottom, spacing: headerContentSpacing) {
                VodPosterView(
                    sourceId: vod.resolvedSourceId,
                    vodId: vod.vodId,
                    initialURL: vod.vodPic,
                    cornerRadius: AppTheme.posterRadius,
                    showRemarks: nil
                )
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.posterRadius, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if let typeName = vod.typeName, !typeName.isEmpty {
                            MetaChip(text: typeName)
                        }
                        let year = HomeFeed.normalizeYear(vod.vodYear)
                        if !year.isEmpty {
                            MetaChip(text: year)
                        }
                        if let remarks = vod.displayRemarks {
                            MetaChip(text: remarks)
                        }
                    }

                    #if os(tvOS)
                    Text(vod.vodName)
                        .font(titleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                    #endif

                    if let blurb = vod.displayBlurb {
                        Text(blurb)
                            .font(blurbFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(blurbLineLimit)
                            .frame(maxWidth: 720, alignment: .leading)
                    }

                    if let playSource = currentPlaySource(detail),
                       let first = playSource.episodes.first {
                        HStack(spacing: 16) {
                            CinemaActionButton(
                                title: "播放",
                                systemImage: "play.fill",
                                kind: .prominent,
                                isFocused: focusedAction == "play"
                            ) {
                                playPrimary(detail)
                            }
                            .focused($focusedAction, equals: "play")

                            CinemaActionButton(
                                title: "下载",
                                systemImage: "arrow.down.circle",
                                kind: .secondary,
                                isFocused: focusedAction == "download"
                            ) {
                                showDownloadPicker = true
                            }
                            .focused($focusedAction, equals: "download")
                        }
                        .padding(.top, 4)
                        .tvFocusSection()
                    }
                }
                .padding(.bottom, headerTextBottom)
            }
            .padding(.horizontal, AppTheme.screenPadding)
        }
        .frame(height: headerHeight)
        #if os(tvOS)
        .defaultFocus($focusedAction, "play")
        #endif
    }

    @ViewBuilder
    private func episodeSection(_ detail: DetailResponse) -> some View {
        if selectedSourceIndex < detail.playSources.count {
            let source = detail.playSources[selectedSourceIndex]
            VStack(alignment: .leading, spacing: 14) {
                #if os(tvOS)
                Text(source.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, AppTheme.screenPadding)
                #endif

                let pages = EpisodePaging.pages(count: source.episodes.count)
                if pages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                                CategoryTabButton(
                                    label: page.label,
                                    isActive: episodePageIndex == index,
                                    isFocused: focusedEpisode == "page:\(page.label)"
                                ) {
                                    episodePageIndex = index
                                }
                                .tvChipFocused($focusedEpisode, equals: "page:\(page.label)")
                            }
                        }
                        .padding(.horizontal, AppTheme.screenPadding)
                    }
                }

                LazyVGrid(
                    columns: episodeColumns,
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(visibleEpisodes(source)) { ep in
                        EpisodeButton(
                            title: ep.name,
                            statusLabel: downloadRecord(detail: detail, episode: ep)?.statusLabel,
                            isFocused: focusedEpisode == ep.id
                        ) {
                            playEpisode(detail: detail, episode: ep)
                        }
                        .focused($focusedEpisode, equals: ep.id)
                        .accessibilityLabel("播放\(ep.name)")
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
            }
            .tvFocusSection()
            .onChange(of: selectedSourceIndex) { _, _ in
                episodePageIndex = 0
            }
        }
    }

    @ViewBuilder
    private func sourcePicker(_ sources: [PlaySource]) -> some View {
        let limit = 8
        let visible = sourcesExpanded || sources.count <= limit
            ? sources
            : Array(sources.prefix(limit))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(visible.enumerated()), id: \.offset) { index, source in
                    CategoryTabButton(
                        label: source.name,
                        isActive: selectedSourceIndex == index,
                        isFocused: focusedSource == index
                    ) {
                        allowResolveFallback = false
                        selectedSourceIndex = index
                    }
                    .tvChipFocused($focusedSource, equals: index)
                }
                if !sourcesExpanded && sources.count > limit {
                    CategoryTabButton(
                        label: "更多线路",
                        isActive: false,
                        isFocused: focusedSource == -1
                    ) {
                        sourcesExpanded = true
                    }
                }
            }
            .padding(.horizontal, AppTheme.screenPadding)
        }
        .tvFocusSection()
    }

    private var headerHeight: CGFloat {
        #if os(tvOS)
        520
        #else
        236
        #endif
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        28
        #else
        16
        #endif
    }

    private var headerContentSpacing: CGFloat {
        #if os(tvOS)
        28
        #else
        18
        #endif
    }

    private var headerTextBottom: CGFloat {
        #if os(tvOS)
        28
        #else
        16
        #endif
    }

    #if os(tvOS)
    private var titleFont: Font {
        .system(size: 42, weight: .bold)
    }
    #endif

    private var blurbFont: Font {
        #if os(tvOS)
        .body
        #else
        .subheadline
        #endif
    }

    private var blurbLineLimit: Int {
        #if os(tvOS)
        4
        #else
        2
        #endif
    }

    private var posterWidth: CGFloat {
        #if os(tvOS)
        200
        #else
        96
        #endif
    }

    private var posterHeight: CGFloat {
        posterWidth * 1.5
    }

    private var episodeColumns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 200), spacing: 14)]
        #else
        [GridItem(.adaptive(minimum: 112, maximum: 168), spacing: 10)]
        #endif
    }

    private func visibleEpisodes(_ source: PlaySource) -> [Episode] {
        let pages = EpisodePaging.pages(count: source.episodes.count)
        guard !pages.isEmpty else { return [] }
        let page = pages[min(max(episodePageIndex, 0), pages.count - 1)]
        return EpisodePaging.slice(source.episodes, page: page)
    }

    private func playPrimary(_ detail: DetailResponse) {
        guard let first = currentPlaySource(detail)?.episodes.first else { return }
        if let record = WatchHistoryResume.lookup(store: history.store, item: detail.vod),
           !record.completed {
            continueRecord = record
            focusedContinue = "continue"
            return
        }
        playEpisode(detail: detail, episode: first)
    }

    private func playFromHistory(restart: Bool) {
        guard let detail, let record = continueRecord else { return }
        continueRecord = nil
        if let playback = WatchHistoryResume.playbackRequest(detail: detail, record: record, restart: restart) {
            playbackRequest = PlaybackRequest(playback)
        }
    }

    private func playEpisode(detail: DetailResponse, episode: Episode) {
        let record = WatchHistoryResume.lookup(store: history.store, item: detail.vod)
        let sameEpisode = record.map {
            $0.episodeId == episode.url || (!$0.episodeTitle.isEmpty && $0.episodeTitle == episode.name)
        } ?? false
        let resume = sameEpisode ? WatchHistoryResume.resumePositionMs(record!) : 0
        let playback = WatchHistoryResume.playbackRequest(
            detail: detail,
            sourceIndex: selectedSourceIndex,
            episode: episode,
            resumePositionMs: resume
        )
        playbackRequest = PlaybackRequest(playback)
    }

    private func episodeSourceId(_ detail: DetailResponse) -> Int {
        guard selectedSourceIndex < detail.playSources.count else {
            return item.resolvedSourceId
        }
        return detail.playSources[selectedSourceIndex].sourceId ?? item.resolvedSourceId
    }

    private func playbackCandidates(detail: DetailResponse, episode: Episode) -> [PlaybackCandidate] {
        VodPlaybackFailover.candidates(
            playSources: detail.playSources,
            selectedIndex: selectedSourceIndex,
            episode: episode,
            fallbackSourceId: item.resolvedSourceId
        )
    }

    private func preferredSourceIndex(for sources: [PlaySource]) -> Int {
        let index = PlayLineWeighting.preferredPlayableIndex(
            in: sources,
            ticketEnabled: PlayLineWeighting.ticketEnabled
        )
        if index >= 8 {
            sourcesExpanded = true
        }
        return index
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let merged = try await vod.detail(sourceId: item.resolvedSourceId, vodId: item.vodId) { primary in
                applyDetail(primary, resetSelection: true)
                isLoading = false
            }
            guard !Task.isCancelled else { return }
            applyDetail(merged, resetSelection: false)
            isLoading = false
        } catch {
            if detail == nil {
                errorMessage = RequestFailure.userFacingMessage(for: error)
            }
            isLoading = false
        }
    }

    private func applyDetail(_ response: DetailResponse, resetSelection: Bool) {
        let filtered = DetailResponse(
            vod: response.vod,
            playSources: PlayLineWeighting.forDetailDisplay(response.playSources),
            variants: response.variants,
            merged: response.merged
        )
        let previousKey: String? = {
            guard !resetSelection,
                  let detail,
                  selectedSourceIndex < detail.playSources.count else { return nil }
            return detail.playSources[selectedSourceIndex].key
        }()
        detail = filtered
        if let previousKey, let index = filtered.playSources.firstIndex(where: { $0.key == previousKey }) {
            selectedSourceIndex = index
        } else if resetSelection || selectedSourceIndex >= filtered.playSources.count {
            selectedSourceIndex = preferredSourceIndex(for: filtered.playSources)
        }
    }

    private func currentPlaySource(_ detail: DetailResponse) -> PlaySource? {
        guard selectedSourceIndex < detail.playSources.count else { return nil }
        return detail.playSources[selectedSourceIndex]
    }

    private func downloadRecord(detail: DetailResponse, episode: Episode) -> DownloadRecord? {
        guard let playSource = currentPlaySource(detail) else { return nil }
        return downloads.record(
            sourceId: episodeSourceId(detail),
            vodId: detail.vod.vodId,
            playSourceKey: playSource.key,
            episodeURL: episode.url
        )
    }
}

private struct DownloadEpisodePicker: View {
    let vod: VodItem
    let playSource: PlaySource
    let sourceId: Int

    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("下载全部") {
                        let outcome = downloads.enqueueLine(vod: vod, playSource: playSource)
                        if let text = DownloadUserMessage.enqueue(outcome) {
                            message = text
                        } else {
                            dismiss()
                        }
                    }
                }

                Section("选择要下载的集") {
                    ForEach(playSource.episodes) { episode in
                        let record = episodeRecord(episode)
                        Button {
                            let outcome = downloads.enqueueEpisode(
                                vod: vod,
                                playSource: playSource,
                                episode: episode
                            )
                            message = DownloadUserMessage.enqueue(outcome)
                        } label: {
                            HStack {
                                Text(episode.name)
                                Spacer()
                                if let record {
                                    Text(record.statusLabel)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                        }
                        .disabled(!(record?.allowsNewDownload ?? true))
                    }
                }
            }
            .cinemaListChrome()
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("下载", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func episodeRecord(_ episode: Episode) -> DownloadRecord? {
        downloads.record(
            sourceId: sourceId,
            vodId: vod.vodId,
            playSourceKey: playSource.key,
            episodeURL: episode.url
        )
    }
}

private struct ContinuePlaybackDialog: View {
    let record: WatchHistoryRecord
    var focusedAction: FocusState<String?>.Binding
    let onContinue: () -> Void
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(WatchHistoryDisplay.heading())
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(record.title.isEmpty ? "上次播放" : record.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                if let episode = WatchHistoryDisplay.episodeLine(title: record.title, episodeTitle: record.episodeTitle) {
                    Text(episode)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                if WatchHistoryDisplay.showProgressBar(record.durationMs) {
                    HStack(spacing: 12) {
                        ProgressView(value: record.progress)
                            .tint(AppTheme.accent)
                        Text(WatchHistoryProgress.formatClock(WatchHistoryResume.resumePositionMs(record)))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                VStack(spacing: 12) {
                    CinemaActionButton(
                        title: WatchHistoryDisplay.continueAction(
                            clock: WatchHistoryProgress.formatClock(WatchHistoryResume.resumePositionMs(record))
                        ),
                        systemImage: "play.fill",
                        kind: .prominent,
                        isFocused: focusedAction.wrappedValue == "continue",
                        action: onContinue
                    )
                    .focused(focusedAction, equals: "continue")

                    CinemaActionButton(
                        title: WatchHistoryDisplay.restartAction(),
                        systemImage: "backward.end",
                        kind: .secondary,
                        isFocused: focusedAction.wrappedValue == "restart",
                        action: onRestart
                    )
                    .focused(focusedAction, equals: "restart")
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(AppTheme.groupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        #if os(tvOS)
        .defaultFocus(focusedAction, "continue")
        #endif
    }
}

private struct EpisodeButton: View {
    let title: String
    var statusLabel: String?
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let statusLabel {
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(isFocused ? .black.opacity(0.55) : AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, episodeVerticalPadding)
            .foregroundStyle(isFocused ? Color.black : AppTheme.textPrimary)
            .background(
                isFocused ? Color.white : AppTheme.elevated,
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
        }
        #if os(tvOS)
        .tvFocusChrome(isFocused)
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var episodeVerticalPadding: CGFloat {
        #if os(tvOS)
        16
        #else
        12
        #endif
    }
}
