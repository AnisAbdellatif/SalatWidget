import SalatCore
import SwiftUI

/// Lets the user pick a mosque by pasting its Mawaqit link (no account needed) or by
/// searching for it by name (requires signing in to a free Mawaqit account).
struct MosquePickerPage: View {
    @Environment(AppModel.self) private var model
    let isOnboarding: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isOnboarding {
                VStack(alignment: .leading, spacing: 4) {
                    Label("SalatWidget", systemImage: "moon.stars.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.brand)
                    Text("Choose the mosque whose prayer times you'd like to see in your menu bar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                PageHeader(title: "Choose Mosque", onBack: onDone)
            }

            LinkSection(onSelected: onDone)

            SectionCard(title: "Search by name", systemImage: "magnifyingglass") {
                if model.isSignedIn {
                    SearchSection(onSelected: onDone)
                } else {
                    SignInForm()
                }
            }

            if isOnboarding {
                HStack {
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Paste a link

private struct LinkSection: View {
    @Environment(AppModel.self) private var model
    let onSelected: () -> Void

    @State private var link = ""
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        SectionCard(title: "Paste a Mawaqit link", systemImage: "link") {
            HStack(spacing: 6) {
                TextField("mawaqit.net/de/your-mosque", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .onChange(of: link) { error = nil }

                Button(action: submit) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Use")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Open your mosque's page on mawaqit.net and copy the address from your browser. No account needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submit() {
        guard !isLoading else { return }
        guard let slug = MosqueLink.slug(from: link) else {
            error = MawaqitError.invalidLink.localizedDescription
            return
        }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await model.selectMosque(slug: slug)
                link = ""
                onSelected()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Search

private struct SearchSection: View {
    @Environment(AppModel.self) private var model
    let onSelected: () -> Void

    @State private var query = ""
    @State private var results: [MosqueSearchResult] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var selectingID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Mosque name or city", text: $query)
                .textFieldStyle(.roundedBorder)

            content

            HStack {
                Text("Signed in to Mawaqit")
                Spacer()
                Button("Sign Out") { model.signOut() }
                    .buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        // Debounced: restarts (and cancels the previous search) on every keystroke.
        .task(id: query) {
            await search()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else if isSearching && results.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching…").font(.caption).foregroundStyle(.secondary)
            }
        } else if !results.isEmpty {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results, id: \.slug) { result in
                        ResultRow(
                            result: result,
                            isSelected: result.slug == model.selectedSlug,
                            isLoading: selectingID == result.slug,
                            action: { select(result) }
                        )
                    }
                }
            }
            .frame(height: min(CGFloat(results.count) * 40, 280))
        } else if query.trimmingCharacters(in: .whitespaces).count >= 2 && !isSearching {
            Text("No mosques found.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func search() async {
        error = nil
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await model.searchMosques(trimmed)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            results = []
            self.error = error.localizedDescription
        }
    }

    private func select(_ result: MosqueSearchResult) {
        guard selectingID == nil else { return }
        let slug = result.slug
        selectingID = slug
        Task {
            defer { selectingID = nil }
            do {
                try await model.selectMosque(slug: slug)
                onSelected()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ResultRow: View {
    let result: MosqueSearchResult
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns")
                    .foregroundStyle(Color.brand)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.label)
                        .lineLimit(1)
                    if !result.place.isEmpty {
                        Text(result.place)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.brand)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(isHovering ? 0.07 : 0))
            )
        }
        .buttonStyle(.plain)
        .help(result.label)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Sign in

private struct SignInForm: View {
    @Environment(AppModel.self) private var model

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var error: String?

    private static let registerURL = URL(string: "https://mawaqit.net/en/backoffice/register/")!

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mawaqit only allows searching with a free account. Your password goes straight to Mawaqit and is never stored. Only an access token is kept in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Email", text: $email)
                .textContentType(.username)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Link("Create an account", destination: Self.registerURL)
                    .font(.caption)
                Spacer()
                Button(action: submit) {
                    if isSigningIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .onChange(of: email) { error = nil }
        .onChange(of: password) { error = nil }
    }

    private func submit() {
        guard canSubmit else { return }
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
