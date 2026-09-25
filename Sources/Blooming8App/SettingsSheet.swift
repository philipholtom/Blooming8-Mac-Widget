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
    @State private var deviceUpdateMessage: String?
    @State private var deviceUpdateFailed = false

    @State private var weatherLocationNameDraft = ""
    @State private var weatherLatitudeDraft = ""
    @State private var weatherLongitudeDraft = ""
    @State private var isLookingUpLocation = false
    @State private var locationResults: [GeocodingResult] = []
    @State private var locationLookupError: String?
    @State private var historyHighlightYearDraft = ""

    @State private var showConnectCanvas = false

    // Privacy panel. `privacyUnlocked` is per-visit: the panel starts locked
    // whenever Settings opens, so locked gallery names are never on screen
    // until the password (or Touch ID) has been given.
    @State private var privacyUnlocked = false
    @State private var unlockPasswordDraft = ""
    @State private var unlockFailed = false
    @State private var newPasswordDraft = ""
    @State private var confirmPasswordDraft = ""
    @State private var currentPasswordDraft = ""
    @State private var privacyMessage: String?
    @State private var einkshotTokenDraft = ""
    @State private var showScheduledSendPhotoPicker = false
    @State private var thumbnailCacheSizeBytes = 0
    @State private var newFrameProfileName = ""
    @State private var pendingFrameProfileDeletion: FrameProfile?
    @AppStorage("settingsSheetCategory") private var category: SettingsCategory = .frames

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
                    case .frames:
                Section("Frame Profiles") {
                    frameProfilesSection
                }
                    case .connection:
                Section("Connection · \(activeProfileName)") {
                    TextField("IP address", text: $ipDraft, prompt: Text("192.168.1.42"))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Bluetooth name", text: $bleNameDraft, prompt: Text("Office"))
                            .textFieldStyle(.roundedBorder)
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
                    HStack {
                        Label(settings.localFolderLocked ? "Locked with a password" : "Not password-protected",
                              systemImage: settings.localFolderLocked ? "lock.fill" : "lock.open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(settings.localFolderLocked ? "Change…" : "Set Password…") { category = .galleries }
                            .font(.caption)
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
                privacySections
                    case .remote:
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
                    case .content:
                Section("Photo of the Day") {
                    TextField("NASA API key", text: $nasaKeyDraft, prompt: Text("Using the shared demo key"))
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 4) {
                        Text("The shared demo key is rate-limited.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Get a free key", destination: URL(string: "https://api.nasa.gov")!)
                            .font(.caption)
                    }
                }
                Section("Weather") {

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

                }
                Section("On This Day") {
                    HStack {
                        TextField("Highlight year", text: $historyHighlightYearDraft, prompt: Text("1979"))
                            .textFieldStyle(.roundedBorder)
                        InfoButton("If today has a historical event from this year, it's always shown first.")
                    }
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
        .frame(minWidth: 760, idealWidth: 800, maxWidth: .infinity, minHeight: 500, idealHeight: 640, maxHeight: .infinity)
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
        .onChange(of: controller.maxIdleSeconds) { _ in
            // The frame answered after the sheet opened (e.g. it just woke):
            // fill the Device fields unless the user is mid-edit.
            if !deviceDraftsChanged { syncDeviceDrafts() }
        }
        .onDisappear { commitDrafts() }
        .onAppear {
            migrateLegacyLocks()
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
                .textFieldStyle(.roundedBorder)
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
        syncDeviceDrafts()
    }

    private func syncDeviceDrafts() {
        deviceNameDraft = controller.deviceName ?? ""
        maxIdleMinutesDraft = controller.maxIdleSeconds.map { String($0 / 60) } ?? ""
        sleepDurationHoursDraft = controller.sleepDurationSeconds.map { String($0 / 3600) } ?? ""
        wakeSensitivityDraft = controller.wakeSensitivity.map(String.init) ?? ""
    }

    // MARK: - Device settings (pushed to the frame itself, not just local)

    private var deviceSettingsSection: some View {
        let asleep = controller.isDeviceAwake == false
        let loaded = controller.maxIdleSeconds != nil
        return VStack(alignment: .leading, spacing: 8) {
            Text("Applied directly to the frame, not just saved locally.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if asleep || !loaded {
                Label(asleep ? "The frame is asleep — wake it (toolbar) to view or change these." : "Not read from the frame yet — press Refresh in the toolbar.",
                      systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // LabeledContent, not a bare HStack of Text+TextField+Text: a raw
            // multi-element HStack as a direct Form/Section row confused
            // macOS's automatic row-labeling — fields still worked, but
            // rendered without their usual editable-field appearance,
            // making them look like static text. LabeledContent is the
            // Form-native way to pair a label with a control and renders
            // predictably. .roundedBorder on each field is a second,
            // unambiguous "you can type here" cue on top of that.
            Group {
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
            }
            .disabled(asleep || !loaded)

            HStack {
                Button("Update Device Settings") {
                    Task {
                        deviceUpdateMessage = nil
                        await controller.updateDeviceSettings(
                            name: deviceNameDraft.trimmingCharacters(in: .whitespaces).isEmpty ? nil : deviceNameDraft,
                            sleepDurationSeconds: Int(sleepDurationHoursDraft).map { $0 * 3600 },
                            maxIdleSeconds: Int(maxIdleMinutesDraft).map { $0 * 60 },
                            wakeSensitivity: Int(wakeSensitivityDraft)
                        )
                        deviceUpdateFailed = controller.statusText.hasPrefix("Couldn't")
                        deviceUpdateMessage = deviceUpdateFailed ? controller.statusText : "Saved to the frame."
                        deviceNameDraft = controller.deviceName ?? ""
                        maxIdleMinutesDraft = controller.maxIdleSeconds.map { String($0 / 60) } ?? ""
                        sleepDurationHoursDraft = controller.sleepDurationSeconds.map { String($0 / 3600) } ?? ""
                        wakeSensitivityDraft = controller.wakeSensitivity.map(String.init) ?? ""
                    }
                }
                .disabled(asleep || !loaded || !deviceDraftsChanged || controller.isBusy)

                if let deviceUpdateMessage {
                    Label(deviceUpdateMessage, systemImage: deviceUpdateFailed ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(deviceUpdateFailed ? Color.red : Color.green)
                }
            }
        }
    }

    /// True when any device field differs from what the frame last reported.
    private var deviceDraftsChanged: Bool {
        deviceNameDraft != (controller.deviceName ?? "")
            || maxIdleMinutesDraft != (controller.maxIdleSeconds.map { String($0 / 60) } ?? "")
            || sleepDurationHoursDraft != (controller.sleepDurationSeconds.map { String($0 / 3600) } ?? "")
            || wakeSensitivityDraft != (controller.wakeSensitivity.map(String.init) ?? "")
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

    // MARK: - Privacy (one lock password, plus which galleries it hides)

    /// The single tab that holds every locked gallery. Locked galleries are
    /// stored as one managed tab whose password is always the same as the
    /// Local Folder/Favorites password, so the rest of the app's locking
    /// logic (sidebar hiding, unlock prompts) works unchanged.
    private static let lockedTabID = UUID(uuidString: "6F0B1E2A-5C1D-4B7E-9A31-2D4C8E7F5A10")!

    private var lockedTabIndex: Int? {
        settings.tabs.firstIndex { $0.id == Self.lockedTabID }
    }

    private func setLockedTabHash(_ hash: String?) {
        if let hash {
            if let index = lockedTabIndex {
                settings.tabs[index].passwordHash = hash
            } else {
                settings.tabs.append(GalleryTab(id: Self.lockedTabID, name: "Locked", passwordHash: hash))
            }
        } else {
            settings.tabs.removeAll { $0.id == Self.lockedTabID }
        }
    }

    /// Older versions let each tab have its own password. Fold every locked
    /// tab into the single managed one (galleries merged, password unified
    /// with the Local Folder one) the first time Settings opens.
    private func migrateLegacyLocks() {
        let legacy = settings.tabs.filter { $0.isLocked && $0.id != Self.lockedTabID }
        guard !legacy.isEmpty else { return }
        let hash = settings.localFolderPasswordHash ?? legacy[0].passwordHash
        guard let hash else { return }
        if settings.localFolderPasswordHash == nil {
            settings.localFolderPasswordHash = hash
        }
        settings.localFolderLocked = true
        let merged = legacy.reduce(into: Set<String>()) { $0.formUnion($1.galleryNames) }
        setLockedTabHash(hash)
        if let index = lockedTabIndex {
            settings.tabs[index].galleryNames.formUnion(merged)
        }
        let legacyIDs = Set(legacy.map(\.id))
        settings.tabs.removeAll { legacyIDs.contains($0.id) }
        for id in legacyIDs { controller.unlockedTabIDs.remove(id) }
    }

    private func passwordMatches(_ password: String) -> Bool {
        guard let stored = settings.localFolderPasswordHash else { return false }
        return PasswordHasher.verify(password, against: stored).matched
    }

    private func relockEverything() {
        privacyUnlocked = false
        controller.isLocalFolderUnlocked = false
        controller.unlockedTabIDs.remove(Self.lockedTabID)
    }

    private func markUnlocked() {
        privacyUnlocked = true
        unlockFailed = false
        unlockPasswordDraft = ""
        // Deliberately does NOT unlock the sidebar: proving the password to
        // edit settings shouldn't reveal the locked galleries in the main
        // window.
    }

    private func attemptPrivacyUnlock() {
        if passwordMatches(unlockPasswordDraft) {
            markUnlocked()
        } else {
            unlockFailed = true
        }
    }

    private func attemptPrivacyTouchID() async {
        if await BiometricAuth.authenticate(reason: "manage locked galleries") {
            markUnlocked()
        }
    }

    private func setInitialPassword() {
        guard !newPasswordDraft.isEmpty, newPasswordDraft == confirmPasswordDraft else { return }
        let hash = PasswordHasher.hash(newPasswordDraft)
        settings.localFolderPasswordHash = hash
        settings.localFolderLocked = true
        setLockedTabHash(hash)
        newPasswordDraft = ""
        confirmPasswordDraft = ""
        privacyMessage = nil
        privacyUnlocked = true // you just chose it; no need to type it again
        controller.isLocalFolderUnlocked = false
        controller.unlockedTabIDs.remove(Self.lockedTabID)
    }

    private func changePassword() {
        guard passwordMatches(currentPasswordDraft) else {
            privacyMessage = "Current password is incorrect."
            return
        }
        guard !newPasswordDraft.isEmpty, newPasswordDraft == confirmPasswordDraft else {
            privacyMessage = "New passwords don't match."
            return
        }
        let hash = PasswordHasher.hash(newPasswordDraft)
        settings.localFolderPasswordHash = hash
        setLockedTabHash(hash)
        currentPasswordDraft = ""
        newPasswordDraft = ""
        confirmPasswordDraft = ""
        privacyMessage = "Password changed."
    }

    private func removePassword() {
        guard passwordMatches(currentPasswordDraft) else {
            privacyMessage = "Enter your current password to remove the lock."
            return
        }
        settings.localFolderLocked = false
        settings.localFolderPasswordHash = nil
        setLockedTabHash(nil)
        controller.isLocalFolderUnlocked = false
        controller.unlockedTabIDs.remove(Self.lockedTabID)
        currentPasswordDraft = ""
        newPasswordDraft = ""
        confirmPasswordDraft = ""
        privacyMessage = nil
        privacyUnlocked = false
    }

    private func lockedGalleryBinding(_ gallery: String) -> Binding<Bool> {
        Binding(
            get: { lockedTabIndex.map { settings.tabs[$0].galleryNames.contains(gallery) } ?? false },
            set: { isLocked in
                guard let index = lockedTabIndex else { return }
                if isLocked {
                    settings.tabs[index].galleryNames.insert(gallery)
                } else {
                    settings.tabs[index].galleryNames.remove(gallery)
                }
            }
        )
    }

    @ViewBuilder
    private var privacySections: some View {
        if !settings.localFolderLocked {
            Section("Lock Password") {
                Text("Set one password to hide chosen galleries, Local Folder and Favorites behind a lock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("New password", text: $newPasswordDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: $confirmPasswordDraft)
                    .textFieldStyle(.roundedBorder)
                if !confirmPasswordDraft.isEmpty && newPasswordDraft != confirmPasswordDraft {
                    Text("Passwords don't match.").font(.caption).foregroundStyle(.red)
                }
                Button("Set Password") { setInitialPassword() }
                    .disabled(newPasswordDraft.isEmpty || newPasswordDraft != confirmPasswordDraft)
            }
        } else if !privacyUnlocked {
            Section("Locked") {
                Text("Enter your password to see or change what's locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.useTouchIDForLocks && BiometricAuth.isAvailable() {
                    Button {
                        Task { await attemptPrivacyTouchID() }
                    } label: {
                        Label("Unlock with Touch ID", systemImage: "touchid")
                    }
                }
                SecureField("Password", text: $unlockPasswordDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(attemptPrivacyUnlock)
                if unlockFailed {
                    Text("Incorrect password.").font(.caption).foregroundStyle(.red)
                }
                Button("Unlock") { attemptPrivacyUnlock() }
                    .disabled(unlockPasswordDraft.isEmpty)
            }
        } else {
            Section("Locked Galleries · \(activeProfileName)") {
                Text("Ticked galleries are hidden in the sidebar until you unlock them (⌘⇧L, then your password). Local Folder and Favorites are always locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if controller.galleries.isEmpty {
                    Text("No galleries loaded yet — wake the frame and press Refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.galleries, id: \.self) { name in
                    Toggle(name, isOn: lockedGalleryBinding(name))
                        .toggleStyle(.checkbox)
                }
                Button("Lock Now") { relockEverything() }
            }

            Section("Change or Remove Password") {
                SecureField("Current password", text: $currentPasswordDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("New password", text: $newPasswordDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm new password", text: $confirmPasswordDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Change Password") { changePassword() }
                        .disabled(currentPasswordDraft.isEmpty || newPasswordDraft.isEmpty)
                    Button("Remove Password", role: .destructive) { removePassword() }
                        .disabled(currentPasswordDraft.isEmpty)
                }
                if let privacyMessage {
                    Text(privacyMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        Section("Touch ID") {
            Toggle("Use Touch ID to unlock", isOn: $settings.useTouchIDForLocks)
                .disabled(!BiometricAuth.isAvailable())
            Text(BiometricAuth.isAvailable()
                ? "Touch ID is tried first; the password still works as a fallback."
                : "Touch ID isn't available on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    case frames = "Frames"
    case connection = "Connection"
    case device = "Device"
    case photos = "Photos"
    case automation = "Automation"
    case galleries = "Privacy"
    case remote = "Remote Push"
    case content = "Content"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .frames: return "photo.on.rectangle.angled"
        case .connection: return "wifi"
        case .device: return "slider.horizontal.3"
        case .photos: return "photo.on.rectangle"
        case .automation: return "clock.arrow.2.circlepath"
        case .galleries: return "lock"
        case .remote: return "paperplane"
        case .content: return "sparkles"
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
