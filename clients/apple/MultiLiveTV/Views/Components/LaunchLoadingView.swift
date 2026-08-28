import SwiftUI

#if os(tvOS)
struct LaunchLoadingView: View {
    var errorMessage: String? = nil
    var retry: (() -> Void)? = nil
    @FocusState private var retryFocused: Bool

    var body: some View {
        ZStack {
            AppTheme.screenBackground

            Group {
                if let errorMessage, let retry {
                    errorBlock(message: errorMessage, retry: retry)
                } else {
                    loadingBlock
                }
            }
            .offset(y: -48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var loadingBlock: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("加载中")
                .foregroundStyle(AppTheme.textSecondary)
                .font(.title3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在加载首页")
    }

    private func errorBlock(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Text(message)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding(.horizontal, AppTheme.screenPadding)

            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .focused($retryFocused)
        }
        .defaultFocus($retryFocused, true)
    }
}
#endif
