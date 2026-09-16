import AVKit
import SwiftUI

struct PlaybackRequest: Identifiable {
    let candidates: [PlaybackCandidate]
    var resumePositionMs: Int64 = 0
    var historyItem: VodItem?
    var historySourceName: String = ""
    var historyEpisodeIndex: Int = 0

    var id: String {
        candidates.map { "\($0.sourceId)-\($0.episode.id)" }.joined(separator: "|")
            + "-\(resumePositionMs)"
    }

    init(
        candidates: [PlaybackCandidate],
        resumePositionMs: Int64 = 0,
        historyItem: VodItem? = nil,
        historySourceName: String = "",
        historyEpisodeIndex: Int = 0
    ) {
        self.candidates = candidates.isEmpty
            ? [PlaybackCandidate(sourceId: 0, episode: Episode(name: "", url: ""))]
            : candidates
        self.resumePositionMs = resumePositionMs
        self.historyItem = historyItem
        self.historySourceName = historySourceName
        self.historyEpisodeIndex = historyEpisodeIndex
    }

    init(_ playback: WatchHistoryPlayback) {
        self.init(
            candidates: playback.candidates,
            resumePositionMs: playback.resumePositionMs,
            historyItem: playback.item,
            historySourceName: playback.sourceName,
            historyEpisodeIndex: playback.episodeIndex
        )
    }

    init(sourceId: Int, episode: Episode) {
        self.init(candidates: [PlaybackCandidate(sourceId: sourceId, episode: episode)])
    }

    var sourceId: Int { candidates[0].sourceId }
    var episode: Episode { candidates[0].episode }
}

struct PlayerView: View {
    let candidates: [PlaybackCandidate]
    var resumePositionMs: Int64 = 0
    var historyItem: VodItem?
    var historySourceName: String = ""
    var historyEpisodeIndex: Int = 0

    @EnvironmentObject private var vod: VodService
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var history: WatchHistoryController
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var failObserver: NSObjectProtocol?
    @State private var timeObserver: Any?
    @State private var startTimeoutTask: Task<Void, Never>?
    @State private var playbackGeneration = 0
    @State private var failedURL: String?
    @State private var playingLocal = false
    @State private var didBecomeReady = false
    @State private var didSeekResume = false
    @State private var candidateIndex = 0
    @State private var statusMessage = "解析播放地址…"
    @State private var recorder: WatchHistoryRecorder?

    init(request: PlaybackRequest) {
        self.candidates = request.candidates
        self.resumePositionMs = request.resumePositionMs
        self.historyItem = request.historyItem
        self.historySourceName = request.historySourceName
        self.historyEpisodeIndex = request.historyEpisodeIndex
    }

    init(candidates: [PlaybackCandidate]) {
        self.candidates = candidates
    }

    init(sourceId: Int, episode: Episode) {
        self.candidates = [PlaybackCandidate(sourceId: sourceId, episode: episode)]
    }

    private var activeCandidate: PlaybackCandidate {
        let index = min(max(candidateIndex, 0), max(candidates.count - 1, 0))
        return candidates.isEmpty
            ? PlaybackCandidate(sourceId: 0, episode: Episode(name: "", url: ""))
            : candidates[index]
    }

    var body: some View {
        ZStack {
            AppTheme.screenBackground.ignoresSafeArea()

            if let player {
                #if os(tvOS)
                SystemVideoPlayer(player: player) {
                    dismiss()
                }
                .ignoresSafeArea()
                #else
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                #endif
            } else if let errorMessage {
                AppErrorView(message: errorMessage) {
                    Task {
                        candidateIndex = 0
                        await startPlayback()
                    }
                }
            } else {
                AppLoadingView(message: playingLocal ? "正在打开本地影片…" : statusMessage)
            }
        }
        .task(id: candidates.map(\.episode.id).joined(separator: "|")) {
            candidateIndex = 0
            didSeekResume = false
            if recorder == nil {
                recorder = WatchHistoryRecorder(store: history.store)
            }
            await startPlayback()
        }
        .onDisappear {
            playbackGeneration += 1
            writeWatchHistory(force: true)
            teardownPlayer()
        }
        #if os(tvOS)
        .onExitCommand {
            if player == nil {
                dismiss()
            }
        }
        #endif
    }

    private func startPlayback() async {
        playbackGeneration += 1
        let generation = playbackGeneration
        errorMessage = nil
        failedURL = nil
        teardownPlayer()

        let candidate = activeCandidate
        let sourceId = candidate.sourceId
        let episode = candidate.episode

        if !playingLocal, let localURL = downloads.playbackURL(sourceId: sourceId, episodeURL: episode.url) {
            playingLocal = true
            attachPlayer(
                item: PlaybackSupport.makeLocalPlayerItem(url: localURL),
                resolvedURL: localURL.absoluteString,
                generation: generation
            )
            return
        }

        playingLocal = false
        statusMessage = candidates.count > 1
            ? "解析播放地址…（线路 \(candidateIndex + 1)/\(candidates.count)）"
            : "解析播放地址…"

        guard let source = vod.source(for: sourceId) else {
            await failOverOrStop(resolvedURL: episode.url, underlying: "资源站不存在", generation: generation)
            return
        }

        let resolvedURLString: String
        do {
            let parsed = try await vod.parsePlay(sourceId: sourceId, url: episode.url)
            resolvedURLString = parsed.url
        } catch {
            guard RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: playbackGeneration) else {
                return
            }
            if RequestGeneration.isCancellation(error) {
                return
            }
            resolvedURLString = episode.url
        }

