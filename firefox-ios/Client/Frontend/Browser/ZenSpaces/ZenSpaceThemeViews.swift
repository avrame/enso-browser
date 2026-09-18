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

/// An approximation of Zen's space background: the theme's colors as a
/// soft diagonal gradient, faded by the theme's opacity so rows stay
/// readable in both appearances.
struct ZenSpaceBackground: View {
    let theme: SpaceTheme?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let theme {
            let strength = theme.opacity * (colorScheme == .dark ? 0.55 : 0.45)
            LinearGradient(colors: gradientColors(theme).map { $0.opacity(strength) },
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    /// A single color still gets a gentle gradient into transparency.
    private func gradientColors(_ theme: SpaceTheme) -> [Color] {
        let colors = theme.colors.map(Color.init)
        return colors.count == 1 ? [colors[0], colors[0].opacity(0.3)] : colors
    }
}
