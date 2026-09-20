// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Lists the loaded extensions and installs new ones from a `.xpi`.
struct ZenExtensionsView: View {
    private struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String
        let permissions: [String]
        let errors: [String]
        let context: WKWebExtensionContext
    }

    @State private var installed: [Installed] = []
    @State private var failures: [LoadFailure] = []
    @State private var isPicking = false
    @State private var isInstalling = false
    @State private var failure: String?

    private static let packageTypes: [UTType] = [UTType(filenameExtension: "xpi") ?? .zip, .zip, .folder]

    var body: some View {
        List {
            if let failure {
                Section("Could not install") {
                    Text(failure).textSelection(.enabled)
                }
            }
            installSection
            failureSection
            Section("Installed") {
                if installed.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(installed) { extensionRow($0) }
                    .onDelete(perform: remove)
            }
        }
        .toolbar { EditButton() }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: Self.packageTypes) { result in
            switch result {
            case .success(let url):
                install(url)
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
        .onAppear(perform: reload)
    }

    private var installSection: some View {
        Section {
            Button {
                isPicking = true
            } label: {
                if isInstalling {
                    HStack {
                        ProgressView()
                        Text("Installing…")
                    }
                } else {
                    Text("Install from a file…")
                }
            }
            .disabled(isInstalling)
        } footer: {
            Text("Pick an extension package (.xpi or .zip) or an unpacked folder.")
        }
    }

    @ViewBuilder
    private var failureSection: some View {
        if !failures.isEmpty {
            Section("Would not load") {
                ForEach(failures) { failure in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.package).font(.headline)
                        Text(failure.message).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func extensionRow(_ item: Installed) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.headline)
            Text("Version \(item.version) · \(item.id)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !item.permissions.isEmpty {
                Text(item.permissions.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(item.errors.enumerated()), id: \.offset) { _, error in
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func install(_ url: URL) {
        isInstalling = true
        failure = nil
        Task { @MainActor in
            do {
                try await ZenWebExtensions.shared.add(package: url)
            } catch {
                failure = "\(error)"
            }
            isInstalling = false
            reload()
        }
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets {
            do {
                try ZenWebExtensions.shared.remove(installed[index].context)
            } catch {
                failure = "\(error)"
            }
        }
        reload()
    }

    private func reload() {
        failures = ZenWebExtensions.shared.failures
        installed = ZenWebExtensions.shared.contexts.map { context in
            let webExtension = context.webExtension
            return Installed(id: context.uniqueIdentifier,
                             name: webExtension.displayName ?? "Unnamed",
                             version: webExtension.displayVersion ?? "?",
                             permissions: webExtension.requestedPermissions.map(\.rawValue).sorted(),
                             errors: webExtension.errors.map { $0.localizedDescription },
                             context: context)
        }
    }
}
