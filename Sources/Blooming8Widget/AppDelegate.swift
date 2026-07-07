import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let settings = Settings()
    private lazy var controller = PhotoController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Blooming8")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem

        let hostingController = NSHostingController(rootView: ContentView(settings: settings, controller: controller))
        // Let the popover grow/shrink to fit however many galleries are listed,
        // instead of a fixed height that needs an inner scroll view.
        hostingController.sizingOptions = [.preferredContentSize]

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = hostingController
        self.popover = popover
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender as AnyObject)
        }
    }

    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Random Photo", action: #selector(randomPhotoFromMenu), keyEquivalent: "r")
            .target = self
        menu.addItem(withTitle: "Wake Frame", action: #selector(wakeFrameFromMenu), keyEquivalent: "w")
            .target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Blooming8 Widget", action: #selector(quitApp), keyEquivalent: "q")
            .target = self

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Detach the menu afterward so left-clicks go back to toggling the popover
        // instead of always opening this menu.
        statusItem?.menu = nil
    }

    @objc private func randomPhotoFromMenu() {
        Task { await controller.showRandomPhoto() }
    }

    @objc private func wakeFrameFromMenu() {
        Task { await controller.wakeFrame() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
