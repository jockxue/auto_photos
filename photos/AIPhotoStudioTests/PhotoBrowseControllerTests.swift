import Photos
import XCTest
@testable import AIPhotoStudio

final class PhotoBrowseControllerTests: XCTestCase {
    func testSwipeNextAndPreviousStayInsideBounds() {
        var browser = PhotoBrowseController(identifiers: ["a", "b", "c"], index: 0)
        browser.showPrevious()
        XCTAssertEqual(browser.index, 0)
        browser.showNext()
        XCTAssertEqual(browser.index, 1)
        browser.index = 2
        browser.showNext()
        XCTAssertEqual(browser.index, 2)
        browser.showPrevious()
        XCTAssertEqual(browser.index, 1)
    }

    func testDeletingMiddlePhotoShowsTheNextOne() {
        var browser = PhotoBrowseController(identifiers: ["a", "b", "c"], index: 1)
        XCTAssertEqual(browser.startDeleting(), "b")
        browser.noteDeleteSucceeded(identifier: "b")
        XCTAssertEqual(browser.identifiers, ["a", "c"])
        XCTAssertEqual(browser.index, 1)
        XCTAssertFalse(browser.isDeleting)
    }

    func testDeletingLastPhotoShowsThePreviousOne() {
        var browser = PhotoBrowseController(identifiers: ["a", "b"], index: 1)
        XCTAssertEqual(browser.startDeleting(), "b")
        browser.noteDeleteSucceeded(identifier: "b")
        XCTAssertEqual(browser.identifiers, ["a"])
        XCTAssertEqual(browser.index, 0)
    }

    func testDeletingTheOnlyPhotoShowsEmptyState() {
        var browser = PhotoBrowseController(identifiers: ["a"], index: 0)
        XCTAssertEqual(browser.startDeleting(), "a")
        browser.noteDeleteSucceeded(identifier: "a")
        XCTAssertTrue(browser.isEmpty)
        XCTAssertNil(browser.positionText)
    }

    func testSecondDeleteWhileInProgressIsIgnored() {
        var browser = PhotoBrowseController(identifiers: ["a", "b"], index: 0)
        XCTAssertEqual(browser.startDeleting(), "a")
        XCTAssertNil(browser.startDeleting())
        browser.showNext()
        XCTAssertEqual(browser.index, 0)
        XCTAssertEqual(browser.identifiers, ["a", "b"])
    }

    func testDeleteFailureKeepsThePhoto() {
        var browser = PhotoBrowseController(identifiers: ["a", "b"], index: 0)
        XCTAssertEqual(browser.startDeleting(), "a")
        browser.noteDeleteFailed("denied")
        XCTAssertEqual(browser.identifiers, ["a", "b"])
        XCTAssertEqual(browser.lastError, "denied")
        XCTAssertFalse(browser.isDeleting)
        XCTAssertEqual(browser.startDeleting(), "a")
    }

    func testSelectingAPhotoMovesToThatIndex() {
        var browser = PhotoBrowseController(identifiers: ["a", "b", "c"], index: 0)
        browser.show(at: 2)
        XCTAssertEqual(browser.index, 2)
        browser.show(at: 9)
        XCTAssertEqual(browser.index, 2)
        _ = browser.startDeleting()
        browser.show(at: 0)
        XCTAssertEqual(browser.index, 2)
    }

    func testDeniedAccessNeedsAPrompt() {
        XCTAssertTrue(PhotoLibraryAccess.needsPrompt(for: .denied))
        XCTAssertTrue(PhotoLibraryAccess.needsPrompt(for: .restricted))
        XCTAssertTrue(PhotoLibraryAccess.needsPrompt(for: .notDetermined))
        XCTAssertFalse(PhotoLibraryAccess.needsPrompt(for: .authorized))
        XCTAssertFalse(PhotoLibraryAccess.needsPrompt(for: .limited))
    }
}
