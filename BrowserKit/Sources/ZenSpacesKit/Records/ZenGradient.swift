// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// A space's background as Zen draws it, from nsZenThemePicker.getGradient
/// and #getSingleRGBColor on a window that cannot be transparent (as a
/// phone sheet cannot): CSS-style layers over Zen's base color.
public struct ZenGradient: Sendable, Equatable {
    public struct Stop: Sendable, Equatable {
        /// Nil is transparent.
        public let color: SpaceTheme.RGB?
        /// 0 = start of the gradient line or center; 1 = its end. May exceed 1.
        public let location: Double
    }

    public enum Layer: Sendable, Equatable {
        /// CSS `linear-gradient(<angle>deg, …)`: 0° points up, clockwise.
        case linear(angle: Double, stops: [Stop])
        /// CSS `radial-gradient(circle at x y, …)`, sized to the farthest corner;
        /// the center is in unit coordinates of the box.
        case radial(centerX: Double, centerY: Double, stops: [Stop])
    }

    /// Painted first; everything else draws over it.
    public let base: SpaceTheme.RGB
    /// Bottom to top.
    public let layers: [Layer]
    /// Zen's grain overlay opacity.
    public let grain: Double
    /// Whether Zen would use light text on this background (shouldBeDarkMode).
    public let prefersDarkText: Bool
    /// The space's color for controls and icons drawn on this background.
    public let accent: SpaceTheme.RGB

    /// WCAG's minimum for icons and controls.
    public static let minimumAccentContrast = 3.0

    /// The base behind the sidebar where a window cannot be transparent
    /// (getToolbarModifiedBaseRaw).
    public static func base(dark: Bool) -> SpaceTheme.RGB {
        dark ? SpaceTheme.RGB(red: 23 / 255, green: 23 / 255, blue: 26 / 255)
             : SpaceTheme.RGB(red: 240 / 255, green: 240 / 255, blue: 244 / 255)
    }

    /// Nil for a space without a theme: Zen then shows its plain default.
    public init?(theme: SpaceTheme?, dark: Bool) {
        guard let theme, !theme.colors.isEmpty else { return nil }
        let base = Self.base(dark: dark)
        let solid = theme.colors.map { color in
            color.isCustom ? color.rgb : color.rgb.mixed(with: base, amount: theme.opacity)
        }

        self.base = base
        self.grain = theme.texture
        self.layers = Self.layers(solid, hasCustom: theme.colors.contains { $0.isCustom })
        let primary = theme.primary ?? solid[0]
        let darkUI = Self.shouldBeDarkMode(primary: primary, opacity: theme.opacity, base: base)
        self.prefersDarkText = !darkUI
        self.accent = Self.readableAccent(primary: primary,
                                          background: primary.mixed(with: base, amount: theme.opacity),
                                          darkUI: darkUI,
                                          darkSystem: dark)
    }

    /// Zen's getAccentColorForUI, then pushed lighter (dark UI) or darker
    /// (light UI) in the same hue until it stands out from the background.
    /// Zen needs no such step: it draws no controls in the space's color.
    static func readableAccent(primary: SpaceTheme.RGB,
                               background: SpaceTheme.RGB,
                               darkUI: Bool,
                               darkSystem: Bool) -> SpaceTheme.RGB {
        var hsl = HSL(primary)
        let isGray = primary.red == primary.green && primary.green == primary.blue
        if !darkUI && !isGray {
            hsl.saturation = min(1, hsl.saturation + 0.3)
            hsl.lightness = hsl.lightness * 0.4 + (darkSystem ? 0.62 : 0.42) * 0.6
        }
        var accent = hsl.rgb
        let step = darkUI ? 0.05 : -0.05
        while contrast(accent, background) < minimumAccentContrast, (0...1).contains(hsl.lightness + step) {
            hsl.lightness += step
            accent = hsl.rgb
        }
        return accent
    }

