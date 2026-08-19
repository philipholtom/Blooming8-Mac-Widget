import Blooming8Core
import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController
    @StateObject private var library: LibraryModel

    @State private var source: LibrarySource = .currentPhoto
    @State private var showSettings = false
    @State private var thumbnailSize: Double = 150

    init(settings: AppSettings, controller: PhotoController) {
        self.settings = settings
        self.controller = controller
        _library = StateObject(wrappedValue: LibraryModel(settings: settings, controller: controller))
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(settings: settings, controller: controller, source: $source)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
                .toolbar { toolbarContent }
        }
        .navigationTitle(source.title)
        .task {
            guard !settings.deviceIP.isEmpty else {
                showSettings = true
                return
            }
            await controller.refreshCurrentPhoto()
            await controller.loadGalleries()
        }
        .onChange(of: source) { newValue in
            library.load(newValue)
        }
        .onChange(of: settings.favoriteImagePaths) { _ in
            if case .favorites = source { library.load(source) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, controller: controller)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch source {
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

    private var isGridSource: Bool {
        switch source {
        case .currentPhoto, .generated: return false
        default: return true
        }
    }
}
