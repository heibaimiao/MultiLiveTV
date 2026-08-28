import SwiftUI

struct LiveGroupRow: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var isFocused: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tickColor)
                    .frame(width: 3, height: 18)
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeForeground)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(badgeBackground, in: Capsule())
            }
            .foregroundStyle(foreground)
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusEffectDisabled()
        #endif
    }

    private var tickColor: Color {
        if isFocused || isSelected { return AppTheme.accent }
        return .clear
    }

    private var foreground: Color {
        if isFocused || isSelected { return AppTheme.accent }
        return AppTheme.textSecondary
    }

    private var background: Color {
        if isFocused { return AppTheme.accent.opacity(0.20) }
        if isSelected { return Color.white.opacity(0.08) }
        return .clear
    }

    private var badgeForeground: Color {
        if isFocused || isSelected { return AppTheme.accent.opacity(0.9) }
        return AppTheme.textTertiary
    }

    private var badgeBackground: Color {
        if isFocused { return AppTheme.accent.opacity(0.18) }
        return Color.white.opacity(0.08)
    }
}

struct LiveChannelRow: View {
    private static let onAccent = Color(red: 0.10, green: 0.07, blue: 0.03)

    let number: Int
    let channel: LiveChannel
    var isPlaying: Bool = false
    var isFocused: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(numberForeground)
                    .frame(width: 36, height: 24)
                    .background(numberBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(channel.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isFocused ? Self.onAccent : AppTheme.accent)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusEffectDisabled()
        #endif
    }

    private var foreground: Color {
        if isFocused { return Self.onAccent }
        if isPlaying { return AppTheme.textPrimary }
        return AppTheme.textSecondary
    }

    private var background: Color {
        if isFocused { return AppTheme.accent }
        if isPlaying { return AppTheme.accent.opacity(0.14) }
        return .clear
    }

    private var numberForeground: Color {
        if isFocused { return Self.onAccent }
        if isPlaying { return AppTheme.accent }
        return AppTheme.textTertiary
    }

    private var numberBackground: Color {
        if isFocused { return Self.onAccent.opacity(0.16) }
        if isPlaying { return AppTheme.accent.opacity(0.16) }
        return Color.white.opacity(0.10)
    }
}
