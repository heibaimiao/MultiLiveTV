import SwiftUI

struct LiveView: View {
    @StateObject private var live = LiveService()
    @StateObject private var session = LivePlaybackSession()
    @State private var selectedGroupName: String?
    @State private var showGuide = true
    @State private var showNameplate = false
    @State private var nameplateGeneration = 0
    @FocusState private var focusedId: String?

    private var selectedGroup: LiveGroup? {
        if let selectedGroupName,
           let match = live.groups.first(where: { $0.name == selectedGroupName }) {
            return match
        }
        return live.groups.first
    }

    var body: some View {
        Group {
            if let configurationError = live.configurationError, live.groups.isEmpty {
                AppErrorView(message: configurationError) {
                    Task { await live.reload() }
                }
            } else if !live.hasConfiguredSource {
                AppEmptyStateView(
                    title: "尚未配置直播源",
                    subtitle: "请在 lives.json 填写 M3U 地址",
                    systemImage: "dot.radiowaves.left.and.right"
                )
            } else if live.isLoading && live.groups.isEmpty {
                AppLoadingView(message: "正在加载直播…")
            } else if let errorMessage = live.errorMessage, live.groups.isEmpty {
                AppErrorView(message: errorMessage) {
                    Task { await live.reload() }
                }
            } else if live.groups.isEmpty {
                AppEmptyStateView(
                    title: "暂无频道",
                    subtitle: "请检查 M3U 是否有效",
                    systemImage: "dot.radiowaves.left.and.right"
                )
            } else {
                stage
            }
        }
        .task {
            session.activate()
            await live.reload()
            await startCurrentChannel()
        }
        .onAppear {
            session.activate()
            Task { await startCurrentChannel() }
        }
        .onDisappear {
            session.deactivate()
        }
        .onChange(of: live.groups) { _, _ in
            Task { await startCurrentChannel() }
        }
        .modifier(LiveTabBarVisibility(visible: showGuide || live.groups.isEmpty))
    }

    private var stage: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 900
            ZStack {
                if let vlcPlayer = session.vlcPlayer {
                    VLCVideoStage(player: vlcPlayer)
                        .ignoresSafeArea()
                } else {
                    LiveVideoStage(player: session.player)
                        .ignoresSafeArea()
                }

                AppTheme.screenBackground
                    .opacity(session.hasRenderer ? 0 : 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let errorMessage = session.errorMessage, !session.hasRenderer {
                    playbackStatus(
                        message: errorMessage,
                        retry: { Task { await session.retry() } }
                    )
                } else if !session.hasRenderer {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("正在打开 \(session.channel?.name ?? "直播")…")
                            .font(.headline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                if showGuide {
                    LiveGuideOverlay(
                        groups: live.groups,
                        selectedGroup: selectedGroup,
                        playing: session.channel,
                        compact: compact,
                        focusedId: $focusedId,
                        onSelectGroup: { group in
                            selectedGroupName = group.name
                        },
                        onSelectChannel: { channel in
                            Task {
                                await session.play(channel)
                                setGuideVisible(false)
                            }
                        },
                        onHide: { setGuideVisible(false) }
                    )
                } else {
                    immersiveCatcher
                }

                if showGuide {
                    VStack {
                        HStack {
                            Spacer()
                            LiveClockBadge()
                        }
                        Spacer()
                    }
                    .padding(.top, compact ? 16 : 24)
                    .padding(.trailing, compact ? 20 : 32)
                    .allowsHitTesting(false)
                } else if showNameplate, let channel = session.channel {
                    VStack {
                        Spacer()
                        LiveNowPlayingBar(
                            channel: channel,
                            number: selectedGroup.flatMap {
                                LiveChannelNumber.displayIndex(in: $0, channelId: channel.id)
                            },
                            streamIndex: session.streamIndex
                        )
                        .padding(.horizontal, compact ? 20 : 36)
                        .padding(.bottom, compact ? 24 : 36)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(.easeInOut(duration: 0.22), value: showGuide)
        .animation(.easeInOut(duration: 0.22), value: showNameplate)
        #if os(tvOS)
        .onExitCommand {
            applyRemote(.menu)
        }
        .onPlayPauseCommand {
            applyRemote(.playPause)
        }
        #endif
    }

    private var immersiveCatcher: some View {
        Button {
            applyRemote(.select)
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .hiddenFocusChrome()
        .accessibilityLabel("显示频道列表")
        #if os(tvOS)
        .onMoveCommand { direction in
            applyRemote(.move(Self.liveDirection(direction)))
        }
        #endif
    }

    @ViewBuilder
    private func playbackStatus(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(!showGuide)
    }

    private func applyRemote(_ event: LiveRemoteEvent) {
        switch LiveRemoteRouter.effect(showGuide: showGuide, event: event) {
        case .zap(let delta):
            Task { await zap(by: delta) }
        case .showGuide:
            setGuideVisible(true)
        case .hideGuide:
            setGuideVisible(false)
        case .togglePause:
            session.togglePause()
        case .cycleStream:
            Task {
                await session.cycleStream()
                revealNameplate()
            }
        case .none:
            break
        }
    }

    private func zap(by delta: Int) async {
        guard let pick = LiveChannelZap.neighbor(
            groups: live.groups,
            currentId: session.channel?.id,
            delta: delta
        ) else { return }
        selectedGroupName = pick.group.name
        await session.play(pick.channel)
        revealNameplate()
    }

    #if os(tvOS)
    private static func liveDirection(_ direction: MoveCommandDirection) -> LiveRemoteDirection {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        @unknown default: return .down
        }
    }
    #endif

    private func setGuideVisible(_ visible: Bool) {
        showGuide = visible
        if visible {
            showNameplate = false
            if let channel = session.channel {
                selectedGroupName = channel.group
                focusedId = "c:\(channel.id)"
            }
            return
        }
        revealNameplate()
    }

    private func revealNameplate() {
        nameplateGeneration += 1
        let generation = nameplateGeneration
        showNameplate = true
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard generation == nameplateGeneration else { return }
            showNameplate = false
        }
    }

    private func startCurrentChannel() async {
        let lastId = session.channel?.id ?? LiveWatchMemory.load()
        guard let pick = LiveResume.resolve(groups: live.groups, lastChannelId: lastId) else { return }
        selectedGroupName = pick.group.name
        await session.play(pick.channel)
        if showGuide {
            focusedId = "c:\(pick.channel.id)"
        }
    }
}

private struct LiveTabBarVisibility: ViewModifier {
    var visible: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.0, tvOS 18.0, *) {
            content.toolbar(visible ? .automatic : .hidden, for: .tabBar)
        } else {
            content
        }
    }
}
