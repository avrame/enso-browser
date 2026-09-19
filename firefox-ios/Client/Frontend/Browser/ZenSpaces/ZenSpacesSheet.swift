// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import ZenSpacesKit

/// The page in the selected browser tab, offered for pinning.
struct ZenCurrentPage {
    let url: URL
    let title: String
    /// The icon the page declared, if Firefox saw one.
    let faviconURL: URL?
}

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
    let currentPage: ZenCurrentPage?
    let onOpen: (TabRecord) -> Void
    /// Called with the new pinned tab once the server has accepted it.
    let onPinned: (TabRecord) -> Void

    @AppStorage("zenSpaces.selectedSpace") private var selectedSpace = ""
    @State private var renaming: RenameRequest?
    @State private var draftName = ""
    @State private var isSaving = false
    @State private var writeError: String?
    @State private var unpinning: TabRecord?

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
        .confirmationDialog("Unpin “\(unpinning?.displayTitle ?? "")”?",
                            isPresented: isPresent($unpinning),
                            titleVisibility: .visible,
                            presenting: unpinning) { tab in
            Button("Unpin", role: .destructive) { unpin(tab) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's removed from the space and closed in Zen on your other devices.")
        }
        .alert("Couldn't Save to Zen", isPresented: isPresent($writeError), presenting: writeError) { _ in
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

    private func pin(to space: SpaceRecord) {
        guard let currentPage else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let icon = await ZenFaviconDownloader.dataURL(pageURL: currentPage.url,
                                                              declaredIcon: currentPage.faviconURL)
                let page = PinnablePage(url: currentPage.url, title: currentPage.title, icon: icon)
                if let tab = try await store.pin(page, toSpace: space.uuid) {
                    onPinned(tab)
                }
            } catch {
                writeError = Self.message(for: error)
            }
        }
    }

    private func unpin(_ tab: TabRecord) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await store.unpin(tabID: tab.tabId)
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
                             currentPage: currentPage,
                             isSaving: isSaving,
                             onRename: startRenaming,
                             onPin: pin(to:),
                             onUnpin: { unpinning = $0 },
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
                                .background(stripHighlight(space.record, selected: space.record.uuid == current),
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

    /// The space's own primary color marks the selection, as Zen tints its
    /// sidebar; spaces without a theme use the app tint.
    private func stripHighlight(_ space: SpaceRecord, selected: Bool) -> AnyShapeStyle {
        guard selected else { return AnyShapeStyle(.clear) }
        if let primary = space.parsedTheme?.primary {
            return AnyShapeStyle(Color(primary).opacity(0.35))
        }
        return AnyShapeStyle(.tint.opacity(0.2))
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
    let currentPage: ZenCurrentPage?
    let isSaving: Bool
    let onRename: (RenameRequest) -> Void
    let onPin: (SpaceRecord) -> Void
    let onUnpin: (TabRecord) -> Void
    let onOpen: (TabRecord) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                Section {
                    if space.items.isEmpty {
                        Text("No pinned tabs").foregroundStyle(.secondary)
                    }
                    ForEach(Array(space.items.enumerated()), id: \.offset) { _, item in
                        ZenSidebarItemView(item: item, onOpen: onOpen, onRename: onRename, onUnpin: onUnpin)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .refreshable { await onRefresh() }
        }
        .background(ZenSpaceBackground(theme: space.record.parsedTheme))
    }

    /// Stays put while the space's tabs scroll underneath it.
    private var header: some View {
        HStack(spacing: 8) {
            ZenSpaceIcon(space: space.record)
            spaceMenu
                .foregroundStyle(.primary)
            if let container = space.container {
                Text(container.name)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .fixedSize()
            }
            Spacer(minLength: 8)
            if let currentPage {
                pinButton(currentPage)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    /// At the top of every space, so pinning never needs a scroll.
    @ViewBuilder
    private func pinButton(_ page: ZenCurrentPage) -> some View {
        if isPinnedHere(page.url) {
            Label("Pinned", systemImage: "pin.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .accessibilityLabel("Current page is pinned in \(space.record.name)")
        } else {
            Button {
                onPin(space.record)
            } label: {
                Label("Pin", systemImage: "pin")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(isSaving)
            .accessibilityLabel("Pin current page")
            .accessibilityHint("Pins \(page.title) to \(space.record.name) in Zen")
        }
    }

    private func isPinnedHere(_ url: URL) -> Bool {
        func tabs(in items: [SidebarItem]) -> [TabRecord] {
            items.flatMap { item -> [TabRecord] in
                switch item {
                case .tab(let tab): return [tab]
                case .split(let split): return split.tabs
                case .folder(let folder): return tabs(in: folder.items)
                case .missing: return []
                }
            }
        }
        return tabs(in: space.items).contains { tab in
            URL(string: tab.url).map { PinnedURLMatching.isSamePage($0, url) } ?? false
        }
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
                Text(space.record.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
    /// Offered on tabs directly in a space or folder; split members are not
    /// listed there, so the writer would refuse them.
    let onUnpin: (TabRecord) -> Void

    var body: some View {
        switch item {
        case .tab(let tab):
            // Long-press, not a swipe: a sideways swipe pages between spaces.
            tabRow(tab)
                .contextMenu {
                    Button(role: .destructive) { onUnpin(tab) } label: {
                        Label("Unpin", systemImage: "pin.slash")
                    }
                }
                .accessibilityAction(named: "Unpin") { onUnpin(tab) }
        case .split(let split):
            Label("Split view", systemImage: "rectangle.split.2x1")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(split.tabs, id: \.tabId) { tabRow($0).padding(.leading, 16) }
        case .folder(let folder):
            DisclosureGroup {
                ForEach(Array(folder.items.enumerated()), id: \.offset) { _, child in
                    ZenSidebarItemView(item: child, onOpen: onOpen, onRename: onRename, onUnpin: onUnpin)
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

    private var letterBackground: AnyShapeStyle {
        guard let primary = space.parsedTheme?.primary else { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(Color(primary).opacity(0.45))
    }

    var body: some View {
        if let emoji = Self.emoji(for: space) {
            Text(emoji)
        } else {
            Text(space.name.prefix(1).uppercased())
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(letterBackground, in: Circle())
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