    private static func layers(_ colors: [SpaceTheme.RGB], hasCustom: Bool) -> [Layer] {
        let rotation = -30.0
        if colors.count == 1 {
            return [.linear(angle: rotation, stops: [Stop(color: colors[0], location: 0),
                                                     Stop(color: colors[0], location: 1)])]
        }
        if hasCustom || colors.count > 3 {
            let last = Double(colors.count - 1)
            return [.linear(angle: rotation, stops: colors.enumerated().map { index, color in
                Stop(color: color, location: Double(index) / last)
            })]
        }
        if colors.count == 2 {
            // CSS lists the top layer first; getGradient reverses its pair.
            let fade = { (color: SpaceTheme.RGB) in
                [Stop(color: color, location: 0.3), Stop(color: nil, location: 1.2)]
            }
            return [
                .linear(angle: rotation, stops: fade(colors[1])),
                .linear(angle: rotation + 180, stops: fade(colors[0])),
            ]
        }
        func fade(_ color: SpaceTheme.RGB, from start: Double, to end: Double) -> [Stop] {
            [Stop(color: color, location: start), Stop(color: nil, location: end)]
        }
        return [
            .radial(centerX: 0, centerY: 0, stops: fade(colors[0], from: 0.1, to: 0.7)),
            .radial(centerX: 0.95, centerY: 0, stops: fade(colors[1], from: 0, to: 0.75)),
            .linear(angle: -5, stops: fade(colors[2], from: 0.1, to: 0.8)),
        ]
    }

    /// Zen's shouldBeDarkMode for a window that cannot be transparent: the
    /// primary color as painted, then whichever of white or black text
    /// (each at 0.9 alpha) contrasts more.
    static func shouldBeDarkMode(primary: SpaceTheme.RGB, opacity: Double, base: SpaceTheme.RGB) -> Bool {
        let background = primary.mixed(with: base, amount: opacity)
        let white = SpaceTheme.RGB(red: 1, green: 1, blue: 1).mixed(with: background, amount: 0.9)
        let black = SpaceTheme.RGB(red: 0, green: 0, blue: 0).mixed(with: background, amount: 0.9)
        return contrast(background, white) > contrast(background, black)
    }

    static func contrast(_ lhs: SpaceTheme.RGB, _ rhs: SpaceTheme.RGB) -> Double {
        let (first, second) = (luminance(lhs), luminance(rhs))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func luminance(_ color: SpaceTheme.RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }
}

/// Hue in degrees, saturation and lightness 0...1 (Zen's rgbToHsl/hslToRgb).
struct HSL: Equatable {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(_ rgb: SpaceTheme.RGB) {
        let high = max(rgb.red, rgb.green, rgb.blue)
        let low = min(rgb.red, rgb.green, rgb.blue)
        lightness = (high + low) / 2
        guard high != low else {
            hue = 0
            saturation = 0
            return
        }
        let delta = high - low
        saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        switch high {
        case rgb.red: hue = ((rgb.green - rgb.blue) / delta + (rgb.green < rgb.blue ? 6 : 0)) * 60
        case rgb.green: hue = ((rgb.blue - rgb.red) / delta + 2) * 60
        default: hue = ((rgb.red - rgb.green) / delta + 4) * 60
        }
    }

    var rgb: SpaceTheme.RGB {
        guard saturation > 0 else { return SpaceTheme.RGB(red: lightness, green: lightness, blue: lightness) }
        let high = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let low = 2 * lightness - high
        func channel(_ offset: Double) -> Double {
            var t = hue / 360 + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return low + (high - low) * 6 * t }
            if t < 1.0 / 2 { return high }
            if t < 2.0 / 3 { return low + (high - low) * (2.0 / 3 - t) * 6 }
            return low
        }
        return SpaceTheme.RGB(red: channel(1.0 / 3), green: channel(0), blue: channel(-1.0 / 3))
    }
}
