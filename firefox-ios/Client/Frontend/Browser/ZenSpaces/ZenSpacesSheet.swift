// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import ZenSpacesKit

/// Zen's spaces on a phone: Essentials on top, one page per space that
/// swipes sideways, and a strip of space icons to jump between them.
struct ZenSpacesSheet: View {
    @ObservedObject var store: SpacesStore
    let onOpen: (TabRecord) -> Void

    @AppStorage("zenSpaces.selectedSpace") private var selectedSpace = ""

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
        .task { await store.refresh() }
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
        TabView(selection: selection(snapshot)) {
            ForEach(snapshot.spaces, id: \.record.uuid) { space in
                ZenSpacePage(space: space, onOpen: onOpen, onRefresh: { await store.refresh() })
                    .tag(space.record.uuid)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func spaceStrip(_ snapshot: SpacesSnapshot) -> some View {
        let current = selection(snapshot).wrappedValue
        return ScrollView(.horizontal, showsIndicators: false) {
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
                    .accessibilityLabel(space.record.name)
                    .accessibilityAddTraits(space.record.uuid == current ? .isSelected : [])
                }
            }
            .padding(.horizontal)
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
    let onOpen: (TabRecord) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            Section {
                if space.items.isEmpty {
                    Text("No pinned tabs").foregroundStyle(.secondary)
                }
                ForEach(Array(space.items.enumerated()), id: \.offset) { _, item in
                    ZenSidebarItemView(item: item, onOpen: onOpen)
                }
            } header: {
                HStack(spacing: 8) {
                    ZenSpaceIcon(space: space.record)
                    Text(space.record.name).font(.headline)
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
}

private struct ZenSidebarItemView: View {
    let item: SidebarItem
    let onOpen: (TabRecord) -> Void

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
                    ZenSidebarItemView(item: child, onOpen: onOpen)
                }
            } label: {
                Label(folder.record.name, systemImage: folder.record.live == nil ? "folder" : "dot.radiowaves.up.forward")
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

    var body: some View {
        if let icon = space.icon, !icon.isEmpty, !icon.contains(":") {
            Text(icon)
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
