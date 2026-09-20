// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// The extension packages kept on disk. Each entry is a `.xpi`/`.zip`
/// package or an unpacked directory, and its file name is the stable
/// identifier a `WKWebExtensionContext` is loaded under.
enum ZenExtensionStore {
    static var directory: URL {
        get throws {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
            let directory = support.appendingPathComponent("ZenExtensions", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static func packages() throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(at: try directory,
                                                                   includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])
        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies `url` into the store, replacing a package of the same name.
    /// `url` may be security scoped, as it is when it comes from Files.
    static func add(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let destination = try directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    static func remove(_ package: URL) throws {
        try FileManager.default.removeItem(at: package)
    }

    /// The identifier a package is loaded under: its name without the
    /// packaging extension.
    static func identifier(of package: URL) -> String {
        let name = package.lastPathComponent
        let packaging = ["xpi", "zip", "crx"]
        return packaging.contains(package.pathExtension.lowercased())
            ? package.deletingPathExtension().lastPathComponent
            : name
    }
}
