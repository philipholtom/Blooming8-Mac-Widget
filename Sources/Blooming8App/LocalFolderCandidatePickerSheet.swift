import Blooming8Core
import AppKit
import SwiftUI

/// Shows 3 random photos from Local Folder to pick from, with Next for 3
/// more, before anything is actually sent — the same "look at a few before
/// committing" pattern the menu bar widget's own Local Folder preview
/// already uses, and the same shape as `ContentSourcePickerSheet` for
/// generated content. The windowed app's "Random from Local Folder" button
/// used to send immediately with no picker step; this restores parity with
/// the widget.
struct LocalFolderCandidatePickerSheet: View {
    /// Which pool of local photos the 3 candidates are drawn from — the
    /// picking/confirming flow itself is identical either way.
    enum Source {
        case localFolder
        case favorites

        var title: String {
            switch self {
            case .localFolder: return "Random from Local Folder"
            case .favorites: return "Random from Favourites"
            }
        }
    }

    @ObservedObject var controller: PhotoController
    var source: Source = .localFolder
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case picking
        case confirming
    }

    @State private var stage: Stage = .picking
    @State private var isFetching = true
    @State private var isRefreshing = false
    @State private var isSending = false
    @State private var selected: PhotoController.LocalFolderCandidate?
    @State private var fetchError: String?
    @State private var showCrop = false
    /// The crop last applied to `selected`, so reopening the crop window
    /// starts from it rather than from the centre.
    @State private var appliedCrop: CropRegion?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(source.title)
                    .font(.headline)
                Spacer()
                if stage == .picking, !isFetching, !controller.localFolderCandidates.isEmpty {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Next", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
                Button("Cancel") { dismiss() }
                    .disabled(isSending)
            }

            content
        }
        .padding(20)
        .frame(width: 720, height: 560)
        .task { await refresh() }
        .onDisappear {
            // Only relevant if dismissed mid-confirm without sending — a
            // completed send already clears this itself.
            controller.cancelLocalFolderCandidate()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .picking: pickingContent
        case .confirming: confirmingContent
        }
    }

    @ViewBuilder
    private var pickingContent: some View {
        if isFetching {
            VStack(spacing: 10) {
                ProgressView()
                Text("Picking random photos…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let fetchError, controller.localFolderCandidates.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text(fetchError)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Pick one to send, or Next for 3 more")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(Array(controller.localFolderCandidates.enumerated()), id: \.offset) { _, candidate in
                    // Plain .onTapGesture, not Button — the same fix already
                    // established for this project's other candidate grids
                    // (see ContentSourcePickerSheet/VideoFramePickerSheet),
                    // where Button showed intermittent missed clicks.
                    Image(nsImage: candidate.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selected = candidate
                            appliedCrop = nil
                            stage = .confirming
                        }
                }
            }
            .opacity(isRefreshing ? 0.5 : 1)
            .allowsHitTesting(!isRefreshing)
            .overlay {
                if isRefreshing {
                    ProgressView("Getting new options…")
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var confirmingContent: some View {
        VStack(spacing: 14) {
            if let selected {
                Image(nsImage: selected.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !controller.statusText.isEmpty {
                Text(controller.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Back to Options") {
                    stage = .picking
                }
                .disabled(isSending)

                if let selected, controller.canCrop(selected) {
                    Button("Crop…") { showCrop = true }
                        .disabled(isSending)
                }

                Spacer()

                Button {
                    confirmSend()
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send to Frame")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || selected == nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCrop) {
            if let selected {
                CropSheet(
                    imageURL: selected.fileURL,
                    canvasAspect: Double(controller.settings.renderWidth) / Double(controller.settings.renderHeight),
                    initial: appliedCrop ?? .centered
                ) { region in
                    if let updated = controller.cropped(selected, crop: region) {
                        self.selected = updated
                        appliedCrop = region
                    }
                }
            }
        }
    }

    private func refresh() async {
        // First load shows the full-screen spinner; a "Next" re-fetch keeps
        // the current set dimmed underneath instead, so it doesn't flash to
        // empty while new ones come in.
        isFetching = controller.localFolderCandidates.isEmpty
        isRefreshing = !isFetching
        fetchError = nil
        // prepareLocalFolderCandidate dispatches its work to a background
        // Task and publishes the result asynchronously rather than being
        // itself async — poll briefly for it to land, the same workaround
        // LibraryGrid.send already uses for this same method.
        switch source {
        case .localFolder: controller.prepareLocalFolderCandidate()
        case .favorites: controller.prepareFavoritesCandidate()
        }
        let deadline = Date().addingTimeInterval(15)
        while controller.localFolderCandidates.isEmpty && Date() < deadline {
            if !controller.statusText.isEmpty { break } // an error status landed
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if controller.localFolderCandidates.isEmpty {
            fetchError = controller.statusText.isEmpty
                ? "Couldn't find any photos."
                : controller.statusText
        }
        isFetching = false
        isRefreshing = false
    }

    private func confirmSend() {
        guard let selected else { return }
        isSending = true
        Task {
            await controller.confirmLocalFolderCandidate(selected)
            isSending = false
            if controller.statusText.contains("✓") {
                controller.cancelLocalFolderCandidate()
                dismiss()
            }
            // On failure the status line above already explains why — leave
            // the sheet open on the same option so Send can be retried.
        }
    }
}
