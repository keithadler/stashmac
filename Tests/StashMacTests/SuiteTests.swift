import XCTest
@testable import StashMac

final class SuiteTests: XCTestCase {
    @MainActor private func runSuite(_ name: String) {
        let results = TestKit.run(filter: name + "/")
        XCTAssertFalse(results.isEmpty)
        for r in results { for f in r.failures { XCTFail("\(r.suite)/\(r.name): \(f)") } }
    }
    @MainActor func testKey() { runSuite("Key") }
    @MainActor func testChunk() { runSuite("Chunk") }
    @MainActor func testBackup() { runSuite("Backup") }
}
