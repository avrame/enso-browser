// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// A space's background as Zen's theme picker stores it (`theme` on a
/// space record, built by nsZenThemePicker.getTheme). Read-only: writes
/// keep the raw theme untouched.
public struct SpaceTheme: Sendable, Equatable {
    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// In the order Zen lists them; the primary color first.
    public let colors: [RGB]
    /// How strongly Zen paints the gradient, 0...1.
    public let opacity: Double
    /// Zen's grain overlay strength, 0...1.
    public let texture: Double

    public var primary: RGB? { colors.first }

    public init(colors: [RGB], opacity: Double, texture: Double) {
        self.colors = colors
        self.opacity = opacity
        self.texture = texture
    }

    /// Nil when there is no usable gradient (Zen then shows its default).
    public init?(_ raw: JSONValue?) {
        guard let raw, raw["type"]?.stringValue == "gradient",
              case .array(let entries)? = raw["gradientColors"]
        else { return nil }

        var primary: [RGB] = []
        var others: [RGB] = []
        for entry in entries {
            guard let color = Self.color(entry["c"]) else { continue }
            if entry["isPrimary"]?.boolValue == true {
                primary.append(color)
            } else {
                others.append(color)
            }
        }
        let colors = primary + others
        guard !colors.isEmpty else { return nil }
        self.init(colors: colors,
                  opacity: Self.unit(raw["opacity"], default: 0.5),
                  texture: Self.unit(raw["texture"], default: 0))
    }

    /// `c` is `[r, g, b]` (0...255), or a CSS color string for custom colors.
    private static func color(_ value: JSONValue?) -> RGB? {
        switch value {
        case .array(let parts)?:
            let numbers = parts.compactMap { part -> Double? in
                if case .number(let number) = part { return number }
                return nil
            }
            guard numbers.count >= 3 else { return nil }
            return RGB(red: clamp(numbers[0] / 255), green: clamp(numbers[1] / 255), blue: clamp(numbers[2] / 255))
        case .string(let css)?:
            return cssColor(css)
        default:
            return nil
        }
    }

    /// `#rgb`, `#rrggbb` and `rgb(r, g, b)` / `rgba(...)`.
    static func cssColor(_ css: String) -> RGB? {
        let css = css.trimmingCharacters(in: .whitespaces).lowercased()
        if css.hasPrefix("#") {
            var hex = String(css.dropFirst())
            if hex.count == 3 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count >= 6, let value = UInt32(hex.prefix(6), radix: 16) else { return nil }
            return RGB(red: Double((value >> 16) & 0xff) / 255,
                       green: Double((value >> 8) & 0xff) / 255,
                       blue: Double(value & 0xff) / 255)
        }
        if css.hasPrefix("rgb"), let open = css.firstIndex(of: "("), let close = css.lastIndex(of: ")") {
            let numbers = css[css.index(after: open)..<close]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0) }
            guard numbers.count >= 3 else { return nil }
            return RGB(red: clamp(numbers[0] / 255), green: clamp(numbers[1] / 255), blue: clamp(numbers[2] / 255))
        }
        return nil
    }

    private static func unit(_ value: JSONValue?, default fallback: Double) -> Double {
        if case .number(let number)? = value { return clamp(number) }
        if let string = value?.stringValue, let number = Double(string) { return clamp(number) }
        return fallback
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

extension SpaceRecord {
    public var parsedTheme: SpaceTheme? { SpaceTheme(theme) }
}
