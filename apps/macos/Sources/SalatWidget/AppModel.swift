import AppKit
import SalatCore
import Observation
import OSLog

/// How the countdown is rendered in the menu bar.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case nameAndCountdown
    case countdown
    case nameAndTime
    case iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAndCountdown: "Prayer and time left"
        case .countdown: "Time left only"
        case .nameAndTime: "Prayer and time"
        case .iconOnly: "Icon only"
        }
    }

    var example: String {
        switch self {
        case .nameAndCountdown: "Asr 1h 23m"
        case .countdown: "1h 23m"
        case .nameAndTime: "Asr 15:41"
        case .iconOnly: ""
        }
    }
}

/// Owns the app's state: the selected mosque's timetable, the clock that drives the
/// menu bar countdown, refreshing, and the optional Mawaqit account used for search.
@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    // MARK: State

    private(set) var timetable: Timetable? {
        didSet { scheduler = timetable.map(PrayerScheduler.init) }
    }
    private(set) var scheduler: PrayerScheduler?
    private(set) var loadState: LoadState = .idle
    /// When the timetable was last downloaded successfully (shown in the footer).
    private(set) var lastUpdated: Date?
    private(set) var isSignedIn: Bool

    // The menu bar label is stored rather than derived from a clock, and only
    // written when it actually changes, so the status item redraws only then.
    private(set) var menuBarTitle: String?
    private(set) var menuBarSymbol = "moon.stars"

    var menuBarStyle: MenuBarStyle {
        didSet {
            defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle)
            startClock()
        }
    }

    var notifyAtAdhan: Bool {
        didSet { notificationPreferenceChanged(Keys.notifyAtAdhan, enabled: notifyAtAdhan, wasEnabled: oldValue) }
    }

    var notifyAtIqama: Bool {
        didSet { notificationPreferenceChanged(Keys.notifyAtIqama, enabled: notifyAtIqama, wasEnabled: oldValue) }
    }

    /// True when notifications are enabled here but blocked in System Settings.
    private(set) var notificationsBlocked = false

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            LaunchAtLogin.setEnabled(launchAtLogin)
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: Dependencies

    private let client: MawaqitClient
    private let cache: TimetableCache
    private let tokenStore: KeychainTokenStore
    private let defaults: UserDefaults
    @ObservationIgnored private let notifier = PrayerNotifier()

    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var lastRefreshAttempt: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let menuBarStyle = "menuBarStyle"
        static let selectedSlug = "selectedMosqueSlug"
        static let notifyAtAdhan = "notifyAtAdhan"
        static let notifyAtIqama = "notifyAtIqama"
    }

    /// Refetch at least this often; Mawaqit's "today" times may carry manual tweaks.
    private static let refreshInterval: TimeInterval = 6 * 3600
    /// Back-off between automatic attempts while offline.
    private static let retryInterval: TimeInterval = 15 * 60
    /// Longest the clock sleeps, which bounds how late a due refresh is noticed.
    private static let maxTickInterval: TimeInterval = 15 * 60

    init(
        client: MawaqitClient = MawaqitClient(),
        cache: TimetableCache = TimetableCache(),
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.cache = cache
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.isSignedIn = tokenStore.token() != nil
        self.menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .nameAndCountdown
        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.notifyAtAdhan = defaults.bool(forKey: Keys.notifyAtAdhan)
        self.notifyAtIqama = defaults.bool(forKey: Keys.notifyAtIqama)

        timetable = cache.load()
        scheduler = timetable.map(PrayerScheduler.init)
        lastUpdated = timetable?.fetchedAt

        startClock()
        observeSystemEvents()
        Task {
            await updateNotifications()
            await refreshIfNeeded()
        }
    }

    // MARK: Derived values

    var selectedSlug: String? { timetable?.slug ?? defaults.string(forKey: Keys.selectedSlug) }

    var hasMosque: Bool { selectedSlug != nil }

    var mosqueName: String? { timetable?.configuration.displayName }

    /// Formats a time in the mosque's time zone using the user's locale (12/24h).
    func formattedTime(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timetable?.timeZone ?? .current
        return date.formatted(style)
    }

    // MARK: Loading

    func refresh() async {
        guard let slug = selectedSlug, loadState != .loading else { return }
        loadState = .loading
        lastRefreshAttempt = Date()
        do {
            apply(try await client.fetchTimetable(slug: slug))
            setLoadState(.idle)
        } catch {
            Logger.app.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
            setLoadState(.failed(error.localizedDescription))
        }
    }

    /// Validates the mosque by downloading its timetable before switching to it.
    func selectMosque(slug: String) async throws {
        let timetable = try await client.fetchTimetable(slug: slug)
        apply(timetable)
        setLoadState(.idle)
    }

    private func setLoadState(_ state: LoadState) {
        if loadState != state { loadState = state }
    }

    private func apply(_ fetched: Timetable) {
        defaults.set(fetched.slug, forKey: Keys.selectedSlug)
        cache.save(fetched)
        lastUpdated = fetched.fetchedAt

        // Most refreshes return the same timetable. Replacing it would redraw every
        // view and reschedule notifications for nothing, so keep the current one
        // unless something that affects the times differs.
        if let timetable, timetable.slug == fetched.slug,
           timetable.configuration == fetched.configuration,
           scheduler?.calendar.isDate(timetable.fetchedAt, inSameDayAs: fetched.fetchedAt) == true {
            return
        }
        timetable = fetched
        startClock()
        Task { await updateNotifications() }
    }

    private var needsRefresh: Bool {
        guard hasMosque else { return false }
        guard let lastUpdated else { return true }
        let fetchedToday = scheduler?.calendar.isDateInToday(lastUpdated) ?? false
        return Date().timeIntervalSince(lastUpdated) > Self.refreshInterval || !fetchedToday
    }

    private func refreshIfNeeded() async {
        guard needsRefresh else { return }
        if let lastRefreshAttempt, Date().timeIntervalSince(lastRefreshAttempt) < Self.retryInterval,
           case .failed = loadState {
            return
        }
        await refresh()
    }

    // MARK: Account & search

    func signIn(email: String, password: String) async throws {
        let token = try await client.signIn(email: email, password: password)
        tokenStore.setToken(token)
        isSignedIn = true
    }

    func signOut() {
        tokenStore.deleteToken()
        isSignedIn = false
    }

    func searchMosques(_ query: String) async throws -> [MosqueSearchResult] {
        guard let token = tokenStore.token() else {
            isSignedIn = false
            return []
        }
        do {
            return try await client.searchMosques(query, token: token)
        } catch MawaqitError.sessionExpired {
            signOut()
            throw MawaqitError.sessionExpired
        }
    }

    // MARK: Notifications

    private var enabledNotificationKinds: Set<PrayerEvent.Kind> {
        var kinds: Set<PrayerEvent.Kind> = []
        if notifyAtAdhan { kinds.insert(.adhan) }
        if notifyAtIqama { kinds.insert(.iqama) }
        return kinds
    }

    private func notificationPreferenceChanged(_ key: String, enabled: Bool, wasEnabled: Bool) {
        guard enabled != wasEnabled else { return }
        defaults.set(enabled, forKey: key)
        Task { await updateNotifications(requestPermission: enabled) }
    }

    /// Re-schedules the rolling window of notifications from the current timetable
    /// and preferences, asking for permission the first time one is enabled.
    func updateNotifications(requestPermission: Bool = false) async {
        let kinds = enabledNotificationKinds
        guard !kinds.isEmpty, PrayerNotifier.isAvailable else {
            notificationsBlocked = false
            notifier.cancelAll()
            return
        }

        // Ask if permission was never decided, e.g. when settings were carried over from
        // an earlier install; once decided this doesn't prompt again.
        let undecided = await notifier.authorization() == .notDetermined
        let allowed = requestPermission || undecided
            ? await notifier.requestAuthorization()
            : await notifier.authorization() == .authorized
        notificationsBlocked = !allowed
        guard allowed, let scheduler, let mosqueName else {
            notifier.cancelAll()
            return
        }
        await notifier.schedule(scheduler.events(after: Date(), kinds: kinds), mosqueName: mosqueName, formatTime: formattedTime)
    }

    // MARK: Clock

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.updateMenuBar()
                await self.refreshIfNeeded()
                try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100))
            }
        }
    }

    /// Brings the menu bar label up to date and returns how long it will stay valid,
    /// so the clock sleeps exactly until the text would change: e.g. a full minute
    /// for "1h 23m", a second during the final seconds, or until the next adhan or
    /// iqama for styles without a countdown.
    private func updateMenuBar() -> TimeInterval {
        let now = Date()
        let status = scheduler?.status(at: now)

        let symbol = status.map { $0.phase == .iqama ? "hourglass" : $0.prayer.prayer.symbolName } ?? "moon.stars"
        let title = status.flatMap { menuBarText(for: $0, at: now) }
        if symbol != menuBarSymbol { menuBarSymbol = symbol }
        if title != menuBarTitle { menuBarTitle = title }

        return MenuBarClock.refreshInterval(
            for: status,
            at: now,
            showsCountdown: menuBarStyle == .nameAndCountdown || menuBarStyle == .countdown,
            maxInterval: Self.maxTickInterval
        )
    }

    private func menuBarText(for status: PrayerStatus, at now: Date) -> String? {
        let name = status.phase == .iqama ? "Iqama" : status.prayer.displayName
        switch menuBarStyle {
        case .nameAndCountdown: return "\(name) \(CountdownFormatter.compact(status.remaining(at: now)))"
        case .countdown: return CountdownFormatter.compact(status.remaining(at: now))
        case .nameAndTime: return "\(name) \(formattedTime(status.target))"
        case .iconOnly: return nil
        }
    }

    private func observeSystemEvents() {
        let wake: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClockDiscontinuity() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wake))
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: wake))
        }
        // The user may have changed notification permissions in System Settings meanwhile.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.updateNotifications() }
            }
        })
    }

    private func handleClockDiscontinuity() {
        lastRefreshAttempt = nil
        startClock()
        Task { await updateNotifications() }
    }
}
