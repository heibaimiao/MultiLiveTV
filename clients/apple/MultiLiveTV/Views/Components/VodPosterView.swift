import SwiftUI

struct VodPosterView: View {
    @EnvironmentObject private var vod: VodService

    let sourceId: Int
    let vodId: String
    let initialURL: String
    var cornerRadius: CGFloat = 8
    var showRemarks: String?

    @State private var resolvedURL: URL?
    @State private var didFail = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                posterContent
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let showRemarks, !showRemarks.isEmpty {
                Text(showRemarks)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(8)
            }
        }
        .task(id: taskKey) {
            await resolveImageURL()
        }
    }

    @ViewBuilder
    private var posterContent: some View {
        RemoteImageView(url: resolvedURL ?? RemoteMediaURL.parse(initialURL)) { phase in
            posterPhase(phase)
        }
    }

    @ViewBuilder
    private func posterPhase(_ phase: RemoteImagePhase) -> some View {
        switch phase {
        case .success(let image):
            image
                .resizable()
                .scaledToFill()
        case .failure:
            placeholder
        case .empty:
            if didFail && RemoteMediaURL.parse(initialURL) == nil && resolvedURL == nil {
                placeholder
            } else {
                AppTheme.tertiaryFill
                    .overlay {
                        #if os(iOS)
                        ProgressView()
                            .tint(AppTheme.textTertiary)
                        #else
                        Color.clear
                        #endif
                    }
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [AppTheme.elevated, AppTheme.tertiaryFill],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var taskKey: String {
        "\(sourceId)-\(vodId)-\(initialURL)"
    }

    private func resolveImageURL() async {
        didFail = false

        if RemoteMediaURL.parse(initialURL) != nil {
            return
        }

        do {
            if let pic = try await vod.fetchVodPic(sourceId: sourceId, vodId: vodId),
               let url = RemoteMediaURL.parse(pic) {
                guard !Task.isCancelled else { return }
                resolvedURL = url
            } else {
                guard !Task.isCancelled else { return }
                didFail = true
            }
        } catch {
            guard !Task.isCancelled, !RequestGeneration.isCancellation(error) else { return }
            didFail = true
        }
    }
}
