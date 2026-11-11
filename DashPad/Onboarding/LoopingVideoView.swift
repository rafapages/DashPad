// DashPad: https://github.com/rafapages/DashPad
// Licensed under PolyForm Noncommercial 1.0.0. Commercial use requires a separate license: dashpad@rafapages.com

// LoopingVideoView.swift - a silent, seamlessly looping video for the setup flow's stage.

import AVFoundation
import SwiftUI

/// Plays a bundled clip on a loop, muted, filling its frame. Playback stops when the view goes
/// away, and resumes when the app returns to the foreground, where AVPlayer pauses on its own.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    /// Off shows the first frame only, for Reduce Motion.
    var autoplays = true

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.load(url, autoplays: autoplays)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: LoopingPlayerView, coordinator: ()) {
        uiView.stop()
    }
}

final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var foregroundObserver: NSObjectProtocol?
    private var autoplays = true

    func load(_ url: URL, autoplays: Bool) {
        self.autoplays = autoplays

        let player = AVQueuePlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        // The looper keeps the queue stocked with copies of the item, so the loop has no gap.
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        self.player = player

        if let layer = layer as? AVPlayerLayer {
            layer.player = player
            layer.videoGravity = .resizeAspectFill
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        resume()
    }

    private func resume() {
        if autoplays { player?.play() }
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        foregroundObserver = nil
    }
}
