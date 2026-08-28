import Foundation
import SwiftUI
import UIKit

#if os(tvOS) && canImport(TVVLCKit)
import TVVLCKit
#elseif os(iOS) && canImport(MobileVLCKit)
import MobileVLCKit
#endif

final class VLCLivePlayer: NSObject, ObservableObject {
    static var isAvailable: Bool {
        #if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
        true
        #else
        false
        #endif
    }

    static let unavailableMessage = "当前线路需要 VLC 播放（HTTP-FLV / 组播）。请在 clients/apple 执行 pod install，然后打开 MultiLiveTV.xcworkspace。"

    var onPlaying: (() -> Void)?
    var onFailed: ((String) -> Void)?

    #if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
    private let mediaPlayer = VLCMediaPlayer()
    private var pendingStart = false
    #endif

    init(url: URL, headers: [String: String]) {
        super.init()
        #if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
        let media = VLCMedia(url: url)
        for option in LivePlayback.vlcHTTPOptions(headers: headers) {
            media.addOption(option)
        }
        mediaPlayer.delegate = self
        mediaPlayer.media = media
        #else
        _ = url
        _ = headers
        #endif
    }

    func attach(to view: UIView) {
        #if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
        if let current = mediaPlayer.drawable as? UIView, current === view { return }
        mediaPlayer.drawable = view
        if pendingStart {
            pendingStart = false
            mediaPlayer.play()
        }
        #endif
    }

    func start() {
        #if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
        if mediaPlayer.drawable != nil {
            mediaPlayer.play()
        } else {
            pendingStart = true
        }
        #endif
    }

    func togglePause() {
        #if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
        #endif
    }

    func stop() {
        #if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
        pendingStart = false
        mediaPlayer.delegate = nil
        mediaPlayer.stop()
        mediaPlayer.drawable = nil
        #endif
        onPlaying = nil
        onFailed = nil
    }
}

#if (os(tvOS) && canImport(TVVLCKit)) || (os(iOS) && canImport(MobileVLCKit))
extension VLCLivePlayer: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        _ = aNotification
        let state = mediaPlayer.state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .playing, .esAdded:
                self.onPlaying?()
            case .error, .ended:
                self.onFailed?("播放失败")
            default:
                break
            }
        }
    }
}
#endif

struct VLCVideoStage: UIViewRepresentable {
    let player: VLCLivePlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        player.attach(to: uiView)
    }
}
