import XCTest
@testable import Pasteroo

/// The duplicate finder decides what gets ticked for the Trash, so its grouping and its "keep" choice are tested.
final class DuplicateFinderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func write(_ name: String, _ bytes: [UInt8], date: Date) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func testIdenticalContentsGroupRegardlessOfName() throws {
        let photo = [UInt8](repeating: 7, count: 300_000)
        let original = try write("IMG_0001.JPG", photo, date: Date(timeIntervalSince1970: 1_000))
        let recovered = try write("f0123456.jpg", photo, date: Date())
        // Same size, different bytes past the first chunk: must not be grouped.
        var other = photo; other[299_999] = 8
        _ = try write("IMG_0002.JPG", other, date: Date())
        _ = try write("notes.txt", [1, 2, 3], date: Date())

        let groups = DuplicateFinder.find(under: [dir], mediaOnly: true) { _ in }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.url.lastPathComponent)), [original.lastPathComponent, recovered.lastPathComponent])
        XCTAssertEqual(groups[0].keep.url.lastPathComponent, "IMG_0001.JPG", "the oldest copy is the one to keep")
        XCTAssertEqual(groups[0].copies.map(\.url.lastPathComponent), ["f0123456.jpg"])
        XCTAssertEqual(groups[0].wasted, 300_000)

        XCTAssertTrue(DuplicateFinder.find(under: [dir], mediaOnly: false) { _ in }.contains { $0.files.count == 2 })
    }

    func testArtifactsAndInstallersAreFoundWithoutDescending() throws {
        let project = dir.appendingPathComponent("app/node_modules/left-pad", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: project.appendingPathComponent("index.js"))
        try Data([1]).write(to: dir.appendingPathComponent("Setup.dmg"))
        try Data([1]).write(to: dir.appendingPathComponent("photo.jpg"))
        // "build" is only an artifact next to a project file; a plain folder called build is someone's work.
        for folder in ["Clienti/build", "rust/target"] {
            let url = dir.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data([1]).write(to: url.appendingPathComponent("x"))
        }
        try Data().write(to: dir.appendingPathComponent("rust/Cargo.toml"))

        XCTAssertEqual(Set(DiskScanner.artifacts(under: [dir]).map(\.name)), ["node_modules", "target"])
        XCTAssertEqual(DiskScanner.installers(under: [dir]).map(\.name), ["Setup.dmg"])
    }
}
