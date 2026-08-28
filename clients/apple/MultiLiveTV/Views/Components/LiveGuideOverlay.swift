import SwiftUI

struct LiveGuideOverlay: View {
    let groups: [LiveGroup]
    let selectedGroup: LiveGroup?
    let playing: LiveChannel?
    var compact: Bool = false
    var focusedId: FocusState<String?>.Binding
    let onSelectGroup: (LiveGroup) -> Void
    let onSelectChannel: (LiveChannel) -> Void
    var onHide: (() -> Void)? = nil

    private var groupWidth: CGFloat { compact ? 200 : 280 }
    private var channelWidth: CGFloat { compact ? 300 : 420 }
    private var sheetGutter: CGFloat { compact ? 10 : 14 }
    private var sheetInset: CGFloat { compact ? 16 : 28 }

    var body: some View {
        HStack(alignment: .top, spacing: sheetGutter) {
            groupColumn
            channelColumn
            dismissCatcher
        }
        .padding(.leading, sheetInset)
        .padding(.vertical, sheetInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: focusedId.wrappedValue) { _, newValue in
            if LiveGuideFocus.shouldDismissGuide(focusedId: newValue) {
                onHide?()
                return
            }
            guard let name = LiveGuideFocus.groupName(fromFocusId: newValue),
                  let group = groups.first(where: { $0.name == name }) else { return }
            onSelectGroup(group)
        }
    }

    private var groupColumn: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    let selected = group.name == selectedGroup?.name
                    LiveGroupRow(
                        title: group.name,
                        count: group.channels.count,
                        isSelected: selected,
                        isFocused: focusedId.wrappedValue == "g:\(group.name)"
                    ) {
                        onSelectGroup(group)
                    }
                    .tvChipFocused(focusedId, equals: "g:\(group.name)")
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
        }
        .frame(width: groupWidth)
        .frame(maxHeight: .infinity)
        .liveGuideSheet()
        .tvFocusSection()
    }

    private var channelColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((selectedGroup?.channels ?? []).enumerated()), id: \.element.id) { index, channel in
                        LiveChannelRow(
                            number: index + 1,
                            channel: channel,
                            isPlaying: playing?.id == channel.id,
                            isFocused: focusedId.wrappedValue == "c:\(channel.id)"
                        ) {
                            onSelectChannel(channel)
                        }
                        .tvChipFocused(focusedId, equals: "c:\(channel.id)")
                        .id(channel.id)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 10)
            }
            .onChange(of: playing?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                if let id = playing?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(width: channelWidth)
        .frame(maxHeight: .infinity)
        .liveGuideSheet()
        .tvFocusSection()
        #if os(tvOS)
        .onMoveCommand { direction in
            if direction == .right {
                onHide?()
            }
        }
        #endif
    }

    private var dismissCatcher: some View {
        Button {
            onHide?()
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .hiddenFocusChrome()
        .accessibilityLabel("全屏观看")
        .tvChipFocused(focusedId, equals: LiveGuideFocus.dismissId)
        .tvFocusSection()
    }
}

struct LiveGuidePanelBackground: View {
    private let radius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(0.58))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct LiveGuideSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background { LiveGuidePanelBackground() }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func liveGuideSheet() -> some View {
        modifier(LiveGuideSheetModifier())
    }
}

struct LiveClockBadge: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.stamp.string(from: context.date))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.48), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
        }
        .accessibilityAddTraits(.updatesFrequently)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct LiveNowPlayingBar: View {
    let channel: LiveChannel
    var number: Int?
    var streamIndex: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            if let number {
                Text("\(number)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(streamCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(channel.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.42))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.45), lineWidth: 1)
        }
    }

    private var streamCaption: String {
        let count = channel.streams.count
        guard count > 1 else { return channel.group }
        let line = min(max(streamIndex, 0), count - 1) + 1
        return "\(channel.group) · 线路 \(line)/\(count)"
    }
}
