import SwiftUI

@main
struct fnFlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() } // no visible settings window
    }
}
