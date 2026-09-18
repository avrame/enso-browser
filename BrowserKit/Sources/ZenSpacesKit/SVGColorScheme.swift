// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Resolves `@media (prefers-color-scheme: …)` blocks in an SVG's CSS for
/// one appearance, since SVG renderers without media query support apply
/// every block and the dark overrides win even in light mode.
public enum SVGColorScheme {
    public static func resolve(_ svg: String, dark: Bool) -> String {
        guard svg.contains("prefers-color-scheme") else { return svg }
        var output = ""
        var rest = Substring(svg)
        while let media = rest.range(of: "@media") {
            output += rest[..<media.lowerBound]
            guard let open = rest[media.upperBound...].firstIndex(of: "{"),
                  let close = matchingBrace(in: rest, from: open)
            else {
                output += rest[media.lowerBound...]
                return output
            }
            let query = rest[media.upperBound..<open].lowercased().filter { !$0.isWhitespace }
            let body = rest[rest.index(after: open)..<close]
            if query.contains("prefers-color-scheme:dark") {
                if dark { output += body }
            } else if query.contains("prefers-color-scheme:light") {
                if !dark { output += body }
            } else {
                output += rest[media.lowerBound...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }

    private static func matchingBrace(in text: Substring, from open: Substring.Index) -> Substring.Index? {
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }
}
