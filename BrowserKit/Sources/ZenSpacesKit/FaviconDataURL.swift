// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns downloaded favicon bytes into the `data:` URL form Zen syncs
/// (ZenSpacesSyncModel.syncableIconUrl drops remote icon URLs).
public enum FaviconDataURL {
    /// Keeps records small; Zen shows favicons at 16pt.
    public static let maxPixelSize = 64
    public static let maxSVGBytes = 32 * 1024

    /// Nil when the bytes are not an image this can use.
    public static func encode(_ data: Data, mimeType: String?) -> String? {
        guard !data.isEmpty else { return nil }
        if isSVG(data, mimeType: mimeType) {
            guard data.count <= maxSVGBytes else { return nil }
            return "data:image/svg+xml;base64," + data.base64EncodedString()
        }
        guard let png = pngThumbnail(data) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    private static func isSVG(_ data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("svg") == true { return true }
        let head = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return head.hasPrefix("<svg") || (head.hasPrefix("<?xml") && head.contains("<svg"))
    }

    /// The largest frame (ICO files hold several), scaled to fit
    /// `maxPixelSize` and re-encoded as PNG.
    private static func pngThumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        let index = largestFrame(in: source)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func largestFrame(in source: CGImageSource) -> Int {
        var best = 0
        var bestWidth = 0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if width > bestWidth {
                best = index
                bestWidth = width
            }
        }
        return best
    }
}
