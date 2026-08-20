import Blooming8Core
import SwiftUI

/// Shown as the detail pane for Local Folder or Favorites when the shared
/// local-photos password is set and hasn't been entered this session —
/// mirrors LockedGalleryPrompt. One password/unlock covers both sources
/// (see PhotoController.isLocalFolderUnlocked); which one you unlocked from
/// doesn't matter.
struct LockedLocalFolderPrompt: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: PhotoController

    @State private var passwordDraft = ""
    @State private var showError = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Local photos are locked")
                .font(.headline)

            SecureField("Password", text: $passwordDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(attemptUnlock)

            if showError {
                Text("Incorrect password.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Unlock") { attemptUnlock() }
                .buttonStyle(.borderedProminent)
                .disabled(passwordDraft.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func attemptUnlock() {
        guard let hash = settings.localFolderPasswordHash,
              PasswordHasher.hash(passwordDraft) == hash
        else {
            showError = true
            return
        }
        showError = false
        passwordDraft = ""
        controller.isLocalFolderUnlocked = true
    }
}
