#if DEBUG
import AppKit
import SalatCore
import SwiftUI

/// Tools for reviewing and profiling the app without clicking through it. Debug builds only.
///
///     # Render the panel pages (light and dark) to PNG files, then quit:
///     swift run SalatWidget --snapshot <output-dir> [mosque-slug]
///
///     # Open/close the real panel after each delay (seconds), e.g. to measure CPU
///     # with `top` while it's open and after it closes; --capture-dir saves what it shows.
///     # Since macOS 27 synthetic clicks may not open the menu bar item (see openPanel()).
///     swift run SalatWidget --toggle-panel 5 30 [--capture-dir <dir>]
///
///     # Measure the app's own CPU time and wakeups with the panel closed, open and
///     # closed again, write them as JSON and quit (used by scripts/perf-check.sh):
///     swift run SalatWidget --perf-report <output.json> [--perf-seconds 15] [--slug assunna-hannover]
@MainActor
enum DebugTools {
    static func renderSnapshotsIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 else { return }
        let output = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        let slug = arguments.count > flag + 2 ? arguments[flag + 2] : "assunna-hannover"

        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        } catch {
            print("Snapshot failed: \(error)")
            exit(1)
        }
        let sandbox = makeSandbox()
        let model = isolatedModel(slug: slug, sandbox: sandbox)
        let empty = AppModel(
            cache: TimetableCache(directory: sandbox.appending(path: "empty")),
            tokenStore: KeychainTokenStore(service: isolatedDomain),
            defaults: UserDefaults(suiteName: isolatedDomain)!
        )

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            render(PanelView().environment(model), appearance: appearance, to: output.appending(path: "times-\(suffix).png"))
            render(SettingsPage(onDone: {}).environment(model).padding(14).frame(width: 330), appearance: appearance, to: output.appending(path: "settings-\(suffix).png"))
            render(PanelView().environment(empty), appearance: appearance, to: output.appending(path: "onboarding-\(suffix).png"))
        }
        try? FileManager.default.removeItem(at: sandbox)
        print("Wrote snapshots to \(output.path)")
        exit(0)
    }

    // MARK: Isolated state

    /// Defaults suite and keychain service used instead of the real ones.
    private static let isolatedDomain = "SalatWidgetDebug"

    private static func makeSandbox() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "SalatWidgetDebug-\(UUID().uuidString)")
    }

    /// A model with its own cache, defaults and keychain entry, primed with a freshly
    /// downloaded timetable, so debug runs never touch the real app's state.
    private static func isolatedModel(slug: String, sandbox: URL) -> AppModel {
        let defaults = UserDefaults(suiteName: isolatedDomain)!
        defaults.removePersistentDomain(forName: isolatedDomain)
        let cache = TimetableCache(directory: sandbox)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var fetched: Result<Timetable, any Error>?
        Task.detached {
            do { fetched = .success(try await MawaqitClient().fetchTimetable(slug: slug)) } catch { fetched = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        do {
            cache.save(try fetched!.get())
        } catch {
            print("Couldn't load \(slug): \(error)")
            exit(1)
        }
        return AppModel(cache: cache, tokenStore: KeychainTokenStore(service: isolatedDomain), defaults: defaults)
    }

    // MARK: Performance report

    private static var perfArguments: (output: URL, seconds: Double, slug: String)? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--perf-report"), arguments.count > flag + 1 else { return nil }
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil }
        }
        return (
            URL(fileURLWithPath: arguments[flag + 1]),
            value("--perf-seconds").flatMap(Double.init) ?? 15,
            value("--slug") ?? "assunna-hannover"
        )
    }

    /// The model to use for a `--perf-report` run, or nil for a normal launch.
    static func perfReportModelIfRequested() -> AppModel? {
        guard let options = perfArguments else { return nil }
        let model = isolatedModel(slug: options.slug, sandbox: makeSandbox())
        perfModel = model
        return model
    }

    private static var perfModel: AppModel?
    private static var standInPanel: NSWindow?

    /// Opens the panel by clicking the status item. Since macOS 27 the status item is a
    /// scene-based item whose clicks the system handles, so synthetic clicks may not open
    /// it; then the same PanelView is shown in a floating stand-in window instead, which
    /// exercises the same views, timelines and visibility tracking.
    private static func openPanel() async -> String {
        clickStatusItem()
        try? await Task.sleep(for: .seconds(1))
        if isPanelOnScreen { return "statusItem" }
        guard let model = perfModel else { return "none" }

        let controller = NSHostingController(rootView: PanelView().environment(model))
        controller.sizingOptions = [.preferredContentSize]
        let panel = NSPanel(contentViewController: controller)
        panel.styleMask = [.nonactivatingPanel, .fullSizeContentView, .titled]
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        standInPanel = panel
        return "standIn"
    }

    /// Runs the scenario: warm up, then measure with the panel closed, open (opened by
    /// clicking the status item) and closed again. Writes JSON and quits.
    static func startPerfReportIfRequested() {
        guard let options = perfArguments else { return }
        let settle: Duration = .seconds(2)
        let phase: Duration = .milliseconds(Int(options.seconds * 1000))

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))  // launch, first layout, first tick
            var report: [String: [String: Any]] = [:]

            @MainActor func measure(_ name: String) async {
                let start = (ResourceUsage.current(), renders: RenderCounter.counts)
                try? await Task.sleep(for: phase)
                let end = (ResourceUsage.current(), renders: RenderCounter.counts)
                let elapsed = end.0.uptime - start.0.uptime
                report[name] = [
                    "seconds": elapsed,
                    "cpuPercent": (end.0.cpuSeconds - start.0.cpuSeconds) / elapsed * 100,
                    "wakeupsPerSecond": Double(end.0.idleWakeups - start.0.idleWakeups) / elapsed,
                    "panelVisible": isPanelOnScreen,
                    "countdownRendersPerSecond": Double(end.renders[.countdown, default: 0] - start.renders[.countdown, default: 0]) / elapsed,
                    "timetableRenders": end.renders[.timetable, default: 0] - start.renders[.timetable, default: 0],
                ]
                print("perf \(name): \(report[name]!)")
            }

            await measure("closed")
            let source = await openPanel()
            try? await Task.sleep(for: settle)
            await measure("open")
            report["open"]?["panelSource"] = source
            // Close the way a click elsewhere would: a second status item click
            // sometimes re-opens the panel right away, which would skew the phase.
            closePanel()
            try? await Task.sleep(for: settle)
            await measure("closedAgain")

            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: options.output)
                exit(0)
            } catch {
                print("Couldn't write report: \(error)")
                exit(1)
            }
        }
    }

    // MARK: Driving the status item

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBarWindow")
    }

    private static var isPanelOnScreen: Bool {
        NSApp.windows.contains { $0.isVisible && !isStatusBarWindow($0) }
    }

    private static func closePanel() {
        NSApp.windows.filter { $0.isVisible && !isStatusBarWindow($0) }.forEach { $0.close() }
    }

    /// Clicks the app's own status item. Since macOS 27, SwiftUI's menu bar item reacts
    /// to mouse events rather than a button action, so a real mouse-down/up pair is sent
    /// to its window (`performClick` alone no longer opens the panel).
    @discardableResult
    private static func clickStatusItem() -> Bool {
        guard let button = NSApp.windows.filter(isStatusBarWindow).compactMap({ $0.contentView.flatMap(findButton) }).first,
              let window = button.window
        else { return false }
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            )
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return false }
        // Queue the mouse-up first: handling the mouse-down starts a tracking loop that
        // waits for it, and would otherwise block forever.
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
        return true
    }

    /// `--toggle-panel <seconds>...`: clicks the app's own status item after each delay,
    /// so the panel can be opened and closed (e.g. for profiling) without a mouse.
    static func scheduleStatusItemClicksIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--toggle-panel") else { return }
        let delays = arguments[(flag + 1)...].prefix { Double($0) != nil }.compactMap(Double.init)
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    print("+\(delay)s clicked status item: \(clickStatusItem())")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    MainActor.assumeIsolated {
                        let visible = NSApp.windows.filter { $0.isVisible && !isStatusBarWindow($0) }.map { String(describing: type(of: $0)) }
                        print("+\(delay + 1)s visible windows: \(visible)")
                        fflush(stdout)
                    }
                }
                // With --capture-dir, save what the open panel shows 1 s and 3 s after the click.
                if let dirFlag = arguments.firstIndex(of: "--capture-dir"), arguments.count > dirFlag + 1 {
                    for offset in [1.0, 3.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + offset) {
                            MainActor.assumeIsolated {
                                guard let view = NSApp.windows.first(where: { $0.isVisible && !isStatusBarWindow($0) })?.contentView,
                                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                                view.cacheDisplay(in: view.bounds, to: rep)
                                let url = URL(fileURLWithPath: arguments[dirFlag + 1]).appending(path: "panel-\(Int(delay + offset))s.png")
                                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func findButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap(findButton).first
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Counts how often instrumented view bodies run, so a perf run can tell that the
/// countdown really ticks once a second (neither frozen nor redrawn every frame).
@MainActor
enum RenderCounter {
    enum View: Hashable {
        case countdown
        case timetable
    }

    private(set) static var counts: [View: Int] = [:]

    static func count(_ view: View) {
        counts[view, default: 0] += 1
    }
}

/// The process's own CPU time and wakeups, as reported by the kernel.
private struct ResourceUsage {
    let uptime: TimeInterval
    let cpuSeconds: TimeInterval
    /// Wakeups from idle (the `IDLEW` column in `top`): the energy cost of timers.
    let idleWakeups: UInt64

    static func current() -> ResourceUsage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000

        var info = task_power_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(task_self_trap(), task_flavor_t(TASK_POWER_INFO), $0, &count)
            }
        }
        return ResourceUsage(
            uptime: ProcessInfo.processInfo.systemUptime,
            cpuSeconds: cpu,
            idleWakeups: status == KERN_SUCCESS ? info.task_platform_idle_wakeups : 0
        )
    }
}
#endif
