import AVFoundation
import Combine
import Foundation

@MainActor
final class LivePlaybackSession: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var vlcPlayer: VLCLivePlayer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var channel: LiveChannel?
    @Published private(set) var isStarting = false

    var hasRenderer: Bool { player != nil || vlcPlayer != nil }

    @Published private(set) var streamIndex = 0
    private var statusObservation: NSKeyValueObservation?
    private var failObserver: NSObjectProtocol?
    private var startTimeoutTask: Task<Void, Never>?
    private var playbackGeneration = 0
    private var isActive = false
    private var didBecomeReady = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
        playbackGeneration += 1
        teardown()
    }

    func play(_ channel: LiveChannel) async {
        guard isActive else { return }
        if self.channel?.id == channel.id, hasRenderer, errorMessage == nil {
            return
        }
        self.channel = channel
        LiveWatchMemory.save(channel.id, to: defaults)
        streamIndex = 0
        await startPlayback()
    }

    func retry() async {
        streamIndex = 0
        await startPlayback()
    }

    func togglePause() {
        if let player {
            if player.rate == 0 {
                player.play()
            } else {
                player.pause()
            }
            return
        }
        vlcPlayer?.togglePause()
    }

    func cycleStream() async {
        guard isActive, let channel else { return }
        guard let next = LivePlayback.cycleURLIndex(after: streamIndex, count: channel.streams.count) else {
            return
        }
        streamIndex = next
        await startPlayback()
    }

    private func startPlayback() async {
        playbackGeneration += 1
        let generation = playbackGeneration
        errorMessage = nil
        teardown()
        guard isActive, !Task.isCancelled else { return }
        guard let channel, streamIndex < channel.streams.count else {
            errorMessage = "播放失败，请换线路重试"
            isStarting = false
            return
        }

        isStarting = true
        let stream = channel.streams[streamIndex]
        let raw = stream.url
        guard let playbackURL = RemoteMediaURL.parse(raw) else {
            await failOverOrStop(
                message: PlaybackSupport.userFacingError(for: raw, underlying: nil),
                generation: generation
            )
            return
        }

        let probeHeaders = LivePlayback.playerHeaders(kodi: stream.headers, cookieHeader: nil)
        let probed = await probePlaylist(url: playbackURL, headers: probeHeaders, generation: generation)
        guard LivePlayback.shouldApplyFailure(eventGeneration: generation, currentGeneration: playbackGeneration) else {
            return
        }
        let headers = LivePlayback.playerHeaders(kodi: stream.headers, cookieHeader: probed.cookie)
        switch probed.decision {
        case .playable:
            attachAVPlayer(url: playbackURL, headers: headers, raw: raw, generation: generation)
        case .flv:
            guard VLCLivePlayer.isAvailable else {
                await failOverOrStop(message: VLCLivePlayer.unavailableMessage, generation: generation)
                return
            }
            attachVLCPlayer(url: playbackURL, headers: headers, raw: raw, generation: generation)
        case .retry, .reject:
            await failOverOrStop(
                message: PlaybackSupport.userFacingError(for: raw, underlying: nil),
                generation: generation
            )
        }
    }

    private func attachAVPlayer(url: URL, headers: [String: String], raw: String, generation: Int) {
        let item = PlaybackSupport.makePlayerItem(playbackURL: url, headers: headers)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        guard LivePlayback.shouldApplyFailure(eventGeneration: generation, currentGeneration: playbackGeneration) else {
            return
        }
        didBecomeReady = false
        player = avPlayer
        isStarting = false

        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                guard LivePlayback.shouldApplyFailure(eventGeneration: generation, currentGeneration: self.playbackGeneration) else {
                    return
                }
                switch item.status {
                case .failed:
                    await self.failOverOrStop(
                        message: PlaybackSupport.userFacingError(
                            for: raw,
                            underlying: item.error?.localizedDescription
                        ),
                        generation: generation
                    )
                case .readyToPlay:
                    self.didBecomeReady = true
                    self.startTimeoutTask?.cancel()
                    self.errorMessage = nil
                default:
                    break
                }
            }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let underlying = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor in
                await self?.failOverOrStop(
                    message: PlaybackSupport.userFacingError(for: raw, underlying: underlying),
                    generation: generation
                )
            }
        }
        watchStartTimeout(raw: raw, generation: generation)
        avPlayer.play()
    }

    private func attachVLCPlayer(url: URL, headers: [String: String], raw: String, generation: Int) {
        let vlc = VLCLivePlayer(url: url, headers: headers)
        vlc.onPlaying = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard LivePlayback.shouldApplyFailure(eventGeneration: generation, currentGeneration: self.playbackGeneration) else {
                    return
                }
                self.didBecomeReady = true
                self.startTimeoutTask?.cancel()
                self.errorMessage = nil
            }
        }
        vlc.onFailed = { [weak self] message in
            Task { @MainActor in
                await self?.failOverOrStop(
                    message: PlaybackSupport.userFacingError(for: raw, underlying: message),
                    generation: generation
                )
            }
        }
        didBecomeReady = false
        vlcPlayer = vlc
        isStarting = false
        watchStartTimeout(raw: raw, generation: generation)
        vlc.start()
    }

    private func watchStartTimeout(raw: String, generation: Int) {
        startTimeoutTask = Task { @MainActor in
            let nanos = UInt64(HLSPlaylistProbe.startTimeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            guard LivePlayback.shouldApplyFailure(eventGeneration: generation, currentGeneration: self.playbackGeneration) else {
                return
            }
            if HLSPlaylistProbe.shouldFailOverForStartTimeout(
                elapsed: HLSPlaylistProbe.startTimeout,
                isReadyToPlay: self.didBecomeReady
            ) {
                await self.failOverOrStop(
                    message: PlaybackSupport.userFacingError(for: raw, underlying: "起播超时"),
                    generation: generation
                )
            }
        }
    }

    private func probePlaylist(
        url: URL,
        headers: [String: String],
        generation: Int
    ) async -> (decision: HLSPlaylistProbe.Decision, cookie: String?) {
        var attempt = 0
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = NetworkConfig.requestTimeout
        config.timeoutIntervalForResource = NetworkConfig.requestTimeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        while true {
            guard LivePlayback.shouldApplyFailure(eventGeneration: generation, currentGeneration: playbackGeneration) else {
                return (.reject, nil)
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = NetworkConfig.requestTimeout
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            do {
                let (bytes, response) = try await session.bytes(for: request)
                var body = Data()
                body.reserveCapacity(HLSPlaylistProbe.probeByteLimit)
                for try await byte in bytes {
                    body.append(byte)
                    if body.count >= HLSPlaylistProbe.probeByteLimit {
                        break
                    }
                }
                bytes.task.cancel()
                let http = response as? HTTPURLResponse
                let decision = HLSPlaylistProbe.evaluate(
                    statusCode: http?.statusCode ?? 0,
                    contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                    body: body,
                    pendingAttempt: attempt
                )
                switch decision {
                case .playable, .flv:
                    return (
                        decision,
                        LivePlayback.cookieHeader(from: response, storage: session.configuration.httpCookieStorage)
                    )
                case .retry:
                    attempt += 1
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                case .reject:
                    return (.reject, nil)
                }
            } catch {
                return (.reject, nil)
            }
        }
    }

    private func failOverOrStop(message: String, generation: Int) async {
        guard isActive, LivePlayback.shouldApplyFailure(eventGeneration: generation, currentGeneration: playbackGeneration) else {
            return
        }
        let count = channel?.streams.count ?? 0
        if let next = LivePlayback.nextURLIndex(after: streamIndex, count: count) {
            streamIndex = next
            await startPlayback()
        } else {
            errorMessage = message
            isStarting = false
            teardown()
        }
    }

    private func teardown() {
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
        vlcPlayer?.stop()
        vlcPlayer = nil
    }
}
