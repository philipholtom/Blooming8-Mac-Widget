import Blooming8Core
import AppKit
import SwiftUI
import os

struct RootView: View {
    fileprivate static let log = Logger(subsystem: "com.pholtom.blooming8app", category: "ui")

    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController
    @StateObject private var library: LibraryModel

    @State private var source: LibrarySource? = .currentPhoto
    @State private var showSettings = false
    @State private var thumbnailSize: Double = 150

    init(settings: AppSettings, controller: PhotoController) {
        self.settings = settings
        self.controller = controller
        _library = StateObject(wrappedValue: LibraryModel(settings: settings, controller: controller))
    }

    var body: some View {
        // HSplitView, not NavigationSplitView: the sidebar's clicks
        // resolved to the wrong row, consistently and reproducibly, no
        // matter what changed in Sidebar's own view code. Diagnostic
        // logging confirmed clicks at genuinely different screen positions
        // were all being reported at nearly the same coordinate — the input
        // wasn't reaching this code with the right position in the first
        // place. Replacing NavigationSplitView's sidebar column (newer and
        // more complex than the long-stable HSplitView already used for the
        // grid/inspector split below) with HSplitView here resolved it.
        HSplitView {
            Sidebar(settings: settings, controller: controller, source: $source)
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 320)

            detail
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { toolbarContent }
        .navigationTitle(activeSource.title)
        .task {
            guard !settings.deviceIP.isEmpty else {
                showSettings = true
                return
            }
            await controller.refreshCurrentPhoto()
            await controller.loadGalleries()
        }
        .onChange(of: source) { newValue in
            let resolved = newValue ?? .currentPhoto
            Self.log.notice("sidebar: selected \(resolved.title, privacy: .public)")
            library.load(resolved)
        }
        .onChange(of: settings.favoriteImagePaths) { _ in
            if activeSource == .favorites { library.load(.favorites) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, controller: controller)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch activeSource {
        case .currentPhoto:
            CurrentPhotoPane(controller: controller, settings: settings)
        case .generated:
            GeneratedPane(settings: settings, controller: controller)
        default:
            HSplitView {
                LibraryGrid(
                    library: library,
                    settings: settings,
                    controller: controller,
                    thumbnailSize: thumbnailSize
                )
                .frame(minWidth: 420)

                if let item = library.selectedItem {
                    InspectorPane(item: item, settings: settings, controller: controller)
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if controller.isBusy {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await controller.refreshCurrentPhoto() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Re-read what the frame is currently showing")

            Button {
                Task { await controller.wakeFrame() }
            } label: {
                Label("Wake", systemImage: "sun.max")
            }
            .help("Send a Bluetooth wake pulse to the frame")

            if isGridSource {
                Slider(value: $thumbnailSize, in: 90...280) {
                    Text("Thumbnail size")
                }
                .frame(width: 110)
                .help("Thumbnail size")
            }

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var activeSource: LibrarySource { source ?? .currentPhoto }

    private var isGridSource: Bool {
        switch activeSource {
        case .currentPhoto, .generated: return false
        default: return true
        }
    }
}
