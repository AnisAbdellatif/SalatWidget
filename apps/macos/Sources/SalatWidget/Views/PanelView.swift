import SwiftUI

/// Root of the window shown when the menu bar item is clicked.
struct PanelView: View {
    private enum Route {
        case times
        case mosque
        case settings
    }

    @Environment(AppModel.self) private var model
    @State private var route: Route = .times
    @State private var isVisible = false

    var body: some View {
        Group {
            if !model.hasMosque {
                MosquePickerPage(isOnboarding: true, onDone: { route = .times })
            } else {
                switch route {
                case .times:
                    TimesPage(
                        onChangeMosque: { route = .mosque },
                        onOpenSettings: { route = .settings }
                    )
                case .mosque:
                    MosquePickerPage(isOnboarding: false, onDone: { route = .times })
                case .settings:
                    SettingsPage(onDone: { route = .times })
                }
            }
        }
        .padding(14)
        .frame(width: 330)
        .animation(.snappy(duration: 0.22), value: route)
        .background(WindowVisibilityReader(isVisible: $isVisible))        .environment(\.isPanelVisible, isVisible)
    }
}
