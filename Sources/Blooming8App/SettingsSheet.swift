import Blooming8Core
import AppKit
import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController
    @ObservedObject var scheduledSendManager: ScheduledSendManager
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
    @State private var isLookingUpLocation = false
    @State private var locationResults: [GeocodingResult] = []
    @State private var locationLookupError: String?
    @State private var historyHighlightYearDraft = ""

    @State private var newTabName = ""
    @State private var passwordDrafts: [UUID: String] = [:]
    @State private var newLocalFolderPassword = ""
    @State private var showConnectCanvas = false
    @State private var einkshotTokenDraft = ""
    @State private var showScheduledSendPhotoPicker = false
    @State private var thumbnailCacheSizeBytes = 0
    @State private var newFrameProfileName = ""
    @State private var pendingFrameProfileDeletion: FrameProfile?
    @State private var category: SettingsCategory = .frame

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            HStack(spacing: 0) {
                List(SettingsCategory.allCases, selection: Binding<SettingsCategory?>(get: { category }, set: { newValue in if let newValue { category = newValue } })) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .frame(width: 190)

                Divider()

                Form {
                    switch category {
                    case .frame:
                Section("Frame Profiles") {
                    frameProfilesSection
                }
                Section("Frame · \(activeProfileName)") {
                    TextField("IP address", text: $ipDraft, prompt: Text("192.168.1.42"))
                    HStack {
                        TextField("Bluetooth name", text: $bleNameDraft, prompt: Text("Office"))
                        Button("Scan\u{2026}") { showConnectCanvas = true }
                    }
                    Text("The Bluetooth name is used to wake the frame when it stops answering over Wi-Fi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Picker("Orientation", selection: $settings.frameOrientation) {
                            ForEach(FrameOrientation.allCases) { orientation in
                                Text(orientation.label).tag(orientation)
                            }
                        }
                        InfoButton("How this frame is physically mounted. The frame reports the same panel size either way, so this can't be detected — everything sent is composed for this orientation.")
                    }
                }
                    case .device:
                Section("Device · \(activeProfileName)") {
                    deviceSettingsSection
                }
                    case .photos:
                Section("Photos") {
                    HStack {
                        Toggle("Crop landscape photos to fill the frame", isOn: $settings.cropLandscapePhotos)
                        InfoButton("Off: a landscape photo shows in full, with black bars above and below. On: it's cropped and centered to fill the screen. Portrait photos aren't affected.")
                    }

                    HStack {
                        Text("Thumbnail cache")
                        InfoButton("Downloaded gallery thumbnails are kept on disk so revisiting a gallery is fast. Clearing frees the space — nothing is deleted from the frame.")
                        Spacer()
                        Text(thumbnailCacheSizeText)
                            .foregroundStyle(.secondary)
                        Button("Clear") {
                            Task {
                                await DeviceThumbnailStore.shared.clear()
                                refreshThumbnailCacheSize()
                            }
                        }
                        .disabled(thumbnailCacheSizeBytes == 0)
                    }
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
                    case .automation:
                Section("Automatic Random Photo · \(activeProfileName)") {
                    autoRandomSection
                }
                Section("Scheduled Send · \(activeProfileName)") {
                    scheduledSendSection
                }
                    case .galleries:
                Section("Tabs · \(activeProfileName)") {
                    tabsSection
                }
                Section("Local Folder & Favorites Password") {
                    localFolderPasswordSection
                }
                Section("Security") {
                    Toggle("Use Touch ID to unlock", isOn: $settings.useTouchIDForLocks)
                        .disabled(!BiometricAuth.isAvailable())
                    Text(BiometricAuth.isAvailable()
                        ? "Applies to locked gallery tabs and Local Folder/Favorites. Touch ID is tried first; the password still works as a fallback."
                        : "Touch ID isn't available on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    case .online:
                Section("Remote Push") {
                    SecureField("API token", text: $einkshotTokenDraft, prompt: Text(settings.einkshotToken == nil ? "Not set" : "Token is set — enter a new one to replace it"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveEinkshotToken)
                    HStack {
                        Button("Save Token") { saveEinkshotToken() }
                            .disabled(einkshotTokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if settings.einkshotToken != nil {
                            Button("Remove Token", role: .destructive) {
                                settings.einkshotToken = nil
                                einkshotTokenDraft = ""
                            }
                        }
                    }
                    Text("For Send Remotely. Get a token in the Bloomin8 phone app: Devices → device card → ⋮ → API Token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Generated Content") {
                    TextField("NASA API key", text: $nasaKeyDraft, prompt: Text("DEMO_KEY"))
                    Text("Used for Photo of the Day. The public demo key is rate-limited.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Weather location: type a town or city and click Look Up, or edit the coordinates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Weather location name", text: $weatherLocationNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(lookUpLocation)
                        Button {
                            lookUpLocation()
                        } label: {
                            if isLookingUpLocation {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Look Up")
                            }
                        }
                        .disabled(isLookingUpLocation || weatherLocationNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !locationResults.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(locationResults) { result in
                                Button(result.displayLabel) { applyLocation(result) }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    if let locationLookupError {
                        Text(locationLookupError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    DisclosureGroup("Coordinates: \(weatherLatitudeDraft), \(weatherLongitudeDraft)") {
                        HStack {
                            TextField("Latitude", text: $weatherLatitudeDraft)
                                .textFieldStyle(.roundedBorder)
                            TextField("Longitude", text: $weatherLongitudeDraft)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    TextField("History highlight year", text: $historyHighlightYearDraft, prompt: Text("1979"))
                    Text("If today has a historical event from this year, it's always shown first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    case .about:
                Section("About") {
                    aboutSection
                }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 760, idealWidth: 800, minHeight: 500, idealHeight: 640, maxHeight: 800)
        .sheet(isPresented: $showConnectCanvas) {
            ConnectCanvasView { name, ip in
                bleNameDraft = name
                if let ip {
                    ipDraft = ip
                }
            }
        }
        .sheet(isPresented: $showScheduledSendPhotoPicker) {
            ScheduledSendPhotoPickerSheet(settings: settings, controller: controller) { devicePath in
                settings.scheduledSend?.devicePath = devicePath
            }
        }
        // Everything applies as you change it: toggles and pickers write
        // straight to settings, and typed fields are committed when you
        // switch category, press Done, or close the window.
        .onChange(of: category) { _ in commitDrafts() }
        .onDisappear { commitDrafts() }
        .onAppear {
            syncFrameDraftsFromActiveProfile()
            nasaKeyDraft = settings.nasaApiKey
            weatherLocationNameDraft = settings.weatherLocationName
            weatherLatitudeDraft = String(settings.weatherLatitude)
            weatherLongitudeDraft = String(settings.weatherLongitude)
            historyHighlightYearDraft = String(settings.historyHighlightYear)
            refreshThumbnailCacheSize()
        }
    }

    // MARK: - Frame profiles

    @ViewBuilder
    private var frameProfilesSection: some View {
        Text("Each profile has its own IP, orientation, tabs, favorites and schedules. Sections marked with the profile name apply to the active one.")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach(settings.frameProfiles) { profile in
            HStack {
                TextField("Name", text: frameProfileNameBinding(profile.id))
                    .textFieldStyle(.plain)
                if profile.id == settings.activeFrameProfileID {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Switch") { switchToFrameProfile(profile.id) }
                }
                Button(role: .destructive) {
                    pendingFrameProfileDeletion = profile
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(settings.frameProfiles.count <= 1)
                .help(settings.frameProfiles.count <= 1 ? "At least one frame profile is required" : "Delete this profile")
            }
        }

        HStack {
            TextField("New profile name", text: $newFrameProfileName)
            Button("Add Profile") {
                let trimmed = newFrameProfileName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                settings.addFrameProfile(name: trimmed)
                newFrameProfileName = ""
                switchToFrameProfile(settings.activeFrameProfileID)
            }
            .disabled(newFrameProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert(
            "Delete '\(pendingFrameProfileDeletion?.name ?? "")'?",
            isPresented: Binding(get: { pendingFrameProfileDeletion != nil }, set: { if !$0 { pendingFrameProfileDeletion = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingFrameProfileDeletion = nil }
            Button("Delete", role: .destructive) {
                guard let profile = pendingFrameProfileDeletion else { return }
                let wasActive = profile.id == settings.activeFrameProfileID
                settings.deleteFrameProfile(profile.id)
                pendingFrameProfileDeletion = nil
                if wasActive { switchToFrameProfile(settings.activeFrameProfileID) }
            }
        } message: {
            Text("This removes its saved IP address, tabs, favorites, and schedule from this app. It doesn't change anything on the frame itself.")
        }
    }

    private func frameProfileNameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { settings.frameProfiles.first(where: { $0.id == id })?.name ?? "" },
            set: { settings.renameFrameProfile(id, to: $0) }
        )
    }

    /// Switching which profile is active moves every per-frame field
    /// (`deviceIP`, `tabs`, etc.) to point at a different frame — this
    /// sheet's own IP/Bluetooth-name drafts need to catch up immediately, or
    /// hitting Save would write the field you're still looking at onto the
    /// newly-active profile instead of the one it visually still shows.
    /// Also re-fetches the newly active frame's own state (name, galleries)
    /// the same way app launch does, since `controller`'s cached state still
    /// reflects whichever frame was queried last.
    private func switchToFrameProfile(_ id: UUID) {
        settings.activeFrameProfileID = id
        syncFrameDraftsFromActiveProfile()
        Task {
            await controller.refreshCurrentPhoto()
            await controller.loadGalleries()
        }
    }

    private func syncFrameDraftsFromActiveProfile() {
        ipDraft = settings.deviceIP
        bleNameDraft = settings.bleDeviceName
        deviceNameDraft = controller.deviceName ?? ""
        maxIdleMinutesDraft = controller.maxIdleSeconds.map { String($0 / 60) } ?? ""
        sleepDurationHoursDraft = controller.sleepDurationSeconds.map { String($0 / 3600) } ?? ""
        wakeSensitivityDraft = controller.wakeSensitivity.map(String.init) ?? ""
    }

    // MARK: - Device settings (pushed to the frame itself, not just local)

    private var deviceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applied directly to the frame, not just saved locally.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // LabeledContent, not a bare HStack of Text+TextField+Text: a raw
            // multi-element HStack as a direct Form/Section row confused
            // macOS's automatic row-labeling — fields still worked, but
            // rendered without their usual editable-field appearance,
            // making them look like static text. LabeledContent is the
            // Form-native way to pair a label with a control and renders
            // predictably. .roundedBorder on each field is a second,
            // unambiguous "you can type here" cue on top of that.
            LabeledContent("Device name") {
                TextField("", text: $deviceNameDraft)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Auto-sleep after") {
                HStack {
                    TextField("", text: $maxIdleMinutesDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("minutes").foregroundStyle(.secondary).fixedSize()
                }
            }

            LabeledContent("Deep sleep every") {
                HStack {
                    TextField("", text: $sleepDurationHoursDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("hours").foregroundStyle(.secondary).fixedSize()
                }
            }

            LabeledContent("Wake sensitivity") {
                TextField("", text: $wakeSensitivityDraft)
                    .textFieldStyle(.roundedBorder)
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

    // MARK: - Scheduled send

    @ViewBuilder
    private var scheduledSendSection: some View {
        Toggle("Send a specific photo on a schedule", isOn: scheduledSendEnabledBinding)

        if let schedule = settings.scheduledSend, schedule.isEnabled {
            HStack {
                Text(schedule.devicePath.isEmpty ? "No photo chosen" : (schedule.devicePath as NSString).lastPathComponent)
                    .foregroundStyle(schedule.devicePath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose Photo…") {
                    showScheduledSendPhotoPicker = true
                }
            }

            DatePicker("At", selection: scheduledSendTimeBinding, displayedComponents: .hourAndMinute)

            HStack(spacing: 4) {
                Text("Days")
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(Weekday.displayOrder) { day in
                    Toggle(day.shortLabel, isOn: scheduledSendDayBinding(day))
                        .toggleStyle(.button)
                        .font(.caption2)
                }
            }

            Toggle("Only if a hidden gallery photo is currently displayed", isOn: scheduledSendHiddenGalleryBinding)
                .help("Skips sending unless the frame is currently showing a photo from a locked gallery tab, or Local Folder/Favorites while locked — use this to revert the display automatically without interrupting anything you're intentionally showing.")

            if schedule.devicePath.isEmpty {
                Text("Choose a photo above to activate this schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if schedule.days.isEmpty {
                Text("Pick at least one day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let next = scheduledSendManager.nextFireDate {
                Label("Next scheduled send: \(next.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scheduledSendEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.scheduledSend?.isEnabled ?? false },
            set: { on in
                if settings.scheduledSend == nil {
                    settings.scheduledSend = ScheduledSend(isEnabled: on)
                } else {
                    settings.scheduledSend?.isEnabled = on
                }
            }
        )
    }

    private var scheduledSendTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                let minutes = settings.scheduledSend?.timeMinutes ?? 17 * 60
                components.hour = minutes / 60
                components.minute = minutes % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let dc = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.scheduledSend?.timeMinutes = (dc.hour ?? 0) * 60 + (dc.minute ?? 0)
            }
        )
    }

    private var scheduledSendHiddenGalleryBinding: Binding<Bool> {
        Binding(
            get: { settings.scheduledSend?.requireHiddenGalleryDisplayed ?? true },
            set: { settings.scheduledSend?.requireHiddenGalleryDisplayed = $0 }
        )
    }

    private func scheduledSendDayBinding(_ day: Weekday) -> Binding<Bool> {
        Binding(
            get: { settings.scheduledSend?.days.contains(day) ?? false },
            set: { isOn in
                if isOn {
                    settings.scheduledSend?.days.insert(day)
                } else {
                    settings.scheduledSend?.days.remove(day)
                }
            }
        )
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabsSection: some View {
        Text("Tabs group galleries and can require a password. Locked tabs stay hidden in the sidebar until unlocked with ⌘⇧L.")
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
    /// there's a single lock rather than two to manage separately. Apple
    /// Photos deliberately isn't included: the user asked for it to stay
    /// unlocked. Shares storage (settings.localFolderLocked/
    /// localFolderPasswordHash) with the widget's own Local Folder lock, but
    /// unlocking in one app doesn't unlock the other — see
    /// PhotoController.isLocalFolderUnlocked.
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

    private func lookUpLocation() {
        let query = weatherLocationNameDraft.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isLookingUpLocation = true
        locationLookupError = nil
        locationResults = []
        Task {
            defer { isLookingUpLocation = false }
            do {
                let results = try await GeocodingClient.search(name: query)
                if results.isEmpty {
                    locationLookupError = "No matches for '\(query)'."
                } else if results.count == 1 {
                    applyLocation(results[0])
                } else {
                    locationResults = results
                }
            } catch {
                locationLookupError = error.localizedDescription
            }
        }
    }

    private func applyLocation(_ result: GeocodingResult) {
        weatherLocationNameDraft = result.name
        weatherLatitudeDraft = String(result.latitude)
        weatherLongitudeDraft = String(result.longitude)
        locationResults = []
        locationLookupError = nil
    }

    private var thumbnailCacheSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(thumbnailCacheSizeBytes), countStyle: .file)
    }

    private func refreshThumbnailCacheSize() {
        thumbnailCacheSizeBytes = DeviceThumbnailStore.diskCacheSizeBytes()
    }

    private func saveEinkshotToken() {
        let trimmed = einkshotTokenDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        settings.einkshotToken = trimmed
        einkshotTokenDraft = ""
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
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(controller.galleries, id: \.self) { name in
                    Toggle(name, isOn: tabMembershipBinding(tab: tab, gallery: name))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
            }

            passwordEditor(tab: tab)

            Button("Delete Tab", role: .destructive) { deleteTab(tab) }
        } label: {
            Label(tab.name, systemImage: tab.isLocked ? "lock.fill" : "folder")
                .bold()
        }
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
        commitDrafts()
        dismiss()
        Task {
            await controller.refreshCurrentPhoto()
            await controller.loadGalleries()
        }
    }

    private var activeProfileName: String {
        settings.frameProfiles.first(where: { $0.id == settings.activeFrameProfileID })?.name ?? "Frame"
    }

    private var aboutSection: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Group {
            LabeledContent("Version", value: "\(version) (\(build))")
            LabeledContent("Active frame", value: activeProfileName)
            LabeledContent("Frame name", value: controller.deviceName ?? "Not connected")
            LabeledContent("IP address", value: settings.deviceIP.isEmpty ? "Not set" : settings.deviceIP)
            if let battery = controller.batteryPercent {
                LabeledContent("Battery", value: "\(battery)%")
            }
        }
    }

    private func commitDrafts() {
        let ip = ipDraft.trimmingCharacters(in: .whitespaces)
        if !ip.isEmpty { settings.deviceIP = ip }
        settings.bleDeviceName = bleNameDraft.trimmingCharacters(in: .whitespaces)
        let key = nasaKeyDraft.trimmingCharacters(in: .whitespaces)
        settings.nasaApiKey = key.isEmpty ? "DEMO_KEY" : key
        settings.weatherLocationName = weatherLocationNameDraft.trimmingCharacters(in: .whitespaces)
        if let lat = Double(weatherLatitudeDraft) { settings.weatherLatitude = lat }
        if let lon = Double(weatherLongitudeDraft) { settings.weatherLongitude = lon }
        if let year = Int(historyHighlightYearDraft) { settings.historyHighlightYear = year }
    }
}


/// Sidebar groupings for the settings window.
private enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case frame = "Frame"
    case device = "Device"
    case photos = "Photos"
    case automation = "Automation"
    case galleries = "Galleries & Privacy"
    case online = "Online"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .frame: return "display"
        case .device: return "slider.horizontal.3"
        case .photos: return "photo.on.rectangle"
        case .automation: return "clock.arrow.2.circlepath"
        case .galleries: return "lock"
        case .online: return "globe"
        case .about: return "info.circle"
        }
    }
}


/// A small (?) button that shows longer explanatory text in a popover, so
/// settings rows stay one line.
private struct InfoButton: View {
    let text: String
    @State private var shown = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .popover(isPresented: $shown) {
            Text(text)
                .font(.callout)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}
