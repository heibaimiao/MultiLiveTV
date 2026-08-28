import AVFoundation
import SwiftUI
import UIKit

struct LiveVideoStage: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerView {
        PlayerLayerView()
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }
}
