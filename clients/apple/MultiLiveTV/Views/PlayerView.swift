import SwiftUI
import AVKit

struct PlayerView: View {
    let sourceId: Int
    let episode: Episode

    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let errorMessage {
                Text(errorMessage).padding()
            } else {
                ProgressView("解析播放地址…")
            }
        }
        .task { await startPlayback() }
        .onDisappear {
            player?.pause()
            Task { await reportProgress() }
        }
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #endif
    }

    private func startPlayback() async {
        do {
            let parsed = try await api.parsePlay(sourceId: sourceId, url: episode.url)
            let playURL = URL(string: parsed.url) ?? URL(string: episode.url)
            guard let url = playURL else {
                errorMessage = "无效播放地址"
                return
            }
            player = AVPlayer(url: url)
            player?.play()
        } catch {
            if let url = URL(string: episode.url) {
                player = AVPlayer(url: url)
                player?.play()
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reportProgress() async {
        guard api.isLoggedIn, let player else { return }
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration > 0 else { return }
        let key = "\(sourceId):\(episode.url)"
        _ = try? await api.saveProgress(key: key, position: position, duration: duration)
    }
}
