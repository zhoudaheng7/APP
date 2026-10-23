import SwiftUI

@main
struct FlickApp: App {
    @StateObject private var link = PeerLink()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            FlickRootView(link: link)
                .tint(.green)
                .task { link.activate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { link.activate() }
                    else if phase == .background { link.suspend() }
                }
        }
    }
}
