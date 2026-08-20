import Blooming8Core
import AppKit
import SwiftUI

/// What the frame is showing right now, with the whole-frame actions that
/// aren't tied to one image in the library.
struct CurrentPhotoPane: View {
    @ObservedObject var controller: PhotoController
    @ObservedObject var settings: AppSettings

    @State private var slideshowGallery = ""
    @State private var slideshowMinutes = "5"

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.12))
                    if let image = controller.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 44))
                                .foregroundStyle(.tertiary)
                            Text(settings.deviceIP.isEmpty ? "No frame configured" : "Nothing loaded yet")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 720)
                .frame(height: 380)

                if let path = controller.currentImagePath {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Randomize by")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Randomize by", selection: $settings.randomWeighting) {
                        ForEach(RandomWeighting.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await controller.showRandomPhoto() }
                    } label: {
                        Label("Random Photo", systemImage: "shuffle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isBusy)

                    Button("Redisplay") {
                        Task { await controller.redisplayCurrentPhoto() }
                    }
                    .disabled(controller.isBusy)

                    Button("Show Next") {
                        Task { await controller.showNextImage() }
                    }
                    .disabled(controller.isBusy)

                    Button("Save Photo…") { savePhoto() }
                        .disabled(controller.currentImageData == nil)
                }

                GroupBox("Slideshow") {
                    HStack(spacing: 8) {
                        Picker("Gallery", selection: $slideshowGallery) {
                            ForEach(controller.galleries, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)

                        TextField("min", text: $slideshowMinutes)
                            .frame(width: 52)
                        Text("min").foregroundStyle(.secondary)

                        Button("Start") {
                            let minutes = Int(slideshowMinutes) ?? 5
                            Task { await controller.startSlideshow(gallery: slideshowGallery, durationSeconds: minutes * 60) }
                        }
                        .disabled(slideshowGallery.isEmpty)

                        Button("Stop") {
                            Task { await controller.stopSlideshow() }
                        }
                    }
                    .padding(6)
                }
                .frame(maxWidth: 720)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: controller.galleries) { names in
            if slideshowGallery.isEmpty { slideshowGallery = names.first ?? "" }
        }
    }

    private func savePhoto() {
        guard let data = controller.currentImageData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (controller.currentImagePath as NSString?)?.lastPathComponent ?? "photo.jpg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}

/// The generated content sources, with the same checkbox model as the widget.
struct GeneratedPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick which sources the frame can generate from. With more than one checked, Random picks between them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(ContentSources.all, id: \.id) { source in
                    Toggle(source.displayName, isOn: Binding(
                        get: { settings.selectedContentSources.contains(source.id) },
                        set: { on in
                            if on { settings.selectedContentSources.insert(source.id) }
                            else { settings.selectedContentSources.remove(source.id) }
                        }
                    ))
                }

                Button {
                    Task { await controller.showRandomGeneratedContent() }
                } label: {
                    Label("Generate & Display", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.selectedContentSources.isEmpty || controller.isBusy)
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
