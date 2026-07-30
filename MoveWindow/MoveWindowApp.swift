import SwiftUI
import SwiftData

@main
struct MoveWindowApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: ActivitySession.self)
    }
}
