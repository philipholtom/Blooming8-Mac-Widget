import Blooming8Core
import Combine
import Foundation

/// The clock-driven trigger for `AppSettings.scheduledContent` — a generated
/// picture (e.g. today's NASA Photo of the Day) shown at a set time on chosen
/// days. Lives in the windowed app only, for the same reason as
/// `ScheduledSendManager`: a schedule should fire once, not once per process.
/// If the Mac is asleep at the set time, the timer fires when it wakes.
@MainActor
final class ScheduledContentManager: ObservableObject {
    private let controller: PhotoController
    private let settings: AppSettings
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    /// When it will next fire, for display in Settings — nil if disabled or
    /// incomplete.
    @Published private(set) var nextFireDate: Date?

    init(controller: PhotoController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
        // Pulled out of the DELIVERED profiles rather than re-read from
        // `settings.scheduledContent`, and de-duplicated — see the long
        // comment in `ScheduledSendManager.init` for why on both counts.
        cancellable = Publishers.CombineLatest(settings.$frameProfiles, settings.$activeFrameProfileID)
            .map { profiles, activeID in profiles.first(where: { $0.id == activeID })?.scheduledContent }
            .removeDuplicates()
            .sink { [weak self] schedule in
                self?.reschedule(with: schedule)
            }
    }

    private func reschedule(with schedule: ScheduledContent?) {
        timer?.invalidate()
        timer = nil
        guard let schedule,
              schedule.isEnabled,
              !schedule.days.isEmpty,
              let fireDate = ScheduledSendManager.nextFireDate(days: schedule.days, timeMinutes: schedule.timeMinutes, after: Date())
        else {
            nextFireDate = nil
            return
        }
        nextFireDate = fireDate
        timer = Timer.scheduledTimer(withTimeInterval: fireDate.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fire()
            }
        }
    }

    private func fire() async {
        guard let schedule = settings.scheduledContent, schedule.isEnabled else { return }
        await controller.fireScheduledContent(schedule)
        reschedule(with: settings.scheduledContent)
    }
}
