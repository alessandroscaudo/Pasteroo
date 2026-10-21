import XCTest
@testable import Pasteroo

/// ClipStore is the only code that writes user data: dedup, pins, the Remember limit
/// and the history file must survive a reload.
/// XCTest, not Swift Testing: its macros need Xcode, and the project builds with the Command Line Tools.
@MainActor
final class ClipStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv("PASTEROO_HOME", dir.path, 1)
        UserDefaults.standard.set(3, forKey: Prefs.rememberLimit)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        UserDefaults.standard.removeObject(forKey: Prefs.rememberLimit)
    }

    func testHistoryRulesSurviveReload() {
        let store = ClipStore()
        store.add("a", source: nil)
        store.add("b", source: nil)
        store.add("a", source: nil)
        XCTAssertEqual(store.clips.map(\.text), ["a", "b"])

        store.rename(store.clips[0].id, to: "Home address")
        store.add("b", source: nil)
        store.add("a", source: nil)
        XCTAssertEqual(store.clips[0].name, "Home address")

        store.togglePin(store.clips.first { $0.text == "b" }!.id)
        for text in ["c", "d", "e", "f"] { store.add(text, source: nil) }
        XCTAssertEqual(store.recent.map(\.text), ["f", "e", "d"])
        XCTAssertEqual(store.pinned.map(\.text), ["b"])

        store.saveNow()
        // Dates are saved to the second, so compare what the user sees.
        let reloaded = ClipStore().clips
        XCTAssertEqual(reloaded.map(\.text), store.clips.map(\.text))
        XCTAssertEqual(reloaded.map(\.name), store.clips.map(\.name))
        XCTAssertEqual(reloaded.map(\.isPinned), store.clips.map(\.isPinned))
    }

    func testUnreadableHistoryIsKeptAside() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("history.json"))

        XCTAssertTrue(ClipStore().clips.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("history-broken-") })
        XCTAssertFalse(files.contains("history.json"))
    }
}
