// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import MozillaAppServices
import Shared
import Storage
import UIKit
import XCTest

@testable import Client

@MainActor
final class BookmarksViewControllerDropTests: XCTestCase {
    private var profile: MockProfile!

    /// The fixture puts the folder first and the bookmark second, matching the order
    /// `MockBookmarksHandler` returns them in.
    private let folderRow = 0
    private let bookmarkRow = 1

    override func setUp() async throws {
        try await super.setUp()
        profile = makeProfile()
        DependencyHelperMock().bootstrapDependencies(injectedProfile: profile)
    }

    override func tearDown() async throws {
        profile = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }
    func testCanDrop_bookmarkOntoFolder_isAllowed() {
        let bookmark = MockBookmarkNode(title: "Firefox", type: .bookmark, guid: "b1")
        let folder = MockBookmarkNode(title: "Reading", type: .folder, guid: "f1")

        XCTAssertTrue(BookmarksViewController.canDrop(bookmark, onto: folder))
    }

    func testCanDrop_folderOntoFolder_isAllowed() {
        let source = MockBookmarkNode(title: "Recipes", type: .folder, guid: "f1")
        let destination = MockBookmarkNode(title: "Reading", type: .folder, guid: "f2")

        XCTAssertTrue(BookmarksViewController.canDrop(source, onto: destination))
    }

    func testCanDrop_ontoBookmark_isRejected() {
        let bookmark = MockBookmarkNode(title: "Firefox", type: .bookmark, guid: "b1")
        let destination = MockBookmarkNode(title: "Mozilla", type: .bookmark, guid: "b2")

        XCTAssertFalse(BookmarksViewController.canDrop(bookmark, onto: destination))
    }

    func testCanDrop_ontoItself_isRejected() {
        let folder = MockBookmarkNode(title: "Reading", type: .folder, guid: "f1")

        XCTAssertFalse(BookmarksViewController.canDrop(folder, onto: folder))
    }

    func testCanDrop_ontoSeparator_isRejected() {
        let bookmark = MockBookmarkNode(title: "Firefox", type: .bookmark, guid: "b1")
        let separator = MockBookmarkNode(title: "", type: .separator, guid: "s1")

        XCTAssertFalse(BookmarksViewController.canDrop(bookmark, onto: separator))
        XCTAssertFalse(BookmarksViewController.canDrop(separator, onto: bookmark))
    }

    /// The aggregate "Desktop Bookmarks" row is a folder by type, but its guid is local and
    /// never synced - re-parenting onto it would save a bookmark under a parent that does
    /// not exist on the server.
    func testCanDrop_ontoLocalDesktopFolderRow_isRejected() {
        let bookmark = MockBookmarkNode(title: "Firefox", type: .bookmark, guid: "b1")
        let desktopRow = LocalDesktopFolder()

        XCTAssertEqual(desktopRow.type, .folder)
        XCTAssertFalse(BookmarksViewController.canDrop(bookmark, onto: desktopRow))
    }

    /// The rows inside that aggregate are the same class but carry real root guids, so they
    /// remain valid destinations. Excluding by type would have taken these with it.
    func testCanDrop_ontoDesktopRootFolders_isAllowed() {
        let bookmark = MockBookmarkNode(title: "Firefox", type: .bookmark, guid: "b1")

        for guid in [BookmarkRoots.MenuFolderGUID,
                     BookmarkRoots.ToolbarFolderGUID,
                     BookmarkRoots.UnfiledFolderGUID] {
            let folder = LocalDesktopFolder(forcedGuid: guid)
            XCTAssertTrue(BookmarksViewController.canDrop(bookmark, onto: folder),
                          "Expected \(guid) to accept a drop")
        }
    }

    // MARK: - Drop hint rendering

    /// The hint is the whole point of the change: eligible folders have to look different
    /// from everything else while a drag is in flight, and identical once it ends.
    @MainActor
    func testDropHint_tintsEligibleFolderOnly() throws {
        let controller = try makeController()
        let tableView = try XCTUnwrap(controller.tableView)

        let draggedBookmark = try XCTUnwrap(controller.viewModel.displayedBookmarkNodes[safe: bookmarkRow])
        controller.setDropHintsActive(true, draggedNode: draggedBookmark)

        let folderCell = controller.tableView(tableView, cellForRowAt: IndexPath(row: folderRow, section: 0))
        let bookmarkCell = controller.tableView(tableView, cellForRowAt: IndexPath(row: bookmarkRow, section: 0))

        XCTAssertNotEqual(folderCell.backgroundColor,
                          bookmarkCell.backgroundColor,
                          "An eligible folder should stand out from the row being dragged")
    }

