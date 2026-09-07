import SwiftUI

@main
struct WhaleCalApp: App {
    @State private var model = CalendarConnectionModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CalendarHomeView(model: model)
                .preferredColorScheme(.dark)
                .tint(Whale.accent)
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.start() }
                    if phase == .background { model.stop() }
                }
        }
    }
}
