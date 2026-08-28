import SwiftUI

struct AppLoadingView: View {
    var message: String = "加载中…"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppTheme.accent)
            Text(message)
                .foregroundStyle(AppTheme.textSecondary)
                #if os(tvOS)
                .font(.title3)
                #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

struct AppErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                #if os(tvOS)
                .font(.system(size: 48))
                #else
                .font(.largeTitle)
                #endif
                .foregroundStyle(AppTheme.accent)

            Text(message)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                #if os(tvOS)
                .font(.title3)
                .padding(.horizontal, TVDesign.screenPadding)
                #endif

            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

struct AppEmptyStateView: View {
    let title: String
    var subtitle: String?
    var systemImage: String = "film"

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                #if os(tvOS)
                .font(.system(size: 56, weight: .light))
                #else
                .font(.system(size: 40, weight: .light))
                #endif
                .foregroundStyle(AppTheme.textTertiary)
            Text(title)
                #if os(tvOS)
                .font(.title2.weight(.semibold))
                #else
                .font(.headline)
                #endif
                .foregroundStyle(AppTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    #if os(tvOS)
                    .font(.body)
                    #endif
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}
