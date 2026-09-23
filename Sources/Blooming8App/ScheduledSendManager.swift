import Blooming8Core
import Combine
import Foundation

/// Owns the clock-driven trigger for `AppSettings.scheduledSend`,
/// deliberately living in the windowed App target rather than
/// `PhotoController` (Core) — unlike the existing auto-random photo, which
/// both the Widget and the App happily run independently of each other, a
/// scheduled send should only ever fire once. The windowed app is the
/// process meant to own that responsibility, so this timer only runs here.
@MainActor
final class ScheduledSendManager: ObservableObject {
    private let controller: PhotoController
    private let settings: AppSettings
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    /// When the schedule will next fire, for display in Settings — nil if
    /// disabled, incomplete (no photo/days chosen), or no future date could
    /// be computed.
    @Published private(set) var nextFireDate: Date?

    init(controller: PhotoController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
        // Combine's sink fires once immediately with the current value, so
        // the schedule is live from launch without a separate initial call.
        //
        // `scheduledSend` is now a computed proxy into the active frame
        // profile (see `AppSettings`), not its own `@Published` property, so
        // this subscribes to `$frameProfiles`/`$activeFrameProfileID` — the
        // genuinely `@Published` storage backing it — and pulls
        // `scheduledSend` out of the DELIVERED profiles/activeID rather than
        // re-reading `settings.scheduledSend`. `@Published` publishes from
        // `willSet`, before the property's backing storage is actually
        // updated, so a fresh read here would return the PREVIOUS value —
        // every edit rescheduled against the edit before it, one step
        // behind. That's what produced the originally observed bug: setting
        // the time to 13:45 left the next-fire caption (and the real timer)
        // still targeting 13:44.
        //
        // `.removeDuplicates()`: `frameProfiles` now backs every per-frame
        // setting, not just `scheduledSend` — without this, editing an
        // unrelated favorite or tab would re-trigger `reschedule` too
        // (cheap here, just a Timer, but still pointless churn — see the
        // same pattern's more serious network-flooding version fixed in
        // `PhotoController.init`).
        cancellable = Publishers.CombineLatest(settings.$frameProfiles, settings.$activeFrameProfileID)
            .map { profiles, activeID in profiles.first(where: { $0.id == activeID })?.scheduledSend }
            .removeDuplicates()
            .sink { [weak self] schedule in
                self?.reschedule(with: schedule)
            }
    }

    private func reschedule(with schedule: ScheduledSend?) {
        timer?.invalidate()
        timer = nil
        guard let schedule,
              schedule.isEnabled,
              !schedule.devicePath.isEmpty,
              !schedule.days.isEmpty,
              let fireDate = Self.nextFireDate(for: schedule, after: Date())
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
        guard let schedule = settings.scheduledSend, schedule.isEnabled else { return }
        await controller.fireScheduledSend(schedule)
        // Whether or not the safety-net condition actually let it send this
        // time, move on to the next matching day/time. Safe to re-read
        // `settings.scheduledSend` fresh here — unlike the `.sink` above,
        // this isn't running inside a `willSet` callback.
        reschedule(with: settings.scheduledSend)
    }

    /// The next `Date` at or after `after` that matches one of `schedule`'s
    /// days at its configured time. Checks today first, then up to a full
    /// week ahead, so a single selected day still resolves correctly once
    /// that day's time has already passed this week.
    static func nextFireDate(for schedule: ScheduledSend, after: Date) -> Date? {
        let calendar = Calendar.current
        for offset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: after) else { continue }
            let weekdayRaw = calendar.component(.weekday, from: candidateDay)
            guard let weekday = Weekday(rawValue: weekdayRaw), schedule.days.contains(weekday) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = schedule.timeMinutes / 60
            components.minute = schedule.timeMinutes % 60
            components.second = 0
            guard let candidateFireDate = calendar.date(from: components), candidateFireDate > after else { continue }
            return candidateFireDate
        }
        return nil
    }
}
