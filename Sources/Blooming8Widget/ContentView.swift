import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var controller: PhotoController

    @State private var showSettings: Bool = false
    @State private var ipDraft: String = ""
    @State private var bleNameDraft: String = ""
    @State private var nasaApiKeyDraft: String = ""

    private enum ActiveSelection: Equatable {
        case gallery(UUID?) // nil = the implicit "All" tab
        case generated
    }

    @State private var activeSelection: ActiveSelection = .gallery(nil)
    @State private var unlockPasswordDraft: String = ""
    @State private var unlockError: Bool = false

    @State private var showTabManager: Bool = false
    @State private var newTabName: String = ""
    @State private var passwordDrafts: [UUID: String] = [:]

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

            if settings.autoRandomEnabled, let next = controller.nextAutoRandomFireDate {
                Label("Next auto photo: \(next.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                    .font(.caption2)
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
            nasaApiKeyDraft = settings.nasaApiKey
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
            if let battery = controller.batteryPercent {
                batteryIndicator(percent: battery)
            }
            Button {
                showSettings.toggle()
                if showSettings {
                    ipDraft = settings.deviceIP
                    bleNameDraft = settings.bleDeviceName
                    nasaApiKeyDraft = settings.nasaApiKey
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
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

            if showTabManager {
                tabManagerView
            } else {
                Button("Manage Tabs (\(settings.tabs.count))...") { showTabManager = true }
            }

            Divider()

            autoRandomSection

            Divider()

            HStack {
                Button("Cancel") { showSettings = false }
                Spacer()
                Button("Save & Connect") {
                    settings.deviceIP = ipDraft
                    settings.bleDeviceName = bleNameDraft
                    let trimmedKey = nasaApiKeyDraft.trimmingCharacters(in: .whitespaces)
                    settings.nasaApiKey = trimmedKey.isEmpty ? "DEMO_KEY" : trimmedKey
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

            Button("Done") { showTabManager = false }
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

                Button {
                    Task { await controller.wakeFrame() }
                } label: {
                    Image(systemName: "bolt.fill")
                }
                .help("Send a Bluetooth wake pulse to the frame")

                Button {
                    Task {
                        switch activeSelection {
                        case .gallery:
                            await controller.showRandomPhoto()
                        case .generated:
                            await controller.showRandomGeneratedContent()
                        }
                    }
                } label: {
                    Label("Random Photo", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRandomDisabled || controller.isBusy)
            }
        }
        .disabled(controller.isBusy)
    }

    private var isRandomDisabled: Bool {
        switch activeSelection {
        case .gallery:
            return settings.selectedGalleries.intersection(controller.availableGalleryNames).isEmpty
        case .generated:
            return settings.selectedContentSources.isEmpty
        }
    }

    private var galleryChecklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            tabBar

            switch activeSelection {
            case .generated:
                contentSourceChecklist
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
            Text("Generates a fresh image and uploads it to the frame's \"Generated\" gallery.")
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

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabChip(name: "All", selection: .gallery(nil), isLocked: false)
                ForEach(settings.tabs) { tab in
                    tabChip(
                        name: tab.name,
                        selection: .gallery(tab.id),
                        isLocked: tab.isLocked && !controller.unlockedTabIDs.contains(tab.id)
                    )
                }
                tabChip(name: "✨ Generated", selection: .generated, isLocked: false)
            }
        }
    }

    private func tabChip(name: String, selection: ActiveSelection, isLocked: Bool) -> some View {
        Button {
            activeSelection = selection
            unlockPasswordDraft = ""
            unlockError = false
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
                .onSubmit { attemptUnlock(tab) }
            if unlockError {
                Text("Incorrect password.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Button("Unlock") { attemptUnlock(tab) }
                .buttonStyle(.borderedProminent)
                .disabled(unlockPasswordDraft.isEmpty)
        }
    }

    private func attemptUnlock(_ tab: GalleryTab) {
        if controller.unlock(tab: tab, password: unlockPasswordDraft) {
            unlockError = false
            unlockPasswordDraft = ""
        } else {
            unlockError = true
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
