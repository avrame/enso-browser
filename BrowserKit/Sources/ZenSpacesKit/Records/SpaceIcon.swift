// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// A space's icon as Zen stores it: an emoji, one of Zen's built-in SVG
/// icons (by URL), or none (ZenEmojiPicker / ZenSpaceManager).
public enum SpaceIcon: Sendable, Equatable, Hashable {
    case emoji(String)
    /// The file name without `.svg`, e.g. "layers".
    case zen(String)
    case none

    public static let zenIconPrefix = "chrome://browser/skin/zen-icons/selectable/"

    /// Zen's selectable icons, in its picker's order (ZenEmojiPicker.mjs).
    public static let zenIconNames = [
        "airplane", "american-football", "baseball", "basket", "bed", "bell", "bookmark", "book",
        "briefcase", "brush", "bug", "build", "cafe", "call", "card", "chat",
        "checkbox", "circle", "cloud", "code", "coins", "construct", "cutlery", "egg",
        "extension-puzzle", "eye", "fast-food", "fish", "flag", "flame", "flask", "folder",
        "game-controller", "globe-1", "globe", "grid-2x2", "grid-3x3", "heart", "ice-cream", "image",
        "inbox", "key", "layers", "leaf", "lightning", "location", "lock-closed", "logo-rss",
        "logo-usd", "mail", "map", "megaphone", "moon", "music", "navigate", "nuclear",
        "page", "palette", "paw", "people", "pizza", "planet", "present", "rocket",
        "school", "shapes", "shirt", "skull", "squares", "square", "star-1", "star",
        "stats-chart", "sun", "tada", "terminal", "ticket", "time", "trash", "triangle",
        "video", "volume-high", "wallet", "warning", "water", "weight",
    ]

    /// Anything unrecognised (another icon URL, an image) is kept as none for
    /// display; writes never produce it.
    public init(stored: String?) {
        guard let stored, !stored.isEmpty else {
            self = .none
            return
        }
        if stored.hasPrefix(Self.zenIconPrefix), stored.hasSuffix(".svg") {
            let name = String(stored.dropFirst(Self.zenIconPrefix.count).dropLast(4))
            self = Self.zenIconNames.contains(name) ? .zen(name) : .none
        } else if stored.contains(":") {
            self = .none
        } else {
            self = .emoji(stored)
        }
    }

    /// The value written to the record's `icon`, or nil for none.
    public var stored: String? {
        switch self {
        case .emoji(let emoji): return emoji
        case .zen(let name): return "\(Self.zenIconPrefix)\(name).svg"
        case .none: return nil
        }
    }

    /// An emoji is one visible character made only of emoji; anything
    /// else would show as text in Zen's sidebar.
    public static func isEmoji(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        return character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (character.unicodeScalars.first?.properties.isEmoji == true
                && character.unicodeScalars.contains { $0.value == 0xFE0F })
    }
}

extension SpaceRecord {
    public var spaceIcon: SpaceIcon { SpaceIcon(stored: icon) }
}