        guard RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: playbackGeneration) else {
            return
        }

        guard PlaybackSupport.isDirectMediaURL(resolvedURLString) else {
            await failOverOrStop(resolvedURL: resolvedURLString, underlying: nil, generation: generation)
            return
        }

        guard let playbackURL = RemoteMediaURL.parse(resolvedURLString) else {
            await failOverOrStop(resolvedURL: resolvedURLString, underlying: "无效播放地址", generation: generation)
            return
        }

        statusMessage = "检测线路…"
        let headers = PlaybackSupport.httpHeaders(for: source, playbackURL: playbackURL)
        let playable = await VodMediaProbe.isLikelyPlayable(url: playbackURL, headers: headers)
        guard RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: playbackGeneration) else {
            return
        }
        guard playable else {
            await failOverOrStop(resolvedURL: resolvedURLString, underlying: "线路不可用", generation: generation)
            return
        }

        statusMessage = "起播中…"
        attachPlayer(
            item: PlaybackSupport.makePlayerItem(source: source, playbackURL: playbackURL),
            resolvedURL: resolvedURLString,
            generation: generation
        )
    }

    private func attachPlayer(item: AVPlayerItem, resolvedURL: String, generation: Int) {
        guard RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: playbackGeneration) else {
            return
        }
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        didBecomeReady = false
        player = avPlayer

        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                guard generation == playbackGeneration else { return }
                switch item.status {
                case .failed:
                    await failOverOrStop(
                        resolvedURL: resolvedURL,
                        underlying: item.error?.localizedDescription,
                        generation: generation
                    )
                case .readyToPlay:
                    didBecomeReady = true
                    startTimeoutTask?.cancel()
                    errorMessage = nil
                    seekToResumeIfNeeded(avPlayer)
                    attachTimeObserver(avPlayer)
                default:
                    break
                }
            }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            let underlying = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor in
                guard generation == playbackGeneration else { return }
                await failOverOrStop(resolvedURL: resolvedURL, underlying: underlying, generation: generation)
            }
        }
        startTimeoutTask = Task { @MainActor in
            let nanos = UInt64(HLSPlaylistProbe.startTimeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, generation == playbackGeneration else { return }
            if HLSPlaylistProbe.shouldFailOverForStartTimeout(
                elapsed: HLSPlaylistProbe.startTimeout,
                isReadyToPlay: didBecomeReady
            ) {
                await failOverOrStop(resolvedURL: resolvedURL, underlying: "起播超时", generation: generation)
            }
        }

        avPlayer.play()
    }

    private func seekToResumeIfNeeded(_ avPlayer: AVPlayer) {
        guard resumePositionMs > 0, !didSeekResume else { return }
        didSeekResume = true
        avPlayer.seek(
            to: CMTime(value: resumePositionMs, timescale: 1000),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func attachTimeObserver(_ avPlayer: AVPlayer) {
        if let timeObserver {
            avPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 2, preferredTimescale: 1),
            queue: .main
        ) { _ in
            Task { @MainActor in
                writeWatchHistory(force: false)
            }
        }
    }

    private func writeWatchHistory(force: Bool) {
        guard let historyItem, let player, let recorder else { return }
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, seconds >= 0 else { return }
        var durationMs: Int64 = 0
        if let item = player.currentItem {
            let duration = CMTimeGetSeconds(item.duration)
            if duration.isFinite, duration > 0 {
                durationMs = Int64(duration * 1000)
            }
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        recorder.save(
            WatchHistoryProgress.fromPlayback(
                item: historyItem,
                episode: activeCandidate.episode,
                episodeIndex: historyEpisodeIndex,
                sourceId: activeCandidate.sourceId,
                sourceName: historySourceName,
                positionMs: Int64(seconds * 1000),
                durationMs: durationMs,
                now: now
            ),
            force: force
        )
        if force {
            history.reload()
        }
    }

    private func failOverOrStop(resolvedURL: String, underlying: String?, generation: Int) async {
        guard RequestGeneration.shouldApply(eventGeneration: generation, currentGeneration: playbackGeneration) else {
            return
        }
        if playingLocal {
            if let record = downloads.records.first(where: {
                $0.sourceId == activeCandidate.sourceId && $0.originalURL == activeCandidate.episode.url
            }) {
                downloads.markEvicted(id: record.id)
            }
            playingLocal = false
            await startPlayback()
            return
        }

        if let next = VodPlaybackFailover.nextIndex(after: candidateIndex, count: candidates.count) {
            candidateIndex = next
            statusMessage = "线路失败，切换备用线…"
            teardownPlayer()
            await startPlayback()
            return
        }

        failedURL = resolvedURL
        errorMessage = PlaybackSupport.userFacingError(for: resolvedURL, underlying: underlying)
        teardownPlayer()
    }

    private func teardownPlayer() {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        didBecomeReady = false
        statusObservation?.invalidate()
        statusObservation = nil
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
    }
}

#if os(tvOS)
struct SystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        context.coordinator.onDismiss = onDismiss
        controller.delegate = context.coordinator
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
            onDismiss()
            return false
        }
    }
}
#endif
