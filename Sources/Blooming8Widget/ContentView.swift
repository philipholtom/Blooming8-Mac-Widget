import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var controller: PhotoController

    @State private var showSettings: Bool = false
    @State private var ipDraft: String = ""
    @State private var bleNameDraft: String = ""

    var body: some View {
        VStack(spacing: 12) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.15))
                if let previewImage = controller.previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)

            if let currentImagePath = controller.currentImagePath {
                Text(currentImagePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }

            if let deviceName = controller.deviceName {
                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showSettings {
                settingsForm
            } else {
                controls
            }

            if !controller.statusText.isEmpty {
                Text(controller.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(width: 300)
        .task {
            ipDraft = settings.deviceIP
            bleNameDraft = settings.bleDeviceName
            if !settings.deviceIP.isEmpty {
                await controller.refreshCurrentPhoto()
                await controller.loadGalleries()
            } else {
                showSettings = true
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Blooming8")
                .font(.headline)
            Spacer()
            Button {
                showSettings.toggle()
                if showSettings {
                    ipDraft = settings.deviceIP
                    bleNameDraft = settings.bleDeviceName
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame IP address")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. 192.168.1.42", text: $ipDraft)
                .textFieldStyle(.roundedBorder)

            Text("Bluetooth device name (for waking a sleeping frame)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. Office", text: $bleNameDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { showSettings = false }
                Spacer()
                Button("Save & Connect") {
                    settings.deviceIP = ipDraft
                    settings.bleDeviceName = bleNameDraft
                    showSettings = false
                    Task {
                        await controller.refreshCurrentPhoto()
                        await controller.loadGalleries()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(ipDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if !controller.galleries.isEmpty {
                galleryChecklist
                weightingPicker
            }

            HStack(spacing: 8) {
                Button {
                    Task { await controller.refreshCurrentPhoto() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    Task { await controller.wakeFrame() }
                } label: {
                    Image(systemName: "bolt.fill")
                }
                .help("Send a Bluetooth wake pulse to the frame")

                Button {
                    Task { await controller.showRandomPhoto() }
                } label: {
                    Label("Random Photo", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.selectedGalleries.isEmpty || controller.isBusy)
            }
        }
        .disabled(controller.isBusy)
    }

    private var galleryChecklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Galleries")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(controller.galleries, id: \.self) { name in
                    Toggle(name, isOn: gallerySelectionBinding(for: name))
                        .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weightingPicker: some View {
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
        }
    }

    private func gallerySelectionBinding(for gallery: String) -> Binding<Bool> {
        Binding(
            get: { settings.selectedGalleries.contains(gallery) },
            set: { isOn in
                if isOn {
                    settings.selectedGalleries.insert(gallery)
                } else {
                    settings.selectedGalleries.remove(gallery)
                }
            }
        )
    }
}
