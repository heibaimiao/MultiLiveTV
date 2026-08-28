import SwiftUI

struct DownloadGlyphButton: View {
    let record: DownloadRecord?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                switch record?.status {
                case .none:
                    Image(systemName: "arrow.down.circle")
                case .queued, .resolving:
                    Image(systemName: "clock")
                case .downloading:
                    ProgressView(value: record?.fraction ?? 0)
                        .frame(width: 22, height: 22)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                case .failed, .evicted:
                    Image(systemName: "exclamationmark.circle")
                case .paused:
                    Image(systemName: "pause.circle")
                }
            }
            #if os(tvOS)
            .font(.title2)
            #else
            .font(.title3)
            #endif
            .foregroundStyle(AppTheme.accent)
        }
        .disabled(!canStart)
        #if os(iOS)
        .buttonStyle(.borderless)
        #endif
        .accessibilityLabel(record?.statusLabel ?? "下载")
    }

    private var canStart: Bool {
        record?.allowsNewDownload ?? true
    }
}
