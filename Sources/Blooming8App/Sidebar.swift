import Blooming8Core
import SwiftUI

struct Sidebar: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController
    @Binding var source: LibrarySource

    var body: some View {
        List(selection: $source) {
            Section("Frame") {
                row(.currentPhoto)
            }

            Section("Library") {
                row(.localFolder)
                row(.favorites, badge: settings.favoriteImagePaths.count)
                row(.generated)
            }

            if !visibleGalleries.isEmpty {
                Section("Galleries") {
                    ForEach(visibleGalleries, id: \.self) { name in
                        row(.gallery(name))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { statusFooter }
    }

    /// Galleries assigned to a locked tab stay hidden until that tab is
    /// unlocked, matching the widget's behaviour — otherwise the app would be
    /// a trivial way around the widget's tab passwords.
    private var visibleGalleries: [String] {
        let lockedNames = settings.tabs
            .filter { $0.isLocked && !controller.unlockedTabIDs.contains($0.id) }
            .flatMap(\.galleryNames)
        let hidden = Set(lockedNames)
        return controller.galleries.filter { !hidden.contains($0) }
    }

    @ViewBuilder
    private func row(_ item: LibrarySource, badge: Int? = nil) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
            .badge(badge ?? 0)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(awakeColor)
                    .frame(width: 7, height: 7)
                Text(awakeLabel)
                Spacer()
                if let battery = controller.batteryPercent {
                    Image(systemName: batterySymbol(battery))
                    Text("\(battery)%")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let name = controller.deviceName {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if !controller.statusText.isEmpty {
                Text(controller.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var awakeColor: Color {
        switch controller.isDeviceAwake {
        case .some(true): return .green
        case .some(false): return .secondary
        case nil: return .clear
        }
    }

    private var awakeLabel: String {
        switch controller.isDeviceAwake {
        case .some(true): return "Awake"
        case .some(false): return "Asleep"
        case nil: return "Not connected"
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
