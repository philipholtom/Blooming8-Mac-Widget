import Blooming8Core
import AppKit
import SwiftUI

/// Lists and shows the frame's on-device diagnostic logs (`GET /log/list` +
/// `GET /log/{filename}`) — useful when something fails silently on the
/// device side (a stuck upload, a wake that didn't take) and the app's own
/// status text isn't enough to tell why.
struct DeviceLogsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let client = BloominClient()

    @State private var filenames: [String] = []
    @State private var selectedFilename: String?
    @State private var logContent = ""
    @State private var isLoadingList = false
    @State private var isLoadingContent = false
    @State private var listError: String?
    @State private var contentError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Device Logs")
                    .font(.title2.bold())
                Spacer()
                if isLoadingList {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await loadList() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoadingList)
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            HSplitView {
                fileList
                    .frame(minWidth: 170, idealWidth: 190, maxWidth: 260, maxHeight: .infinity)
                logView
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .task { await loadList() }
    }

    // MARK: - File list

    /// Plain tappable rows rather than `List(selection:)`, matching
    /// Sidebar's own row style — kept consistent with the rest of the app
    /// rather than reaching for a control this codebase otherwise avoids.
    @ViewBuilder
    private var fileList: some View {
        if let listError, filenames.isEmpty {
            message(listError, symbol: "exclamationmark.triangle")
        } else if filenames.isEmpty, !isLoadingList {
            message("No log files found on the frame.", symbol: "doc.text")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filenames, id: \.self) { name in
                        fileRow(name)
                    }
                }
                .padding(8)
            }
        }
    }

    private func fileRow(_ name: String) -> some View {
        let isSelected = selectedFilename == name
        return Button {
            selectedFilename = name
            Task { await loadContent(name) }
        } label: {
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log content

    @ViewBuilder
    private var logView: some View {
        if isLoadingContent {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let contentError {
            message(contentError, symbol: "exclamationmark.triangle")
        } else if selectedFilename == nil {
            message("Select a log file to view it.", symbol: "doc.text.magnifyingglass")
        } else {
            ScrollView {
                Text(logContent)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if let selectedFilename {
                        Text(selectedFilename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save to File…") { saveCurrentLog() }
                        .disabled(logContent.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func loadList() async {
        isLoadingList = true
        listError = nil
        defer { isLoadingList = false }
        do {
            let names = try await client.fetchLogList(ip: settings.deviceIP)
            // Filenames are `YYYY-MM-DD.log`, so a plain reverse-lexical sort
            // puts the newest (most likely to be relevant) first.
            filenames = names.sorted(by: >)
            if selectedFilename == nil, let first = filenames.first {
                selectedFilename = first
                await loadContent(first)
            }
        } catch {
            listError = "Couldn't list logs: \(error.localizedDescription)"
        }
    }

    private func loadContent(_ filename: String) async {
        isLoadingContent = true
        contentError = nil
        defer { isLoadingContent = false }
        do {
            logContent = try await client.fetchLogContent(ip: settings.deviceIP, filename: filename)
        } catch {
            contentError = "Couldn't load '\(filename)': \(error.localizedDescription)"
        }
    }

    private func saveCurrentLog() {
        guard let filename = selectedFilename else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? logContent.write(to: url, atomically: true, encoding: .utf8)
    }
}
