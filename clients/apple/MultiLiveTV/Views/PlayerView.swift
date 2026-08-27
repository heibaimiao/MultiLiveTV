import SwiftUI
import AVKit

struct PlaybackRequest: Identifiable {
    let sourceId: Int
    let episode: Episode

    var id: String { "\(sourceId)-\(episode.id)" }
}

struct PlayerView: View {
    let sourceId: Int
    let episode: Episode

    @EnvironmentObject private var vod: VodService
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var statusObservation: NSKeyValueObservation?
    @State private var failedURL: String?

    var body: some View {
        ZStack {
            AppTheme.screenBackground.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let errorMessage {
                AppErrorView(message: errorMessage) {
                    Task { await startPlayback() }
                }
            } else {
                AppLoadingView(message: "解析播放地址…")
            }
        }
        .task(id: episode.id) { await startPlayback() }
        .onDisappear {
            statusObservation?.invalidate()
            statusObservation = nil
            player?.pause()
            player = nil
        }
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #endif
    }

    private func startPlayback() async {
        errorMessage = nil
        failedURL = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil

        guard let source = vod.source(for: sourceId) else {
            errorMessage = "资源站不存在"
            return
        }

        let resolvedURLString: String
        do {
            let parsed = try await vod.parsePlay(sourceId: sourceId, url: episode.url)
            resolvedURLString = parsed.url
        } catch {
            resolvedURLString = episode.url
        }

        guard PlaybackSupport.isDirectMediaURL(resolvedURLString) else {
            failedURL = resolvedURLString
            errorMessage = PlaybackSupport.userFacingError(for: resolvedURLString, underlying: nil)
            return
        }

        guard let playbackURL = makePlaybackURL(from: resolvedURLString) else {
            errorMessage = "无效播放地址"
            return
        }

        let item = PlaybackSupport.makePlayerItem(source: source, playbackURL: playbackURL)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        player = avPlayer

        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .failed:
                    let underlying = item.error?.localizedDescription
                    errorMessage = PlaybackSupport.userFacingError(
                        for: resolvedURLString,
                        underlying: underlying
                    )
                    player = nil
                case .readyToPlay:
                    errorMessage = nil
                default:
                    break
                }
            }
        }

        avPlayer.play()
    }

    private func makePlaybackURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) { return url }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        return encoded.flatMap { URL(string: $0) }
    }
}