    @MainActor
    func testDropHint_clearsWhenDragEnds() throws {
        let controller = try makeController()
        let tableView = try XCTUnwrap(controller.tableView)
        let folderPath = IndexPath(row: folderRow, section: 0)
        let bookmarkPath = IndexPath(row: bookmarkRow, section: 0)

        let restingFolderColor = controller.tableView(tableView, cellForRowAt: folderPath).backgroundColor

        let draggedBookmark = try XCTUnwrap(controller.viewModel.displayedBookmarkNodes[safe: bookmarkRow])
        controller.setDropHintsActive(true, draggedNode: draggedBookmark)
        XCTAssertNotEqual(controller.tableView(tableView, cellForRowAt: folderPath).backgroundColor,
                          restingFolderColor)

        controller.setDropHintsActive(false)
        XCTAssertNil(controller.draggedNode)
        XCTAssertEqual(controller.tableView(tableView, cellForRowAt: folderPath).backgroundColor,
                       restingFolderColor)
        XCTAssertEqual(controller.tableView(tableView, cellForRowAt: folderPath).backgroundColor,
                       controller.tableView(tableView, cellForRowAt: bookmarkPath).backgroundColor)
    }

    // MARK: - Helpers

    private func makeController() throws -> BookmarksViewController {
        let viewModel = BookmarksPanelViewModel(
            profile: profile,
            bookmarksHandler: MockBookmarksHandler(folderData: folderContainingAFolderAndABookmark()),
            bookmarkFolderGUID: BookmarkRoots.MobileFolderGUID,
            quickActions: MockQuickActions()
        )

        let loaded = expectation(description: "Bookmarks loaded")
        viewModel.reloadData { loaded.fulfill() }
        wait(for: [loaded], timeout: 1)

        let controller = BookmarksViewController(viewModel: viewModel, windowUUID: .XCTestDefaultUUID)
        trackForMemoryLeaks(controller)
        controller.loadViewIfNeeded()

        XCTAssertEqual(viewModel.displayedBookmarkNodes.count, 2)
        XCTAssertEqual(viewModel.displayedBookmarkNodes[safe: folderRow]?.type, .folder)
        XCTAssertEqual(viewModel.displayedBookmarkNodes[safe: bookmarkRow]?.type, .bookmark)
        return controller
    }

    private func folderContainingAFolderAndABookmark() -> BookmarkFolderData {
        let timestamp = Int64(Date().toTimestamp())
        let folder = BookmarkFolderData(
            guid: "f1",
            dateAdded: timestamp,
            lastModified: timestamp,
            parentGUID: BookmarkRoots.MobileFolderGUID,
            position: 0,
            title: "Reading",
            childGUIDs: [],
            children: nil
        )
        let bookmark = BookmarkItemData(
            guid: "b1",
            dateAdded: timestamp,
            lastModified: timestamp,
            parentGUID: BookmarkRoots.MobileFolderGUID,
            position: 1,
            url: "https://www.firefox.com",
            title: "Firefox"
        )
        return BookmarkFolderData(
            guid: BookmarkRoots.MobileFolderGUID,
            dateAdded: timestamp,
            lastModified: timestamp,
            parentGUID: BookmarkRoots.RootGUID,
            position: 0,
            title: "Mobile Bookmarks",
            childGUIDs: ["f1", "b1"],
            children: [folder, bookmark]
        )
    }
}

// Unchecked sendable because BookmarkNodeType in rust components is not Sendable (FXIOS-12903).
private final class MockBookmarkNode: @unchecked Sendable, FxBookmarkNode {
    let type: BookmarkNodeType
    let guid: String
    let parentGUID: String?
    let position: UInt32
    let isRoot: Bool
    let title: String

    init(
        title: String,
        type: BookmarkNodeType = .bookmark,
        guid: String = "12345",
        parentGUID: String? = nil,
        position: UInt32 = 0,
        isRoot: Bool = false
    ) {
        self.title = title
        self.type = type
        self.guid = guid
        self.parentGUID = parentGUID
        self.position = position
        self.isRoot = isRoot
    }
}
