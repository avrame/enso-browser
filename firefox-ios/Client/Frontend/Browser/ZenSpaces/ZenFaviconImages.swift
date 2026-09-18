// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftDraw
import UIKit
import ZenSpacesKit

/// Decodes Zen's `data:` favicons (PNG, ICO and SVG) once per appearance.
@MainActor
enum ZenFaviconImages {
    enum Tone {
        case light
        case dark
        case mixed
    }

    final class Favicon {
        let image: UIImage
        let tone: Tone

        init(image: UIImage, tone: Tone) {
            self.image = image
            self.tone = tone
        }
    }

    private static let renderSize = CGSize(width: 64, height: 64)
    private static let cache: NSCache<NSString, Favicon> = {
        let cache = NSCache<NSString, Favicon>()
        cache.countLimit = 500
        return cache
    }()
    private static let undecodable = NSCache<NSString, NSNull>()

    static func favicon(for icon: String, dark: Bool) -> Favicon? {
        let key = "\(dark ? "d" : "l"):\(icon)" as NSString
        if let favicon = cache.object(forKey: key) { return favicon }
        if undecodable.object(forKey: key) != nil { return nil }

        guard let uri = DataURI(icon), let image = decode(uri, dark: dark) else {
            undecodable.setObject(NSNull(), forKey: key)
            return nil
        }
        let favicon = Favicon(image: image, tone: tone(of: image))
        cache.setObject(favicon, forKey: key)
        return favicon
    }

    private static func decode(_ uri: DataURI, dark: Bool) -> UIImage? {
        guard uri.isSVG else { return UIImage(data: uri.data) }
        let source = String(decoding: uri.data, as: UTF8.self)
        let resolved = Data(SVGColorScheme.resolve(source, dark: dark).utf8)
        return SVG(data: resolved)?.rasterize(size: renderSize)
    }

    /// Whether the visible pixels are nearly all light or all dark, i.e.
    /// the icon would vanish on a background of the same tone.
    private static func tone(of image: UIImage) -> Tone {
        guard let cgImage = image.cgImage else { return .mixed }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: side,
                                          height: side,
                                          bitsPerComponent: 8,
                                          bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .mixed }

        var luminance = 0.0
        var coverage = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.1 else { continue }
            let red = Double(pixels[offset]) / 255 / alpha
            let green = Double(pixels[offset + 1]) / 255 / alpha
            let blue = Double(pixels[offset + 2]) / 255 / alpha
            luminance += (0.2126 * red + 0.7152 * green + 0.0722 * blue) * alpha
            coverage += alpha
        }
        guard coverage > 0 else { return .mixed }
        let average = luminance / coverage
        if average > 0.85 { return .light }
        if average < 0.15 { return .dark }
        return .mixed
    }
}
