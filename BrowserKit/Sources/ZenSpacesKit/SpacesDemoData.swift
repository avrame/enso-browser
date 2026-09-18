// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Generated records in Zen's wire format, for exercising the UI with more
/// spaces than a real account has. Never uploaded anywhere.
public enum SpacesDemoData {
    private static let icons = ["🏠", "💼", "🎨", "📚", "🧪", "🎮", "✈️", "🍳", "🎵", "🏃", "💡", "🛠️"]
    /// Some two- and three-color gradients; every fourth space has none.
    private static let palettes: [[[Int]]] = [
        [[65, 195, 241], [74, 65, 241], [64, 242, 145]],
        [[227, 161, 130], [211, 227, 130], [227, 130, 181]],
        [[77, 116, 178]],
        [],
    ]
    private static let sites = [
        ("https://www.wikipedia.org/", "Wikipedia"),
        ("https://news.ycombinator.com/", "Hacker News"),
        ("https://developer.apple.com/", "Apple Developer"),
        ("https://www.mozilla.org/", "Mozilla"),
        ("https://github.com/", "GitHub"),
        ("https://www.openstreetmap.org/", "OpenStreetMap"),
    ]

    public static func records(spaceCount: Int, tabsPerSpace: Int = 4) -> [SpacesRecord] {
        var records: [SpacesRecord] = []
        var spaceIds: [String] = []

        for index in 0..<spaceCount {
            let spaceId = "{demo-space-\(index)}"
            spaceIds.append(spaceId)
            let folderId = "demo-folder-\(index)"
            let tabIds = (0..<tabsPerSpace).map { "demo-tab-\(index)-\($0)" }

            let icon: Any = index.isMultiple(of: 3) ? NSNull() : icons[index % icons.count]
            let name = index == 1 ? "A space with a very long name that will not fit" : "Space \(index + 1)"
            let colors = palettes[index % palettes.count].enumerated().map { position, rgb in
                ["c": rgb, "isPrimary": position == 0, "isCustom": false] as [String: Any]
            }
            records.append(record(spaceId, kind: "space", data: [
                "uuid": spaceId, "name": name, "icon": icon,
                "theme": ["type": "gradient", "gradientColors": colors, "opacity": 0.5, "texture": 0],
                "children": [folderId] + tabIds.dropFirst(),
            ]))
            records.append(record(folderId, kind: "folder", data: [
                "folderId": folderId, "name": "Folder \(index + 1)",
                "workspaceUuid": spaceId, "children": [tabIds[0]],
            ]))
            for (position, tabId) in tabIds.enumerated() {
                let (url, title) = sites[(index + position) % sites.count]
                records.append(record(tabId, kind: "tab", data: [
                    "tabId": tabId, "url": url, "title": "\(title) (\(index + 1).\(position + 1))",
                    "pinned": true, "workspaceUuid": spaceId,
                    "folderId": position == 0 ? folderId : NSNull(),
                ]))
            }
        }
        let essentialIds = ["demo-essential-0", "demo-essential-1"]
        for (position, tabId) in essentialIds.enumerated() {
            let (url, title) = sites[position]
            records.append(record(tabId, kind: "tab", data: [
                "tabId": tabId, "url": url, "title": title, "essential": true, "pinned": true,
            ]))
        }
        records.append(record("layout", kind: "layout", data: [
            "spaces": spaceIds, "essentials": ["default": essentialIds],
        ]))
        return records
    }

    private static func record(_ id: String, kind: String, data: [String: Any]) -> SpacesRecord {
        let cleartext = (try? JSONSerialization.data(withJSONObject: ["id": id, "kind": kind, "data": data])) ?? Data()
        return SpacesRecord(id: id, modified: Date(), cleartext: cleartext)
    }
}
