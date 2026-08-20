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

    @State private var deviceNameDraft = ""
    @State private var maxIdleMinutesDraft = ""
    @State private var sleepDurationHoursDraft = ""
    @State private var wakeSensitivityDraft = ""

    @State private var weatherLocationNameDraft = ""
    @State private var weatherLatitudeDraft = ""
    @State private var weatherLongitudeDraft = ""
    @State private var historyHighlightYearDraft = ""

    @State private var newTabName = ""
    @State private var passwordDrafts: [UUID: String] = [:]
    @State private var newLocalFolderPassword = ""
    @State private var showConnectCanvas = false

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
                    HStack {
                        TextField("Bluetooth name", text: $bleNameDraft, prompt: Text("Office"))
                        Button("Scan\u{2026}") { showConnectCanvas = true }
                    }
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

                Section("Local Folder & Favorites Password") {
                    localFolderPasswordSection
                }

                Section("Generated Content") {
                    TextField("NASA API key", text: $nasaKeyDraft, prompt: Text("DEMO_KEY"))
                    Text("Used for Photo of the Day. The public demo key is rate-limited.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Weather location name", text: $weatherLocationNameDraft)
                    HStack {
                        TextField("Latitude", text: $weatherLatitudeDraft)
                        TextField("Longitude", text: $weatherLongitudeDraft)
                    }

                    TextField("History highlight year", text: $historyHighlightYearDraft, prompt: Text("1979"))
                    Text("If today has a historical event from this year, it's always shown first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Device") {
                    deviceSettingsSection
                }

                Section("Automatic Random Photo") {
                    autoRandomSection
                }

                Section("Tabs") {
                    tabsSection
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
        .frame(minWidth: 520, idealWidth: 560, minHeight: 470, idealHeight: 640, maxHeight: 800)
        .sheet(isPresented: $showConnectCanvas) {
            ConnectCanvasView { name, ip in
                bleNameDraft = name
                if let ip {
                    ipDraft = ip
                }
            }
        }
        .onAppear {
            ipDraft = settings.deviceIP
            bleNameDraft = settings.bleDeviceName
            nasaKeyDraft = settings.nasaApiKey
            deviceNameDraft = controller.deviceName ?? ""
            maxIdleMinutesDraft = controller.maxIdleSeconds.map { String($0 / 60) } ?? ""
            sleepDurationHoursDraft = controller.sleepDurationSeconds.map { String($0 / 3600) } ?? ""
            wakeSensitivityDraft = controller.wakeSensitivity.map(String.init) ?? ""
            weatherLocationNameDraft = settings.weatherLocationName
            weatherLatitudeDraft = String(settings.weatherLatitude)
            weatherLongitudeDraft = String(settings.weatherLongitude)
            historyHighlightYearDraft = String(settings.historyHighlightYear)
        }
    }

    // MARK: - Device settings (pushed to the frame itself, not just local)

    private var deviceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applied directly to the frame, not just saved locally.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Device name", text: $deviceNameDraft)

            HStack {
                Text("Auto-sleep after")
                TextField("min", text: $maxIdleMinutesDraft)
                    .frame(width: 50)
                Text("min").foregroundStyle(.secondary)
            }

            HStack {
                Text("Deep sleep every")
                TextField("hrs", text: $sleepDurationHoursDraft)
                    .frame(width: 50)
                Text("hours").foregroundStyle(.secondary)
            }

            HStack {
                Text("Wake sensitivity")
                TextField("", text: $wakeSensitivityDraft)
                    .frame(width: 50)
            }

            Button("Update Device Settings") {
                Task {
                    await controller.updateDeviceSettings(
                        name: deviceNameDraft.trimmingCharacters(in: .whitespaces).isEmpty ? nil : deviceNameDraft,
                        sleepDurationSeconds: Int(sleepDurationHoursDraft).map { $0 * 3600 },
                        maxIdleSeconds: Int(maxIdleMinutesDraft).map { $0 * 60 },
                        wakeSensitivity: Int(wakeSensitivityDraft)
                    )
                    deviceNameDraft = controller.deviceName ?? ""
                    maxIdleMinutesDraft = controller.maxIdleSeconds.map { String($0 / 60) } ?? ""
                    sleepDurationHoursDraft = controller.sleepDurationSeconds.map { String($0 / 3600) } ?? ""
                    wakeSensitivityDraft = controller.wakeSensitivity.map(String.init) ?? ""
                }
            }
        }
    }

    // MARK: - Automatic random photo

    @ViewBuilder
    private var autoRandomSection: some View {
        Toggle("Automatically show a random photo", isOn: $settings.autoRandomEnabled)

        if settings.autoRandomEnabled {
            Picker("Frequency", selection: $settings.autoRandomInterval) {
                ForEach(AutoRandomInterval.allCases) { option in
                    Text(option.label).tag(option)
                }
            }

            if settings.autoRandomInterval == .daily {
                DatePicker("At", selection: autoRandomDailyTimeBinding, displayedComponents: .hourAndMinute)
            }
        }
    }

    private var autoRandomDailyTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.autoRandomDailyMinute / 60
                components.minute = settings.autoRandomDailyMinute % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let dc = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.autoRandomDailyMinute = (dc.hour ?? 0) * 60 + (dc.minute ?? 0)
            }
        )
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabsSection: some View {
        Text("Tabs group galleries and can optionally require a password to view. Locking a tab here also hides it from this app's sidebar until unlocked with ⌘⇧L.")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach(settings.tabs) { tab in
            tabEditor(tab: tab)
        }

        HStack {
            TextField("New tab name", text: $newTabName)
            Button("Add Tab") {
                let trimmed = newTabName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                settings.tabs.append(GalleryTab(name: trimmed))
                newTabName = ""
            }
            .disabled(newTabName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Local Folder / Favorites password

    /// One password protects both Local Folder and Favorites in this app —
    /// they're really the same "your private local photos" concern, so
    /// there's a single lock rather than two to manage separately. Shares
    /// storage (settings.localFolderLocked/localFolderPasswordHash) with the
    /// widget's own Local Folder lock, but unlocking in one app doesn't
    /// unlock the other — see PhotoController.isLocalFolderUnlocked.
    @ViewBuilder
    private var localFolderPasswordSection: some View {
        if settings.localFolderLocked {
            Text("Local Folder and Favorites are locked behind this password in this app — unlock either from its lock icon in the sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("New password", text: $newLocalFolderPassword)
            HStack {
                Button("Update Password") { setLocalFolderPassword() }
                    .disabled(newLocalFolderPassword.isEmpty)
                Button("Remove Password", role: .destructive) { removeLocalFolderPassword() }
            }
        } else {
            Text("Set a password to hide Local Folder and Favorites behind a lock icon in the sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Set password", text: $newLocalFolderPassword)
            Button("Set Password") { setLocalFolderPassword() }
                .disabled(newLocalFolderPassword.isEmpty)
        }
    }

    private func setLocalFolderPassword() {
        guard !newLocalFolderPassword.isEmpty else { return }
        settings.localFolderPasswordHash = PasswordHasher.hash(newLocalFolderPassword)
        settings.localFolderLocked = true
        newLocalFolderPassword = ""
        controller.isLocalFolderUnlocked = false // re-lock immediately under the new password
    }

    private func removeLocalFolderPassword() {
        settings.localFolderLocked = false
        settings.localFolderPasswordHash = nil
        controller.isLocalFolderUnlocked = false
    }

    private func tabEditor(tab: GalleryTab) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tab.name).bold()
                Spacer()
                Button(role: .destructive) {
                    deleteTab(tab)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(controller.galleries, id: \.self) { name in
                    Toggle(name, isOn: tabMembershipBinding(tab: tab, gallery: name))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
            }

            passwordEditor(tab: tab)
            Divider()
        }
        .padding(.vertical, 2)
    }

    private func passwordEditor(tab: GalleryTab) -> some View {
        HStack {
            SecureField(tab.isLocked ? "New password" : "Set password", text: passwordDraftBinding(for: tab))
            Button(tab.isLocked ? "Update" : "Lock") { setPassword(for: tab) }
                .disabled((passwordDrafts[tab.id] ?? "").isEmpty)
            if tab.isLocked {
                Button("Unlock") { removePassword(for: tab) }
            }
        }
    }

    private func tabMembershipBinding(tab: GalleryTab, gallery: String) -> Binding<Bool> {
        Binding(
            get: { tab.galleryNames.contains(gallery) },
            set: { isMember in
                guard let index = settings.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                if isMember {
                    settings.tabs[index].galleryNames.insert(gallery)
                } else {
                    settings.tabs[index].galleryNames.remove(gallery)
                }
            }
        )
    }

    private func passwordDraftBinding(for tab: GalleryTab) -> Binding<String> {
        Binding(
            get: { passwordDrafts[tab.id] ?? "" },
            set: { passwordDrafts[tab.id] = $0 }
        )
    }

    private func setPassword(for tab: GalleryTab) {
        guard let index = settings.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let password = passwordDrafts[tab.id] ?? ""
        guard !password.isEmpty else { return }
        settings.tabs[index].passwordHash = PasswordHasher.hash(password)
        passwordDrafts[tab.id] = ""
        controller.unlockedTabIDs.remove(tab.id) // re-lock immediately under the new password
    }

    private func removePassword(for tab: GalleryTab) {
        guard let index = settings.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        settings.tabs[index].passwordHash = nil
        controller.unlockedTabIDs.remove(tab.id)
    }

    private func deleteTab(_ tab: GalleryTab) {
        settings.tabs.removeAll { $0.id == tab.id }
        controller.unlockedTabIDs.remove(tab.id)
    }

    private func save() {
        settings.deviceIP = ipDraft.trimmingCharacters(in: .whitespaces)
        settings.bleDeviceName = bleNameDraft.trimmingCharacters(in: .whitespaces)
        let key = nasaKeyDraft.trimmingCharacters(in: .whitespaces)
        settings.nasaApiKey = key.isEmpty ? "DEMO_KEY" : key
        settings.weatherLocationName = weatherLocationNameDraft.trimmingCharacters(in: .whitespaces)
        if let lat = Double(weatherLatitudeDraft) { settings.weatherLatitude = lat }
        if let lon = Double(weatherLongitudeDraft) { settings.weatherLongitude = lon }
        if let year = Int(historyHighlightYearDraft) { settings.historyHighlightYear = year }
        dismiss()
        Task {
            await controller.refreshCurrentPhoto()
            await controller.loadGalleries()
        }
    }
}
