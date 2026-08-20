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

/// `WindowGroup`'s built-in "click the Dock icon to bring the window back"
/// isn't firing on this setup — confirmed directly: after closing the
/// window and clicking the Dock icon, the process stays alive and correctly
/// foregrounded, but zero windows exist afterward, not even an off-screen
/// one. So this asks explicitly instead of relying on the implicit default.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openWindowAction: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindowAction?()
        }
        return true
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let log = Logger(subsystem: "com.pholtom.blooming8app", category: "ui")

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(settings: env.settings, controller: env.controller)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    Self.log.notice("app: window appeared")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .background(WindowOpenerCapture(appDelegate: appDelegate))
        }
        .defaultSize(width: 1180, height: 760)
    }
}

/// Invisible — exists only to capture `@Environment(\.openWindow)` from a
/// genuine View context (the only place it's guaranteed to resolve
/// correctly; reading it directly on the `App` type is not a documented,
/// reliable path) and hand the action to `AppDelegate`, which can't read
/// `@Environment` itself.
private struct WindowOpenerCapture: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                appDelegate.openWindowAction = { openWindow(id: "main") }
            }
    }
}
