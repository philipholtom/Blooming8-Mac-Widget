import Blooming8Core
import AppKit
import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController
    @Environment(\.dismiss) private var dismiss

    @State private var ipDraft = ""
    @State private var bleNameDraft = ""
    @State private var nasaKeyDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section("Frame") {
                    TextField("IP address", text: $ipDraft, prompt: Text("192.168.1.42"))
                    TextField("Bluetooth name", text: $bleNameDraft, prompt: Text("Office"))
                    Text("The Bluetooth name is used to wake the frame when it's asleep and stops answering over Wi-Fi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Photos") {
                    Toggle("Crop landscape photos to fill the frame", isOn: $settings.cropLandscapePhotos)
                    Text("Off: a landscape photo shows in full, with black bars above and below. On: it's cropped and centered to fill the whole screen instead. Portrait photos aren't affected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Local Folder") {
                    HStack {
                        Text(settings.randomFolderPath.isEmpty ? "No folder chosen" : settings.randomFolderPath)
                            .font(.caption)
                            .foregroundStyle(settings.randomFolderPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") {
                            if let folder = FilePicker.chooseFolder(title: "Choose a Folder of Photos") {
                                settings.randomFolderPath = folder.path
                            }
                        }
                    }
                }

                Section("Generated Content") {
                    TextField("NASA API key", text: $nasaKeyDraft, prompt: Text("DEMO_KEY"))
                    Text("Used for Photo of the Day. The public demo key is rate-limited.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(ipDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 470)
        .onAppear {
            ipDraft = settings.deviceIP
            bleNameDraft = settings.bleDeviceName
            nasaKeyDraft = settings.nasaApiKey
        }
    }

    private func save() {
        settings.deviceIP = ipDraft.trimmingCharacters(in: .whitespaces)
        settings.bleDeviceName = bleNameDraft.trimmingCharacters(in: .whitespaces)
        let key = nasaKeyDraft.trimmingCharacters(in: .whitespaces)
        settings.nasaApiKey = key.isEmpty ? "DEMO_KEY" : key
        dismiss()
        Task {
            await controller.refreshCurrentPhoto()
            await controller.loadGalleries()
        }
    }
}
