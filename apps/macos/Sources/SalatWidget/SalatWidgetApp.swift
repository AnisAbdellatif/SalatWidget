import AppKit
import SwiftUI

@main
struct SalatWidgetApp: App {
    @State private var model: AppModel

    init() {
        // Menu bar only: no Dock icon or app menu, also when launched via `swift run`
        // (the bundled app gets the same from `LSUIElement`).
        NSApplication.shared.setActivationPolicy(.accessory)
        #if DEBUG
        DebugTools.renderSnapshotsIfRequested()
        _model = State(initialValue: DebugTools.perfReportModelIfRequested() ?? AppModel())
        DebugTools.scheduleStatusItemClicksIfRequested()
        DebugTools.startPerfReportIfRequested()
        #else
        _model = State(initialValue: AppModel())
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// What appears in the menu bar itself.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let title = model.menuBarTitle {
            HStack(spacing: 4) {
                Image(systemName: model.menuBarSymbol)
                Text(title)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        } else {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("Prayer times")
        }
    }
}
