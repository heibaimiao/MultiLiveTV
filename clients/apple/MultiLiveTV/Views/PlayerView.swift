import AVKit
import SwiftUI

struct PlaybackRequest: Identifiable {
    let sourceId: Int
    let episode: Episode

    var id: String { "\(sourceId)-\(episode.id)" }
}

struct PlayerView: View {
    let sourceId: Int
    let episode: Episode

    @EnvironmentObject private var vod: VodService
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var failObserver: NSObjectProtocol?
    @State private var startTimeoutTask: Task<Void, Never>?
    @State private var playbackGeneration = 0
    @State private var failedURL: String?
    @State private var playingLocal = false
    @State private var didBecomeReady = false

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
                    Task { await startPlayback() }
                }
            } else {
                AppLoadingView(message: playingLocal ? "正在打开本地影片…" : "解析播放地址…")
            }
        }
        .task(id: episode.id) { await startPlayback() }
        .onDisappear {
            playbackGeneration += 1
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

        guard let source = vod.source(for: sourceId) else {
            errorMessage = "资源站不存在"
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
            failedURL = resolvedURLString
            errorMessage = PlaybackSupport.userFacingError(for: resolvedURLString, underlying: nil)
            return
        }

        guard let playbackURL = RemoteMediaURL.parse(resolvedURLString) else {
            errorMessage = "无效播放地址"
            return
        }

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
                    await handlePlaybackFailure(resolvedURL: resolvedURL, underlying: item.error?.localizedDescription)
                case .readyToPlay:
                    didBecomeReady = true
                    startTimeoutTask?.cancel()
                    errorMessage = nil
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
                await handlePlaybackFailure(resolvedURL: resolvedURL, underlying: underlying)
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
                await handlePlaybackFailure(resolvedURL: resolvedURL, underlying: "起播超时")
            }
        }

        avPlayer.play()
    }

    private func handlePlaybackFailure(resolvedURL: String, underlying: String?) async {
        if playingLocal {
            if let record = downloads.records.first(where: {
                $0.sourceId == sourceId && $0.originalURL == episode.url
            }) {
                downloads.markEvicted(id: record.id)
            }
            playingLocal = false
            await startPlayback()
            return
        }
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
