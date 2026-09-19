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

        /// `self` weighted by `amount` (0...1) over `other`, as Zen's blendColors.
        public func mixed(with other: RGB, amount: Double) -> RGB {
            RGB(red: red * amount + other.red * (1 - amount),
                green: green * amount + other.green * (1 - amount),
                blue: blue * amount + other.blue * (1 - amount))
        }
    }

    public struct Color: Sendable, Equatable {
        public let rgb: RGB
        /// Typed in by the user; Zen draws these unblended.
        public let isCustom: Bool
        public let isPrimary: Bool

        public init(rgb: RGB, isCustom: Bool = false, isPrimary: Bool = false) {
            self.rgb = rgb
            self.isCustom = isCustom
            self.isPrimary = isPrimary
        }
    }

    /// In the order Zen stores and draws them.
    public let colors: [Color]
    /// How strongly Zen paints the colors, 0...1.
    public let opacity: Double
    /// Zen's grain overlay strength, 0...1.
    public let texture: Double

    /// Zen's getPrimaryColor: the one marked primary, else the middle one.
    public var primary: RGB? {
        guard !colors.isEmpty else { return nil }
        return (colors.first { $0.isPrimary } ?? colors[colors.count / 2]).rgb
    }

    public init(colors: [Color], opacity: Double, texture: Double) {
        self.colors = colors
        self.opacity = opacity
        self.texture = texture
    }

    /// Nil when there is no usable gradient (Zen then shows its default).
    public init?(_ raw: JSONValue?) {
        guard let raw, raw["type"]?.stringValue == "gradient",
              case .array(let entries)? = raw["gradientColors"]
        else { return nil }

        let colors = entries.compactMap { entry -> Color? in
            guard let rgb = Self.color(entry["c"]) else { return nil }
            return Color(rgb: rgb,
                         isCustom: entry["isCustom"]?.boolValue == true,
                         isPrimary: entry["isPrimary"]?.boolValue == true)
        }
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
