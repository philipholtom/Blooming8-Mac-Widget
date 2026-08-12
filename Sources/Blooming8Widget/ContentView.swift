import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var controller: PhotoController

    @State private var showSettings: Bool = false
    @State private var ipDraft: String = ""
    @State private var bleNameDraft: String = ""
    @State private var nasaApiKeyDraft: String = ""
    @State private var deviceNameDraft: String = ""
    @State private var maxIdleMinutesDraft: String = ""
    @State private var sleepDurationHoursDraft: String = ""
    @State private var wakeSensitivityDraft: String = ""

    @State private var slideshowGallery: String = ""
    @State private var slideshowDurationDraft: String = "5"

    @State private var manageGallery: String = ""
    @State private var newGalleryNameForUpload: String = ""

    @State private var weatherLocationNameDraft: String = ""
    @State private var weatherLatitudeDraft: String = ""
    @State private var weatherLongitudeDraft: String = ""
    @State private var historyHighlightYearDraft: String = ""

    private enum ActiveSelection: Equatable {
        case gallery(UUID?) // nil = the implicit "All" tab
        case generated
        case localFolder
    }

    @State private var activeSelection: ActiveSelection = .gallery(nil)
    @State private var unlockPasswordDraft: String = ""
    @State private var unlockError: Bool = false

    @State private var newTabName: String = ""
    @State private var passwordDrafts: [UUID: String] = [:]
    @State private var selectedLocalFolderIndex: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            revealHiddenTabsShortcut

            header

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.15))
                let previewImage = controller.localFolderCandidates.indices.contains(selectedLocalFolderIndex)
                    ? controller.localFolderCandidates[selectedLocalFolderIndex].image
                    : (controller.localFolderCandidates.first?.image ?? controller.previewImage)
                if let previewImage = previewImage {
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

            if !controller.localFolderCandidates.isEmpty {
                Text("Pick one of 3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onChange(of: controller.localFolderCandidates.count) { _ in
                        selectedLocalFolderIndex = 0
                    }
            } else if let currentImagePath = controller.currentImagePath {
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

            if settings.autoRandomEnabled, let next = controller.nextAutoRandomFireDate {
                Label("Next auto photo: \(next.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !controller.localFolderCandidates.isEmpty {
                localFolderPreviewControls
            } else if showSettings {
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
            populateSettingsDrafts()
            if !settings.deviceIP.isEmpty {
                await controller.refreshCurrentPhoto()
                await controller.loadGalleries()
            } else {
                showSettings = true
            }
            populateSettingsDrafts() // pick up device values fetched above
            if slideshowGallery.isEmpty {
                slideshowGallery = controller.galleries.first ?? ""
            }
            if manageGallery.isEmpty {
                manageGallery = controller.galleries.first ?? ""
            }
        }
        .onChange(of: controller.galleries) { names in
            if slideshowGallery.isEmpty {
                slideshowGallery = names.first ?? ""
            }
            if manageGallery.isEmpty {
                manageGallery = names.first ?? ""
            }
        }
    }

    private func populateSettingsDrafts() {
        ipDraft = settings.deviceIP
        bleNameDraft = settings.bleDeviceName
        nasaApiKeyDraft = settings.nasaApiKey
        deviceNameDraft = controller.deviceName ?? ""
        maxIdleMinutesDraft = controller.maxIdleSeconds.map { String($0 / 60) } ?? ""
        sleepDurationHoursDraft = controller.sleepDurationSeconds.map { String($0 / 3600) } ?? ""
        wakeSensitivityDraft = controller.wakeSensitivity.map(String.init) ?? ""
        weatherLocationNameDraft = settings.weatherLocationName
        weatherLatitudeDraft = String(settings.weatherLatitude)
        weatherLongitudeDraft = String(settings.weatherLongitude)
        historyHighlightYearDraft = String(settings.historyHighlightYear)
    }

    private var header: some View {
        HStack {
            Text("Blooming8")
                .font(.headline)
            Spacer()
            if let isAwake = controller.isDeviceAwake {
                awakeIndicator(isAwake: isAwake)
            }
            if let battery = controller.batteryPercent {
                batteryIndicator(percent: battery)
            }
            Button {
                showSettings.toggle()
                if showSettings {
                    populateSettingsDrafts()
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
    }

    private func awakeIndicator(isAwake: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(isAwake ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(isAwake ? "Awake" : "Asleep")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func batteryIndicator(percent: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: batterySymbolName(for: percent))
            Text("\(percent)%")
        }
        .font(.caption)
        .foregroundStyle(batteryColor(for: percent))
    }

    private func batterySymbolName(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(for percent: Int) -> Color {
        if percent <= 15 { return .red }
        if percent <= 30 { return .orange }
        return .secondary
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

            Text("NASA API key (for Photo of the Day — defaults to the public demo key)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("DEMO_KEY", text: $nasaApiKeyDraft)
                .textFieldStyle(.roundedBorder)

            Divider()

            Group {
                DisclosureGroup("Manage Tabs (\(settings.tabs.count))") {
                    tabManagerView
                }
                DisclosureGroup("Upload / Download Photos") {
                    photoManagementSection
                }
                DisclosureGroup("Automatic Random Photo") {
                    autoRandomSection
                }
                DisclosureGroup("Device Settings") {
                    deviceSettingsSection
                }
                DisclosureGroup("Generated Content Settings") {
                    generatedContentSettingsSection
                }
            }

            Divider()

            HStack {
                Button("Cancel") { showSettings = false }
                Spacer()
                Button("Save & Connect") {
                    settings.deviceIP = ipDraft
                    settings.bleDeviceName = bleNameDraft
                    let trimmedKey = nasaApiKeyDraft.trimmingCharacters(in: .whitespaces)
                    settings.nasaApiKey = trimmedKey.isEmpty ? "DEMO_KEY" : trimmedKey
                    settings.weatherLocationName = weatherLocationNameDraft.trimmingCharacters(in: .whitespaces)
                    if let lat = Double(weatherLatitudeDraft) { settings.weatherLatitude = lat }
                    if let lon = Double(weatherLongitudeDraft) { settings.weatherLongitude = lon }
                    if let year = Int(historyHighlightYearDraft) { settings.historyHighlightYear = year }
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

    // MARK: - Automatic random photo (Settings)

    private var autoRandomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Automatically show a random photo", isOn: $settings.autoRandomEnabled)

            if settings.autoRandomEnabled {
                Picker("Frequency", selection: $settings.autoRandomInterval) {
                    ForEach(AutoRandomInterval.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if settings.autoRandomInterval == .daily {
                    DatePicker("At", selection: autoRandomDailyTimeBinding, displayedComponents: .hourAndMinute)
                }
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
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.autoRandomDailyMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    // MARK: - Device settings (pushed to the frame itself, not just local)

    private var deviceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applied directly to the frame, not just saved locally.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("Device name", text: $deviceNameDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Auto-sleep after")
                    .font(.caption)
                TextField("min", text: $maxIdleMinutesDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Deep sleep every")
                    .font(.caption)
                TextField("hrs", text: $sleepDurationHoursDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Wake sensitivity")
                    .font(.caption)
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
                    populateSettingsDrafts()
                }
            }
        }
    }

    // MARK: - Generated content settings (Weather location, History year)

    private var generatedContentSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Weather location name", text: $weatherLocationNameDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Latitude", text: $weatherLatitudeDraft)
                    .textFieldStyle(.roundedBorder)
                TextField("Longitude", text: $weatherLongitudeDraft)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("History highlight year")
                    .font(.caption)
                TextField("1979", text: $historyHighlightYearDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
            Text("If today has a historical event from this year, it's always shown first.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Upload / download photos (Settings)

    private var photoManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !controller.galleries.isEmpty {
                Picker("Gallery", selection: $manageGallery) {
                    ForEach(controller.galleries, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
            }

            TextField("or type a new gallery name to upload into", text: $newGalleryNameForUpload)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Upload Photos...") {
                    let urls = FilePicker.chooseImages()
                    guard !urls.isEmpty else { return }
                    let trimmedNew = newGalleryNameForUpload.trimmingCharacters(in: .whitespaces)
                    let targetGallery = trimmedNew.isEmpty ? manageGallery : trimmedNew
                    Task {
                        await controller.uploadPhotos(urls: urls, gallery: targetGallery)
                        newGalleryNameForUpload = ""
                    }
                }

                Button("Download Gallery...") {
                    guard !manageGallery.isEmpty, let folder = FilePicker.chooseFolder() else { return }
                    Task { await controller.downloadGallery(manageGallery, to: folder) }
                }
                .disabled(manageGallery.isEmpty)
            }
        }
    }

    // MARK: - Tab management (Settings)

    private var tabManagerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tabs group galleries and can optionally require a password to view.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(settings.tabs) { tab in
                tabEditor(tab: tab)
            }

            HStack {
                TextField("New tab name", text: $newTabName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newTabName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    settings.tabs.append(GalleryTab(name: trimmed))
                    newTabName = ""
                }
                .disabled(newTabName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
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
    }

    private func passwordEditor(tab: GalleryTab) -> some View {
        HStack {
            SecureField(tab.isLocked ? "New password" : "Set password", text: passwordDraftBinding(for: tab))
                .textFieldStyle(.roundedBorder)
            Button(tab.isLocked ? "Update" : "Lock") { setPassword(for: tab) }
                .disabled((passwordDrafts[tab.id] ?? "").isEmpty)
            if tab.isLocked {
                Button("Unlock") { removePassword(for: tab) }
            }
        }
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
        if activeSelection == .gallery(tab.id) { activeSelection = .gallery(nil) }
    }

    // MARK: - Main controls

    private var controls: some View {
        VStack(spacing: 8) {
            galleryChecklist
            if case .gallery = activeSelection {
                weightingPicker
            }

            HStack(spacing: 8) {
                Button {
                    Task { await controller.refreshCurrentPhoto() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }

                Menu {
                    Button("Redisplay Photo") {
                        Task { await controller.redisplayCurrentPhoto() }
                    }
                    Button("Show Next") {
                        Task { await controller.showNextImage() }
                    }
                    Button("Wake Frame") {
                        Task { await controller.wakeFrame() }
                    }
                    Divider()
                    Button("Save Photo...") {
                        savePhoto()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More: redisplay, show next, wake frame, save photo")

                Button {
                    Task {
                        switch activeSelection {
                        case .gallery:
                            await controller.showRandomPhoto()
                        case .generated:
                            await controller.showRandomGeneratedContent()
                        case .localFolder:
                            controller.prepareLocalFolderCandidate()
                        }
                    }
                } label: {
                    Label("Random Photo", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRandomDisabled || controller.isBusy)
            }

            if case .gallery = activeSelection {
                slideshowControls
            }
        }
        .disabled(controller.isBusy)
    }

    private var slideshowControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Slideshow")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("Gallery", selection: $slideshowGallery) {
                    ForEach(controller.galleries, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                TextField("min", text: $slideshowDurationDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Start") {
                    let minutes = Int(slideshowDurationDraft) ?? 5
                    Task { await controller.startSlideshow(gallery: slideshowGallery, durationSeconds: minutes * 60) }
                }
                .disabled(slideshowGallery.isEmpty)
                Button("Stop") {
                    Task { await controller.stopSlideshow() }
                }
            }
        }
    }

    // MARK: - Local folder preview (approve/skip/cancel before anything is sent)

    private var localFolderPreviewControls: some View {
        VStack(spacing: 8) {
            Text("Click to select, then Send")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Array(controller.localFolderCandidates.enumerated()), id: \.offset) { index, candidate in
                    Button {
                        selectedLocalFolderIndex = index
                    } label: {
                        Image(nsImage: candidate.image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 60)
                            .clipped()
                            .cornerRadius(4)
                            .opacity(index == selectedLocalFolderIndex ? 1.0 : 0.6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(index == selectedLocalFolderIndex ? Color.blue : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Cancel") {
                    controller.cancelLocalFolderCandidate()
                }
                .frame(maxWidth: .infinity)

                Button("Next") {
                    controller.prepareLocalFolderCandidate()
                }
                .frame(maxWidth: .infinity)

                Button("Send") {
                    if controller.localFolderCandidates.indices.contains(selectedLocalFolderIndex) {
                        Task { await controller.confirmLocalFolderCandidate(controller.localFolderCandidates[selectedLocalFolderIndex]) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(controller.isBusy)
    }

    private func savePhoto() {
        guard let data = controller.currentImageData else { return }
        let panel = NSSavePanel()
        panel.title = "Save Photo"
        panel.nameFieldStringValue = controller.currentImagePath.map { ($0 as NSString).lastPathComponent } ?? "photo.jpg"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private var isRandomDisabled: Bool {
        switch activeSelection {
        case .gallery:
            return settings.selectedGalleries.intersection(controller.availableGalleryNames).isEmpty
        case .generated:
            return settings.selectedContentSources.isEmpty
        case .localFolder:
            return settings.randomFolderPath.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var galleryChecklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            tabBar

            switch activeSelection {
            case .generated:
                contentSourceChecklist
            case .localFolder:
                localFolderSection
            case .gallery:
                if let tab = activeGalleryTab, tab.isLocked, !controller.unlockedTabIDs.contains(tab.id) {
                    lockedTabPrompt(tab: tab)
                } else {
                    Text("Galleries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(activeTabGalleryNames, id: \.self) { name in
                            Toggle(name, isOn: gallerySelectionBinding(for: name))
                                .toggleStyle(.checkbox)
                        }
                        if activeTabGalleryNames.isEmpty {
                            Text("No galleries in this tab.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Generated content

    private var contentSourceChecklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Generated Content")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ContentSources.all, id: \.id) { source in
                    Toggle(source.displayName, isOn: contentSourceBinding(for: source.id))
                        .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Generates a fresh image and uploads it to that source's own gallery on the frame (e.g. \"NASA\", \"Fortune\").")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func contentSourceBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.selectedContentSources.contains(id) },
            set: { isOn in
                if isOn {
                    settings.selectedContentSources.insert(id)
                } else {
                    settings.selectedContentSources.remove(id)
                }
            }
        )
    }

    // MARK: - Local folder

    private var localFolderSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local Folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(settings.randomFolderPath.isEmpty ? "No folder selected" : settings.randomFolderPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose...") {
                    if let folder = FilePicker.chooseFolder(title: "Choose a Folder of Photos") {
                        settings.randomFolderPath = folder.path
                    }
                }
            }
            HStack {
                Button("Delete Random Gallery", role: .destructive) {
                    Task { await controller.deleteRandomGallery() }
                }
                .font(.caption)
                Spacer()
            }
            Text("When you pick a random photo, you'll see 3 options to choose from.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabChip(name: "All", selection: .gallery(nil), isLocked: false)
                ForEach(settings.tabs.filter { !$0.isLocked || controller.showHiddenTabs }) { tab in
                    tabChip(
                        name: tab.name,
                        selection: .gallery(tab.id),
                        isLocked: tab.isLocked && !controller.unlockedTabIDs.contains(tab.id)
                    )
                }
                tabChip(name: "✨ Generated", selection: .generated, isLocked: false)
                tabChip(name: "📁 Local Folder", selection: .localFolder, isLocked: false)
            }
        }
    }

    /// Invisible — exists purely to register the ⌘⇧L shortcut that reveals
    /// locked tabs in the bar above without a visible control anyone could
    /// stumble onto.
    private var revealHiddenTabsShortcut: some View {
        Button("") {
            controller.showHiddenTabs.toggle()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func tabChip(name: String, selection: ActiveSelection, isLocked: Bool) -> some View {
        Button {
            activeSelection = selection
            unlockPasswordDraft = ""
            unlockError = false
            controller.cancelLocalFolderCandidate()
        } label: {
            HStack(spacing: 4) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                }
                Text(name)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(activeSelection == selection ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func lockedTabPrompt(tab: GalleryTab) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("'\(tab.name)' is locked", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Password", text: $unlockPasswordDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { attemptUnlock(tab, unlockError: $unlockError, unlockPasswordDraft: $unlockPasswordDraft) }
            if unlockError {
                Text("Incorrect password.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Button("Unlock") { attemptUnlock(tab, unlockError: $unlockError, unlockPasswordDraft: $unlockPasswordDraft) }
                .buttonStyle(.borderedProminent)
                .disabled(unlockPasswordDraft.isEmpty)
        }
    }

    private func attemptUnlock(_ tab: GalleryTab, unlockError: Binding<Bool>, unlockPasswordDraft: Binding<String>) {
        if controller.unlock(tab: tab, password: unlockPasswordDraft.wrappedValue) {
            unlockError.wrappedValue = false
            unlockPasswordDraft.wrappedValue = ""
        } else {
            unlockError.wrappedValue = true
        }
    }

    private var activeGalleryTab: GalleryTab? {
        guard case .gallery(let id?) = activeSelection else { return nil }
        return settings.tabs.first(where: { $0.id == id })
    }

    private var ungroupedGalleryNames: [String] {
        let assigned = Set(settings.tabs.flatMap { $0.galleryNames })
        return controller.galleries.filter { !assigned.contains($0) }
    }

    private var activeTabGalleryNames: [String] {
        if let tab = activeGalleryTab {
            return controller.galleries.filter { tab.galleryNames.contains($0) }
        } else {
            return ungroupedGalleryNames
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

    private func tabMembershipBinding(tab: GalleryTab, gallery: String) -> Binding<Bool> {
        Binding(
            get: {
                settings.tabs.first(where: { $0.id == tab.id })?.galleryNames.contains(gallery) ?? false
            },
            set: { isOn in
                guard let index = settings.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                if isOn {
                    settings.tabs[index].galleryNames.insert(gallery)
                } else {
                    settings.tabs[index].galleryNames.remove(gallery)
                }
            }
        )
    }
}

extension ContentView {
    /// When the popover hosting this view closes, hide the hidden tabs again
    /// so a keyboard-revealed state doesn't linger for the next person who
    /// opens the popover. We can't use NSPopover's didClose delegate directly
    /// on a SwiftUI hosted view, so this hook is called from AppDelegate
    /// after detaching the popover's menu.
    func resetHiddenTabVisibility() {
        if controller.showHiddenTabs {
            controller.showHiddenTabs = false
        }
    }
}
