import SwiftUI

struct VodPosterView: View {
    @EnvironmentObject private var vod: VodService

    let sourceId: Int
    let vodId: String
    let initialURL: String
    var cornerRadius: CGFloat = 10
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(alignment: .topTrailing) {
            if let showRemarks, !showRemarks.isEmpty {
                Text(showRemarks)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(8)
            }
        }
        .task(id: taskKey) {
            await resolveImageURL()
        }
    }

    @ViewBuilder
    private var posterContent: some View {
        AsyncImage(url: resolvedURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            default:
                if didFail && resolvedURL == nil {
                    placeholder
                } else {
                    AppTheme.tertiaryFill
                        .overlay { ProgressView() }
                }
            }
        }
    }

    private var placeholder: some View {
        AppTheme.tertiaryFill
            .overlay {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }

    private var taskKey: String {
        "\(sourceId)-\(vodId)-\(initialURL)"
    }

    private func resolveImageURL() async {
        didFail = false

        if let url = normalizedURL(initialURL) {
            resolvedURL = url
            return
        }

        do {
            if let pic = try await vod.fetchVodPic(sourceId: sourceId, vodId: vodId),
               let url = normalizedURL(pic) {
                resolvedURL = url
            } else {
                didFail = true
            }
        } catch {
            didFail = true
        }
    }

    private func normalizedURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
