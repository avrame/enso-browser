// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import ZenSpacesKit

/// Picks a space icon the way Zen's picker offers them: any emoji, one of
/// Zen's built-in icons, or none.
struct ZenSpaceIconPicker: View {
    let spaceName: String
    let current: SpaceIcon
    let onPick: (SpaceIcon) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var emoji = ""
    @FocusState private var emojiFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    emojiField
                    Text("Zen Icons").font(.headline)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(SpaceIcon.zenIconNames, id: \.self) { name in
                            iconButton(.zen(name)) {
                                Image(systemName: ZenSpaceIconSymbols.symbol(for: name))
                                    .font(.title3)
                            }
                            .accessibilityLabel(name.replacingOccurrences(of: "-", with: " "))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Icon for \(spaceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("No Icon") { pick(.none) }
                        .disabled(current == .none)
                }
            }
        }
    }

    private var emojiField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emoji").font(.headline)
            HStack {
                TextField("Type or choose an emoji", text: $emoji)
                    .focused($emojiFocused)
                    .font(.title2)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: emoji) { _, text in
                        // The emoji keyboard inserts one emoji; keep only the last one typed.
                        if let last = text.last, text.count > 1 {
                            emoji = String(last)
                        }
                    }
                Button("Use") { pick(.emoji(emoji)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!SpaceIcon.isEmoji(emoji))
            }
            if case .emoji(let existing) = current {
                Text("Current: \(existing)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func iconButton<Label: View>(_ icon: SpaceIcon, @ViewBuilder label: () -> Label) -> some View {
        Button { pick(icon) } label: {
            label()
                .frame(width: 44, height: 44)
                .background(icon == current ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(icon == current ? .isSelected : [])
    }

    private func pick(_ icon: SpaceIcon) {
        onPick(icon)
        dismiss()
    }
}

extension SpaceRecord: @retroactive Identifiable {
    public var id: String { uuid }
}
