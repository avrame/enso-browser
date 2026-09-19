// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ZenSpacesKit

final class FaviconDataURLTests: XCTestCase {
    func testLargeImageIsShrunkToAPNG() throws {
        let jpeg = try image(width: 256, height: 256, type: .jpeg)
        let icon = try XCTUnwrap(FaviconDataURL.encode(jpeg, mimeType: "image/jpeg"))
        XCTAssertTrue(icon.hasPrefix("data:image/png;base64,"))
        let size = try pixelSize(of: icon)
        XCTAssertEqual(size.width, 64)
        XCTAssertEqual(size.height, 64)
    }

    func testSmallImageKeepsItsSize() throws {
        let icon = try XCTUnwrap(FaviconDataURL.encode(try image(width: 16, height: 16, type: .png), mimeType: nil))
        let size = try pixelSize(of: icon)
        XCTAssertEqual(size.width, 16)
    }

    func testSVGPassesThroughByMimeTypeOrContent() throws {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>"#.utf8)
        XCTAssertEqual(FaviconDataURL.encode(svg, mimeType: "image/svg+xml"),
                       "data:image/svg+xml;base64," + svg.base64EncodedString())
        XCTAssertEqual(FaviconDataURL.encode(Data("<?xml version=\"1.0\"?>\n".utf8) + svg, mimeType: "text/plain")?
                        .hasPrefix("data:image/svg+xml;base64,"), true)
    }

    func testRejectsOversizedSVGAndNonImages() {
        let huge = Data("<svg>".utf8) + Data(repeating: 0x20, count: FaviconDataURL.maxSVGBytes)
        XCTAssertNil(FaviconDataURL.encode(huge, mimeType: "image/svg+xml"))
        XCTAssertNil(FaviconDataURL.encode(Data("<!doctype html><html></html>".utf8), mimeType: "text/html"))
        XCTAssertNil(FaviconDataURL.encode(Data(), mimeType: "image/png"))
    }

    // MARK: Helpers

    private func image(width: Int, height: Int, type: UTType) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil,
                                              width: width,
                                              height: height,
                                              bitsPerComponent: 8,
                                              bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixelSize(of dataURL: String) throws -> (width: Int, height: Int) {
        let base64 = try XCTUnwrap(dataURL.split(separator: ",").last)
        let data = try XCTUnwrap(Data(base64Encoded: String(base64)))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }
}
