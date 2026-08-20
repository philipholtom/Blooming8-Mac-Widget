import Blooming8Core
import SwiftUI
import os

struct Sidebar: View {
    private static let log = Logger(subsystem: "com.pholtom.blooming8app", category: "ui")

    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController
    @Binding var source: LibrarySource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Frame")
                row(.currentPhoto)

                sectionHeader("Library")
                row(.localFolder)
                row(.favorites, badge: settings.favoriteImagePaths.count)
                row(.generated)

                if !visibleGalleries.isEmpty {
                    sectionHeader("Galleries")
                    ForEach(visibleGalleries, id: \.self) { name in
                        row(.gallery(name))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { statusFooter }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
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

    /// A plain tappable row rather than `List(selection:)`. That binding
    /// never fired here — clicking a row produced no selection change and no
    /// log line, on a window confirmed to be real, on-screen, and receiving
    /// other input (it could be resized). Rather than keep chasing whichever
    /// SwiftUI/AppKit interaction is swallowing the selection, this sets
    /// `source` directly from a button's own action closure, which only
    /// depends on ordinary tap-gesture delivery.
    private func row(_ item: LibrarySource, badge: Int? = nil) -> some View {
        let isSelected = source == item
        return Button {
            Self.log.notice("row tapped: \(item.title, privacy: .public)")
            source = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .frame(width: 18)
                Text(item.title)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
