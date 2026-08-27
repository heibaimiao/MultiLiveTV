import SwiftUI

struct AppLoadingView: View {
    var message: String = "加载中…"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
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
            Image(systemName: "exclamationmark.triangle")
                #if os(tvOS)
                .font(.system(size: 48))
                #else
                .font(.largeTitle)
                #endif
                .foregroundStyle(.secondary)

            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                #if os(tvOS)
                .font(.title3)
                .padding(.horizontal, TVDesign.screenPadding)
                #endif

            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
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

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                #if os(tvOS)
                .font(.system(size: 56))
                #else
                .font(.largeTitle)
                #endif
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                #if os(tvOS)
                .font(.title2)
                #endif
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    #if os(tvOS)
                    .font(.body)
                    #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}
