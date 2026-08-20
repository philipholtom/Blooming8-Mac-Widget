import Blooming8Core
import AppKit
import SwiftUI

/// The "easy" alternative to a full scrubbing player: pulls a handful of
/// frames spread across the video and lets the user click one to send,
/// rather than building timeline/seek UI around video playback.
struct VideoFramePickerSheet: View {
    let videoURL: URL
    @ObservedObject var controller: PhotoController
    @Environment(\.dismiss) private var dismiss

    @State private var frames: [NSImage] = []
    @State private var isExtracting = true
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(videoURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isSending)
            }

            content
        }
        .padding(20)
        .frame(width: 640, height: 500)
        .task {
            frames = await VideoFrameExtractor.extractFrames(from: videoURL, count: 9)
            isExtracting = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if isExtracting {
            VStack(spacing: 10) {
                ProgressView()
                Text("Pulling frames from the video…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if frames.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text("Couldn't read any frames from this file.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Pick a frame to send")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                        Button {
                            send(frame)
                        } label: {
                            Image(nsImage: frame)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 110)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .disabled(isSending)
            .opacity(isSending ? 0.5 : 1)
            .overlay {
                if isSending {
                    ProgressView("Sending…")
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func send(_ frame: NSImage) {
        guard let cgImage = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        isSending = true
        controller.prepareVideoFrame(cgImage: cgImage, sourceURL: videoURL)
        Task {
            guard let candidate = controller.localFolderCandidates.first else {
                isSending = false
                return
            }
            await controller.confirmLocalFolderCandidate(candidate)
            controller.cancelLocalFolderCandidate()
            isSending = false
            dismiss()
        }
    }
}
