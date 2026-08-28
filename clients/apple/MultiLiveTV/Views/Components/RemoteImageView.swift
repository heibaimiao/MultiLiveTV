import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum RemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

struct RemoteImageView<Content: View>: View {
    let url: URL?
    @ViewBuilder var content: (RemoteImagePhase) -> Content

    @State private var phase: RemoteImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: url?.absoluteString ?? "") {
                await load()
            }
    }

    private func load() async {
        phase = .empty
        guard let url else {
            return
        }

        do {
            let data = try await RemoteImageLoader.shared.data(for: url)
            guard !Task.isCancelled else { return }
            if let image = makeImage(from: data) {
                phase = .success(image)
            } else {
                phase = .failure
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                phase = .failure
            }
        }
    }

    private func makeImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}
