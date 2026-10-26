import SwiftUI

struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    let onDone: () -> Void

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Settings", onBack: onDone)

            SectionCard(title: "Menu bar", systemImage: "menubar.rectangle") {
                Picker("Show", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        HStack {
                            Text(style.title)
                            if !style.example.isEmpty {
                                Text(style.example)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text("While the adhan has been called, the menu bar counts down to the iqama instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionCard(title: "Notifications", systemImage: "bell.badge") {
                switchRow("At adhan", isOn: $model.notifyAtAdhan)
                switchRow("At iqama", isOn: $model.notifyAtIqama)

                if !PrayerNotifier.isAvailable {
                    Text("Available when running the installed app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.notificationsBlocked {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Notifications are turned off for SalatWidget.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Open Settings") { PrayerNotifier.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
            }
            .disabled(!PrayerNotifier.isAvailable)

            SectionCard(title: "General", systemImage: "gearshape") {
                switchRow("Open at login", isOn: $model.launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                if !LaunchAtLogin.isAvailable {
                    Text("Available when running the installed app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.isSignedIn {
                SectionCard(title: "Mawaqit account", systemImage: "person.crop.circle") {
                    HStack {
                        Text("Signed in. Used only for mosque search.")
                            .font(.callout)
                        Spacer()
                        Button("Sign Out") { model.signOut() }
                    }
                }
            }

            Text("Prayer times provided by mawaqit.net · Version \(Self.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }

    /// A label on the left with a small switch aligned to the right edge.
    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
