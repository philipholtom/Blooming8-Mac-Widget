import Blooming8Core
import AppKit
import SwiftUI
import os

/// Owns the two long-lived objects the whole window tree shares. Held by a
/// single `@StateObject` so `PhotoController` can be handed the same
/// `AppSettings` instance it was built from.
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: AppSettings
    let controller: PhotoController

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.controller = PhotoController(settings: settings)
    }
}

/// SwiftUI App lifecycle rather than an AppKit `NSWindow` +
/// `NSHostingController`: `NavigationSplitView` needs a real `Scene` to wire
/// up its columns, and inside a hand-built window it renders but its sidebar
/// selection never binds — rows don't even highlight. The `Scene` also gives
/// us the standard menu bar for free.
@main
struct Blooming8AppMain: App {
    @StateObject private var env = AppEnvironment()

    private static let log = Logger(subsystem: "com.pholtom.blooming8app", category: "ui")

    var body: some Scene {
        WindowGroup {
            RootView(settings: env.settings, controller: env.controller)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    Self.log.notice("app: window appeared")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
