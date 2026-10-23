import SwiftUI
import AVKit

struct SelectedMediaPreview: View {
    let asset: PhotoAsset
    @State private var player: AVPlayer?
    @State private var image: UIImage?
    var body: some View {
        Group {
            if asset.kind == .video, let player = player { VideoPlayer(player: player) }
            else { Image(uiImage: image ?? asset.image).resizable().scaledToFit() }
        }
        .task(id: asset.id) {
            player?.pause(); player = nil; image = nil
            if asset.kind == .video {
                let value = AVPlayer(url: asset.url); value.isMuted = true; player = value
            } else if asset.kind == .photo {
                let url = asset.url
                let value = await Task.detached(priority: .userInitiated) { try? PhotoFiles.thumbnail(url) }.value
                if !Task.isCancelled { image = value }
            }
        }
        .onDisappear { player?.pause() }
    }
}
