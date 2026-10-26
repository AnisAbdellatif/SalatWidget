import AppKit
import SwiftUI

// A plain EnvironmentKey rather than `@Entry`, whose macro plugin ships only with Xcode.
private struct PanelVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the panel window is on screen. SwiftUI keeps timelines running in a
    /// MenuBarExtra window after it closes, so per-second views pause on this.
    var isPanelVisible: Bool {
        get { self[PanelVisibilityKey.self] }
        set { self[PanelVisibilityKey.self] = newValue }
    }
}

/// Reports whether the hosting window is on screen (ordered in).
///
/// Uses key-value observation of the window's `isVisible`, the one signal that proved
/// reliable for MenuBarExtra windows: they post no occlusion changes when they open,
/// and aren't necessarily key (e.g. when opened while another app is active).
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = { isVisible = $0 }
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = { isVisible = $0 }
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var lastReported: Bool?
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.isVisible) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.report() }
            }
            // The panel's first opening happens before this observer exists.
            report()
        }

        private func report() {
            let visible = window?.isVisible ?? false
            guard visible != lastReported else { return }
            lastReported = visible
            // Defer: this can run during a SwiftUI update, where state must not change.
            DispatchQueue.main.async { [onChange] in onChange?(visible) }
        }
    }
}
