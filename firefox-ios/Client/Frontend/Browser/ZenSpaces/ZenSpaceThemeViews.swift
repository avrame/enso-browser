// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import ZenSpacesKit

extension Color {
    init(_ rgb: SpaceTheme.RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// A space's background drawn the way Zen draws it (see `ZenGradient`), with
/// Zen's grain texture (zen-grain.png, from zen-browser/desktop, MPL 2.0).
struct ZenSpaceBackground: View {
    let theme: SpaceTheme?
    /// The system appearance, which picks Zen's base color; the page's own
    /// scheme may differ (`zenColorScheme`).
    let dark: Bool

    var body: some View {
        if let gradient = ZenGradient(theme: theme, dark: dark) {
            GeometryReader { proxy in
                ZStack {
                    Color(gradient.base)
                    ForEach(Array(gradient.layers.enumerated()), id: \.offset) { _, layer in
                        Self.view(for: layer, size: proxy.size)
                    }
                    if gradient.grain > 0, let grain = UIImage(named: "zen-grain") {
                        Image(uiImage: grain)
                            .resizable(resizingMode: .tile)
                            .opacity(gradient.grain)
                    }
                }
            }
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private static func view(for layer: ZenGradient.Layer, size: CGSize) -> some View {
        switch layer {
        case .linear(let angle, let stops):
            let line = linearLine(angle: angle, size: size, stops: stops)
            LinearGradient(stops: gradientStops(stops, scale: line.scale), startPoint: line.start, endPoint: line.end)
        case .radial(let centerX, let centerY, let stops):
            let reach = farthestCorner(from: CGPoint(x: centerX * size.width, y: centerY * size.height), in: size)
            let last = stops.map(\.location).max() ?? 1
            RadialGradient(stops: gradientStops(stops, scale: max(last, 1)),
                           center: UnitPoint(x: centerX, y: centerY),
                           startRadius: 0,
                           endRadius: reach * max(last, 1))
        }
    }

    /// CSS places a linear gradient on a line through the center whose length
    /// makes the corners land on 0% and 100%; stops past 100% extend it.
    private struct GradientLine {
        let start: UnitPoint
        let end: UnitPoint
        /// How far past 100% the last stop reaches; stop locations divide by it.
        let scale: Double
    }

    private static func linearLine(angle: Double, size: CGSize, stops: [ZenGradient.Stop]) -> GradientLine {
        let radians = angle * .pi / 180
        let direction = CGVector(dx: sin(radians), dy: -cos(radians))
        let length = abs(size.width * sin(radians)) + abs(size.height * cos(radians))
        let scale = max(stops.map(\.location).max() ?? 1, 1)
        let half = length / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let start = CGPoint(x: center.x - direction.dx * half, y: center.y - direction.dy * half)
        let end = CGPoint(x: start.x + direction.dx * length * scale, y: start.y + direction.dy * length * scale)
        func unit(_ point: CGPoint) -> UnitPoint {
            UnitPoint(x: size.width > 0 ? point.x / size.width : 0, y: size.height > 0 ? point.y / size.height : 0)
        }
        return GradientLine(start: unit(start), end: unit(end), scale: scale)
    }

    /// Transparent stops fade the neighbouring color out, as CSS does.
    private static func gradientStops(_ stops: [ZenGradient.Stop], scale: Double) -> [Gradient.Stop] {
        let fallback = stops.compactMap(\.color).first
        return stops.map { stop in
            let color = stop.color.map { Color($0) } ?? fallback.map { Color($0).opacity(0) } ?? .clear
            return Gradient.Stop(color: color, location: stop.location / scale)
        }
    }

    private static func farthestCorner(from center: CGPoint, in size: CGSize) -> CGFloat {
        [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - center.x, $0.y - center.y) }
            .max() ?? 0
    }
}

extension View {
    /// Light or dark UI over a space, as Zen chooses from its primary color.
    func zenColorScheme(for theme: SpaceTheme?, system: ColorScheme) -> some View {
        let gradient = ZenGradient(theme: theme, dark: system == .dark)
        return environment(\.colorScheme, gradient.map { $0.prefersDarkText ? .light : .dark } ?? system)
    }
}

extension View {
    /// Tints controls and icons over a space with a color that stands out
    /// from its background (`ZenGradient.accent`).
    func zenAccent(for theme: SpaceTheme?, system: ColorScheme) -> some View {
        let accent = ZenGradient(theme: theme, dark: system == .dark).map { Color($0.accent) }
        return tint(accent).environment(\.zenAccent, accent)
    }
}

extension EnvironmentValues {
    @Entry var zenAccent: Color?
}
