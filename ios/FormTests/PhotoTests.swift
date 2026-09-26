import UIKit
import XCTest
@testable import Form

@MainActor
final class PhotoTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
    }

    private func photo(daysAgo: Int, kg: Double? = nil) -> ProgressPhoto {
        ProgressPhoto(id: UUID(), storagePath: "u/x.jpg",
                      takenAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!, bodyWeightKg: kg)
    }

    func testAddSavesOfflineThenUploads() async {
        let repo = MockPhotoRepository()
        repo.failUploads = true
        let store = PhotoStore(repository: repo, directory: tempDir())
        let added = await store.add(image(), bodyWeightKg: 78.4)
        XCTAssertNotNil(added)
        XCTAssertEqual(store.photos.count, 1, "visible immediately")
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertTrue(added!.storagePath.hasPrefix("demo/"), "stored under the user's folder")

        repo.failUploads = false
        await store.sync()
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(repo.photos.first?.bodyWeightKg, 78.4)
        XCTAssertNotNil(repo.files[added!.storagePath])
    }

    func testQueueSurvivesRelaunch() async {
        let repo = MockPhotoRepository()
        repo.failUploads = true
        let dir = tempDir()
        let store = PhotoStore(repository: repo, directory: dir)
        await store.add(image())
        let relaunched = PhotoStore(repository: repo, directory: dir)
        XCTAssertEqual(relaunched.photos.count, 1)
        XCTAssertEqual(relaunched.pendingCount, 1)
    }

    func testThumbnailComesFromLocalFile() async {
        let store = PhotoStore(repository: MockPhotoRepository(), directory: tempDir())
        let added = await store.add(image())!
        let thumb = await store.thumbnail(for: added, maxPixel: 100)
        XCTAssertNotNil(thumb)
        XCTAssertLessThanOrEqual(max(thumb!.size.width, thumb!.size.height), 100)
    }

    func testDeleteRemovesEverywhere() async {
        let repo = MockPhotoRepository()
        let store = PhotoStore(repository: repo, directory: tempDir())
        let added = await store.add(image())!
        await store.delete(added)
        XCTAssertTrue(store.photos.isEmpty)
        XCTAssertTrue(repo.photos.isEmpty)
    }

    func testDayNumbers() {
        let first = photo(daysAgo: 216)
        XCTAssertEqual(PhotoTimeline.dayNumber(of: first, first: first.takenAt), 1)
        XCTAssertEqual(PhotoTimeline.dayNumber(of: photo(daysAgo: 0), first: first.takenAt), 217)
    }

    func testChangeLine() {
        XCTAssertEqual(PhotoTimeline.change(from: photo(daysAgo: 112, kg: 78.4), to: photo(daysAgo: 0, kg: 73.9)),
                       "−4.5 kg over 16 weeks")
        XCTAssertEqual(PhotoTimeline.change(from: photo(daysAgo: 3), to: photo(daysAgo: 0)), "3 days apart")
    }

    func testByMonthNewestFirst() {
        let groups = PhotoTimeline.byMonth([photo(daysAgo: 70), photo(daysAgo: 0), photo(daysAgo: 1)])
        XCTAssertGreaterThanOrEqual(groups.count, 2)
        XCTAssertGreaterThan(groups[0].month, groups[1].month)
    }

    func testJPEGIsResized() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000),
                                          format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in }
        let data = PhotoStore.jpeg(big)!
        let decoded = UIImage(data: data)!
        XCTAssertEqual(max(decoded.size.width, decoded.size.height), 2000, accuracy: 1)
    }
}
