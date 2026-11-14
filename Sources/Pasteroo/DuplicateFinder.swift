import CryptoKit
import Foundation

/// Files with identical contents, whatever their names. `files[0]` is the one to keep.
struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let files: [FoundItem]
    var size: Int64 { files.first?.size ?? 0 }
    /// Bytes freed by removing every copy but the first.
    var wasted: Int64 { size * Int64(files.count - 1) }
    var keep: FoundItem { files[0] }
    var copies: ArraySlice<FoundItem> { files.dropFirst() }
}

/// Finds byte-identical files. Names are ignored on purpose: recovered photos come back as IMG_0001.JPG and f1234.jpg.
enum DuplicateFinder {
    static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "psd",
        "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf",
        "mov", "mp4", "m4v", "avi", "mts", "3gp",
    ]

    enum Phase: Sendable { case listing(Int), comparing(Int, Int) }

    /// Groups identical files under `roots`. Size first, then a hash of the first chunk,
    /// then a hash of the whole file, so most files are never read in full.
    static func find(under roots: [URL], mediaOnly: Bool, progress: @escaping @Sendable (Phase) -> Void) -> [DuplicateGroup] {
        var listed = 0
        let files = DiskScanner.files(under: roots) { url in
            listed += 1
            if listed % 500 == 0 { progress(.listing(listed)) }
            return !mediaOnly || mediaExtensions.contains(url.pathExtension.lowercased())
        }
        return group(files, progress: progress)
    }

    static func group(_ files: [FoundItem], progress: @escaping @Sendable (Phase) -> Void = { _ in }) -> [DuplicateGroup] {
        let bySize = Dictionary(grouping: files.filter { $0.size > 0 }, by: \.size).values.filter { $0.count > 1 }
        let candidates = bySize.flatMap { $0 }
        var done = 0
        var groups: [DuplicateGroup] = []
        for sameSize in bySize {
            if Task.isCancelled { return groups }
            let byHead = Dictionary(grouping: sameSize) { hash($0.url, limit: 128 * 1024) ?? "" }
            for (head, sameHead) in byHead where !head.isEmpty && sameHead.count > 1 {
                let byFull = Dictionary(grouping: sameHead) { hash($0.url) ?? "" }
                for (full, identical) in byFull where !full.isEmpty && identical.count > 1 {
                    groups.append(DuplicateGroup(id: full, files: identical.sorted(by: keepFirst)))
                }
            }
            done += sameSize.count
            progress(.comparing(done, candidates.count))
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    /// The oldest file is the original; on a tie the shorter path, which is usually the tidier place.
    static func keepFirst(_ a: FoundItem, _ b: FoundItem) -> Bool {
        a.date != b.date ? a.date < b.date : a.url.path.count < b.url.path.count
    }

    private static func hash(_ url: URL, limit: Int? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var left = limit ?? .max
        while left > 0, let chunk = try? handle.read(upToCount: min(left, 1 << 20)), !chunk.isEmpty {
            hasher.update(data: chunk)
            left -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
