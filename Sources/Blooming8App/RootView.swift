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
    @State private var showDeleteGalleryConfirm = false

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
                // The unstyled default here is NSColor.windowBackgroundColor
                // — deliberately a soft grey "chrome" tone, not meant to be
                // content itself. textBackgroundColor is the semantic match
                // for an actual content/document pane (what NSTextView,
                // Mail's message body, etc. use): near-white in light mode,
                // and — unlike a literal .white — still correct if the
                // system is ever in Dark Mode. Sidebar is left as the system
                // default; a grey sidebar next to a white content pane is
                // the standard Finder/Mail/Photos convention, not the thing
                // that reads as "grey" here.
                .background(Color(nsColor: .textBackgroundColor))
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
            // Re-lock on the way out, matching the widget: leaving Local
            // Folder, Favorites, or Apple Photos means the next visit
            // re-prompts, rather than staying unlocked for the rest of the
            // session just because one of them was entered once.
            if !isLocalFolderSource(resolved) {
                controller.isLocalFolderUnlocked = false
            }
            library.load(resolved)
        }
        .onChange(of: settings.favoriteImagePaths) { _ in
            if activeSource == .favorites { library.load(.favorites) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings, controller: controller)
        }
        .alert("Delete '\(activeGalleryName ?? "")'?", isPresented: $showDeleteGalleryConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let name = activeGalleryName else { return }
                Task {
                    await controller.deleteGalleryOnDevice(name)
                    // The gallery being viewed no longer exists — fall back
                    // to the frame pane rather than showing an empty grid.
                    source = nil
                }
            }
        } message: {
            Text("This removes the gallery and every photo in it from the frame. This can't be undone.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if case .gallery(let name) = activeSource, let lockedTab = lockedGalleryTab(name) {
            LockedGalleryPrompt(tab: lockedTab, controller: controller, settings: settings)
        } else if isLocalFolderSource, settings.localFolderLocked, !controller.isLocalFolderUnlocked {
            LockedLocalFolderPrompt(settings: settings, controller: controller)
        } else {
            detailForUnlockedSource
        }
    }

    /// Personal-photo sources gated behind the same Local Folder & Favorites
    /// password/Touch ID lock — Apple Photos is personal content too, so it
    /// shares the lock rather than needing its own.
    private func isLocalFolderSource(_ source: LibrarySource) -> Bool {
        source == .localFolder || source == .favorites || source == .applePhotos
    }

    private var isLocalFolderSource: Bool { isLocalFolderSource(activeSource) }

    @ViewBuilder
    private var detailForUnlockedSource: some View {
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

    /// The still-locked tab a gallery belongs to, if `activeSource` is that
    /// gallery and it hasn't been unlocked this session. Checked here rather
    /// than at the sidebar-click site: `unlockedTabIDs` can change (via
    /// `LockedGalleryPrompt`) without `source` itself changing, so the detail
    /// view needs to re-evaluate on every render, not just once per click.
    private func lockedGalleryTab(_ name: String) -> GalleryTab? {
        settings.lockedTab(for: name, unlockedTabIDs: controller.unlockedTabIDs)
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

            if let galleryName = activeGalleryName {
                Menu {
                    Button("Download Gallery…") {
                        guard let folder = FilePicker.chooseFolder() else { return }
                        Task { await controller.downloadGallery(galleryName, to: folder) }
                    }
                    Divider()
                    Button("Delete Gallery…", role: .destructive) {
                        showDeleteGalleryConfirm = true
                    }
                } label: {
                    Label("Gallery Actions", systemImage: "ellipsis.circle")
                }
                .help("Download or delete '\(galleryName)'")
            }

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var activeSource: LibrarySource { source ?? .currentPhoto }

    private var activeGalleryName: String? {
        guard case .gallery(let name) = activeSource, lockedGalleryTab(name) == nil else { return nil }
        return name
    }

    private var isGridSource: Bool {
        switch activeSource {
        case .currentPhoto, .generated: return false
        default: return true
        }
    }
}
