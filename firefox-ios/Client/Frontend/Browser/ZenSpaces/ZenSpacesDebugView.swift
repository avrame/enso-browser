// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import ZenSpacesKit

/// Read-only view of the Zen spaces synced to the signed-in account.
struct ZenSpacesDebugView: View {
    private enum LoadState {
        case loading
        case loaded(SpacesFetchResult)
        case failed(String)
    }

    private struct OutlineRow: Identifiable {
        let id: Int
        let depth: Int
        let symbol: String
        let title: String
        let detail: String?
    }

    let loadAuth: @MainActor () async throws -> SyncAuth

    @State private var state: LoadState = .loading

    var body: some View {
        List {
            switch state {
            case .loading:
                ProgressView("Fetching spaces…")
            case .failed(let message):
                Section("Could not read spaces") {
                    Text(message).textSelection(.enabled)
                }
            case .loaded(let result):
                loaded(result)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func loaded(_ result: SpacesFetchResult) -> some View {
        let snapshot = result.snapshot
        Section("Summary") {
            LabeledContent("Engine version", value: "\(result.engineVersion)")
            LabeledContent("Records", value: "\(result.records.count)")
            LabeledContent("Spaces", value: "\(snapshot.spaces.count)")
            LabeledContent("Tombstones", value: "\(snapshot.tombstoneCount)")
            ForEach(snapshot.unknownKinds.sorted(by: { $0.key < $1.key }), id: \.key) { kind, count in
                LabeledContent("Unknown kind “\(kind)”", value: "\(count)")
            }
            LabeledContent("Fetched", value: result.fetchedAt.formatted(date: .omitted, time: .standard))
        }
        if !snapshot.issues.isEmpty {
            Section("Issues") {
                ForEach(Array(snapshot.issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue).font(.footnote)
                }
            }
        }
        ForEach(Array(snapshot.essentials.enumerated()), id: \.offset) { _, row in
            Section("Essentials — \(row.container?.name ?? (row.key == "default" ? "No container" : row.key))") {
                ForEach(Array(row.tabs.enumerated()), id: \.offset) { _, tab in
                    rowView(OutlineRow(id: 0, depth: 0, symbol: "star", title: tab.displayTitle, detail: tab.url))
                }
            }
        }
        ForEach(Array(snapshot.spaces.enumerated()), id: \.offset) { _, space in
            Section {
                ForEach(outline(space.items)) { rowView($0) }
            } header: {
                Text(spaceHeader(space))
            }
        }
    }

    private func spaceHeader(_ space: SpaceNode) -> String {
        var header = [space.record.icon, space.record.name].compactMap { $0 }.joined(separator: " ")
        if let container = space.container {
            header += " · \(container.name)"
        }
        return header
    }

    private func rowView(_ row: OutlineRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: row.symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).lineLimit(1)
                if let detail = row.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .contextMenu {
            if let detail = row.detail {
                Button("Copy") { UIPasteboard.general.string = detail }
            }
        }
    }

    private func outline(_ items: [SidebarItem]) -> [OutlineRow] {
        var rows: [OutlineRow] = []
        func add(_ depth: Int, _ symbol: String, _ title: String, _ detail: String?) {
            rows.append(OutlineRow(id: rows.count, depth: depth, symbol: symbol, title: title, detail: detail))
        }
        func walk(_ items: [SidebarItem], depth: Int) {
            for item in items {
                switch item {
                case .tab(let tab):
                    add(depth, tab.pinned ? "pin" : "doc", tab.displayTitle, tab.url)
                case .split(let split):
                    add(depth, "rectangle.split.2x1", "Split view (\(split.record.gridType))", nil)
                    for tab in split.tabs {
                        add(depth + 1, "doc", tab.displayTitle, tab.url)
                    }
                case .folder(let folder):
                    let live = folder.record.live.map { " · live \($0.type)" } ?? ""
                    add(depth, "folder", folder.record.name + live, nil)
                    walk(folder.items, depth: depth + 1)
                case .missing(let id):
                    add(depth, "questionmark.circle", "Missing record", id)
                }
            }
        }
        walk(items, depth: 0)
        return rows
    }

    private func load() async {
        do {
            let auth = try await loadAuth()
            state = .loaded(try await ZenSpacesReader(auth: auth).fetch())
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
