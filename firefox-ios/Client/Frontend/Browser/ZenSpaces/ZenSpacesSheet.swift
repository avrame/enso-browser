// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import ZenSpacesKit

/// A space or folder the user asked to rename, with the name to start from.
private struct RenameRequest {
    let target: RenameTarget
    let currentName: String

    var title: String {
        switch target {
        case .space: return "Rename Space"
        case .folder: return "Rename Folder"
        }
    }
}

/// Zen's spaces on a phone: Essentials on top, one page per space that
/// swipes sideways, and a strip of space icons to jump between them.
struct ZenSpacesSheet: View {
    @ObservedObject var store: SpacesStore
    let onOpen: (TabRecord) -> Void

    @AppStorage("zenSpaces.selectedSpace") private var selectedSpace = ""
    @State private var renaming: RenameRequest?
    @State private var draftName = ""
    @State private var isSaving = false
    @State private var writeError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = store.snapshot, !snapshot.spaces.isEmpty {
                essentials(snapshot)
                pages(snapshot)
                spaceStrip(snapshot)
            } else {
                emptyState
            }
            statusLine
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // The rename alert's keyboard would squeeze the paging TabView to zero
        // height, which snaps it back to the first space.
        .ignoresSafeArea(.keyboard)
        .task { await store.refresh() }
        .alert(renaming?.title ?? "", isPresented: isPresent($renaming), presenting: renaming) { request in
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { save(request.target) }
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { _ in
            Text("The new name also appears in Zen on your other devices.")
        }
        .alert("Couldn't Rename", isPresented: isPresent($writeError), presenting: writeError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: Renaming

    private func startRenaming(_ request: RenameRequest) {
        draftName = request.currentName
        renaming = request
    }

    /// Nothing changes locally until the server has accepted the new name.
    private func save(_ target: RenameTarget) {
        let name = draftName
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await store.rename(target, to: name)
            } catch {
                writeError = Self.message(for: error)
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let error as ZenSpacesWriteError: return error.description
        case let error as ZenSpacesAuthError: return error.description
        case let error as SyncStorageError: return error.description
        default: return error.localizedDescription
        }
    }

    private func isPresent<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    // MARK: Essentials

    @ViewBuilder
    private func essentials(_ snapshot: SpacesSnapshot) -> some View {
        let tabs = snapshot.essentials.flatMap(\.tabs)
        if !tabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tabs, id: \.tabId) { tab in
                        Button { onOpen(tab) } label: {
                            ZenSpacesFavicon(tab: tab, size: 28)
                                .frame(width: 52, height: 52)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.displayTitle)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: Space pages

    private func pages(_ snapshot: SpacesSnapshot) -> some View {
        let selection = selection(snapshot)
        return TabView(selection: selection) {
            ForEach(snapshot.spaces, id: \.record.uuid) { space in
                ZenSpacePage(space: space,
                             allSpaces: snapshot.spaces,
                             selection: selection,
                             onRename: startRenaming,
                             onOpen: onOpen,
                             onRefresh: { await store.refresh() })
                    .tag(space.record.uuid)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// Keeps the current space's icon in view as pages change.
    private func spaceStrip(_ snapshot: SpacesSnapshot) -> some View {
        let current = selection(snapshot).wrappedValue
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(snapshot.spaces, id: \.record.uuid) { space in
                        Button {
                            withAnimation { selectedSpace = space.record.uuid }
                        } label: {
                            ZenSpaceIcon(space: space.record)
                                .frame(width: 36, height: 36)
                                .background(space.record.uuid == current ? AnyShapeStyle(.tint.opacity(0.2))
                                                                          : AnyShapeStyle(.clear),
                                            in: Circle())
                        }
                        .buttonStyle(.plain)
                        .id(space.record.uuid)
                        .accessibilityLabel(space.record.name)
                        .accessibilityAddTraits(space.record.uuid == current ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
            }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, uuid in
                withAnimation { proxy.scrollTo(uuid, anchor: .center) }
            }
        }
        .padding(.vertical, 8)
    }

    /// Falls back to the first space when the remembered one is gone.
    private func selection(_ snapshot: SpacesSnapshot) -> Binding<String> {
        Binding(
            get: {
                snapshot.spaces.contains { $0.record.uuid == selectedSpace }
                    ? selectedSpace
                    : snapshot.spaces.first?.record.uuid ?? ""
            },
            set: { selectedSpace = $0 }
        )
    }

    // MARK: Empty and status

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if store.status == .refreshing {
                ProgressView()
            } else {
                Image(systemName: "square.stack.3d.up")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No spaces yet").font(.headline)
                Text("Turn on Settings → Sync → Sync your Spaces in Zen, and sign in here with the same account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusLine: some View {
        if isSaving {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Saving to Zen…")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        } else {
            syncStatus
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch store.status {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal)
                .padding(.bottom, 8)
        case .refreshing, .idle:
            if let fetchedAt = store.fetchedAt {
                Text("Synced \(fetchedAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct ZenSpacePage: View {
    let space: SpaceNode
    let allSpaces: [SpaceNode]
    @Binding var selection: String
    let onRename: (RenameRequest) -> Void
    let onOpen: (TabRecord) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            Section {
                if space.items.isEmpty {
                    Text("No pinned tabs").foregroundStyle(.secondary)
                }
                ForEach(Array(space.items.enumerated()), id: \.offset) { _, item in
                    ZenSidebarItemView(item: item, onOpen: onOpen, onRename: onRename)
                }
            } header: {
                HStack(spacing: 8) {
                    ZenSpaceIcon(space: space.record)
                    spaceMenu
                    if let container = space.container {
                        Text(container.name)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .textCase(nil)
                .foregroundStyle(.primary)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await onRefresh() }
    }

    /// Every space by name, for jumping when the strip holds too many to scan.
    private var spaceMenu: some View {
        Menu {
            Picker("Space", selection: $selection.animation()) {
                ForEach(allSpaces, id: \.record.uuid) { space in
                    Text(ZenSpaceIcon.menuTitle(for: space.record)).tag(space.record.uuid)
                }
            }
            Divider()
            Button {
                onRename(RenameRequest(target: .space(space.record.uuid), currentName: space.record.name))
            } label: {
                Label("Rename Space…", systemImage: "pencil")
            }
        } label: {
            HStack(spacing: 4) {
                Text(space.record.name).font(.headline).multilineTextAlignment(.leading)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Space: \(space.record.name)")
        .accessibilityHint("Shows all spaces and space actions")
    }
}

private struct ZenSidebarItemView: View {
    let item: SidebarItem
    let onOpen: (TabRecord) -> Void
    let onRename: (RenameRequest) -> Void

    var body: some View {
        switch item {
        case .tab(let tab):
            tabRow(tab)
        case .split(let split):
            Label("Split view", systemImage: "rectangle.split.2x1")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(split.tabs, id: \.tabId) { tabRow($0).padding(.leading, 16) }
        case .folder(let folder):
            DisclosureGroup {
                ForEach(Array(folder.items.enumerated()), id: \.offset) { _, child in
                    ZenSidebarItemView(item: child, onOpen: onOpen, onRename: onRename)
                }
            } label: {
                Label(folder.record.name, systemImage: folder.record.live == nil ? "folder" : "dot.radiowaves.up.forward")
                    .contextMenu {
                        Button {
                            onRename(RenameRequest(target: .folder(folder.record.folderId),
                                                   currentName: folder.record.name))
                        } label: {
                            Label("Rename Folder…", systemImage: "pencil")
                        }
                    }
                    .accessibilityAction(named: "Rename Folder") {
                        onRename(RenameRequest(target: .folder(folder.record.folderId), currentName: folder.record.name))
                    }
            }
        case .missing:
            EmptyView()
        }
    }

    private func tabRow(_ tab: TabRecord) -> some View {
        Button { onOpen(tab) } label: {
            HStack(spacing: 12) {
                ZenSpacesFavicon(tab: tab, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.displayTitle).lineLimit(1)
                    Text(URL(string: tab.url)?.host() ?? tab.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

private struct ZenSpaceIcon: View {
    let space: SpaceRecord

    /// Zen space icons are emoji or `chrome://` image URLs, which cannot load here.
    static func emoji(for space: SpaceRecord) -> String? {
        guard let icon = space.icon, !icon.isEmpty, !icon.contains(":") else { return nil }
        return icon
    }

    static func menuTitle(for space: SpaceRecord) -> String {
        emoji(for: space).map { "\($0)  \(space.name)" } ?? space.name
    }

    var body: some View {
        if let emoji = Self.emoji(for: space) {
            Text(emoji)
        } else {
            Text(space.name.prefix(1).uppercased())
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
        }
    }
}

/// Zen syncs favicons as `data:` URLs; anything unusable gets a letter.
struct ZenSpacesFavicon: View {
    let tab: TabRecord
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        if let favicon = ZenFaviconImages.favicon(for: tab.icon, dark: dark) {
            let vanishes = favicon.tone == (dark ? .dark : .light)
            Image(uiImage: favicon.image)
                .resizable()
                .scaledToFit()
                .frame(width: vanishes ? size * 0.7 : size, height: vanishes ? size * 0.7 : size)
                .frame(width: size, height: size)
                .background(vanishes ? Color(white: dark ? 0.85 : 0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: size / 4))
                .accessibilityHidden(true)
        } else {
            Text((URL(string: tab.url)?.host() ?? tab.displayTitle).prefix(1).uppercased())
                .font(.system(size: size * 0.55, weight: .semibold))
                .frame(width: size, height: size)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: size / 4))
        }
    }
}
