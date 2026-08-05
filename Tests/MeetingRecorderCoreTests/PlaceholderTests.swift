import XCTest
@testable import MeetingRecorderCore

final class PlaceholderTests: XCTestCase {
    func test_placeholderMessage() {
        XCTAssertEqual(Placeholder.message, "MeetingRecorderCore scaffold OK")
    }
}
