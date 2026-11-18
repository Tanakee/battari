import SwiftData
import XCTest
@testable import BATTARI

final class ValidationTests: XCTestCase {
    func testStudentId() {
        XCTAssertEqual(Validation.studentId("  s2301234 "), .valid("s2301234"))
        XCTAssertEqual(Validation.studentId(""), .empty)
        XCTAssertEqual(Validation.studentId("   "), .empty)
        XCTAssertEqual(Validation.studentId("s23-01"), .format)
        XCTAssertEqual(Validation.studentId("ｓ２３"), .format, "全角は不可")
        XCTAssertEqual(Validation.studentId(String(repeating: "a", count: 21)), .format)
        XCTAssertEqual(Validation.studentEmail("S2301234"), "s2301234@s.asojuku.ac.jp")
    }

    func testDisplayNameAndOtp() {
        XCTAssertEqual(Validation.displayName("  たなか  "), "たなか")
        XCTAssertNil(Validation.displayName("   "))
        XCTAssertTrue(Validation.isOtp("012345"))
        XCTAssertFalse(Validation.isOtp("12345"))
        XCTAssertFalse(Validation.isOtp("１２３４５６"), "全角数字は不可")
        XCTAssertEqual(Validation.truncated("あいうえお", to: 3), "あいう")
    }

    func testFormat() {
        XCTAssertEqual(Format.stickerCount(12), "12")
        XCTAssertEqual(Format.stickerCount(9999), "9999")
        XCTAssertEqual(Format.stickerCount(10_000), "9999+")
    }
}

final class StickerLayoutTests: XCTestCase {
    func testFirstStickerGoesToCenter() {
        let p = StickerLayout.freePosition(existing: [])
        XCTAssertEqual(p.x, 0.5)
        XCTAssertEqual(p.y, 0.5)
    }

    func testFreePositionAvoidsExistingAndStaysOnLid() {
        let existing = [(x: 0.5, y: 0.5), (x: 0.2, y: 0.2)]
        let p = StickerLayout.freePosition(existing: existing)
        XCTAssertTrue((StickerLayout.minX...StickerLayout.maxX).contains(p.x))
        XCTAssertTrue((StickerLayout.minY...StickerLayout.maxY).contains(p.y))
        for e in existing {
            XCTAssertGreaterThan(hypot(e.x - p.x, (e.y - p.y) / StickerLayout.lidAspect), StickerLayout.stickerSize)
        }
    }

    func testClamp() {
        let p = StickerLayout.clamp(x: -1, y: 2)
        XCTAssertEqual(p.x, StickerLayout.minX)
        XCTAssertEqual(p.y, StickerLayout.maxY)
    }
}

@MainActor
final class StickerStoreTests: XCTestCase {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: MyProfile.self, Sticker.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func payload(_ uid: String, name: String = "あいう") -> ProfilePayload {
        ProfilePayload(uid: uid, displayName: name, department: "情報工学科", grade: 2, message: "")
    }

    func testSaveAssignsTopZIndexAndKeepsInCollection() throws {
        let ctx = try context()
        let a = try StickerStore.saveReceived(payload("a"), icon: Data([1]), in: ctx)
        let b = try StickerStore.saveReceived(payload("b"), icon: Data([2]), in: ctx)
        XCTAssertEqual(a.zIndex, 1)
        XCTAssertEqual(b.zIndex, 2)
        XCTAssertTrue((-15...15).contains(b.rotation))
        XCTAssertFalse(a.isPlaced, "貼るかどうかはG7で決める")
    }

    func testReExchangeOverwritesSamePartner() throws {
        let ctx = try context()
        try StickerStore.saveReceived(payload("a", name: "旧"), icon: Data([1]), in: ctx)
        try StickerStore.saveReceived(payload("b"), icon: Data([2]), in: ctx)
        let again = try StickerStore.saveReceived(payload("a", name: "新"), icon: Data([3]), in: ctx)
        let all = try ctx.fetch(FetchDescriptor<Sticker>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(again.displayName, "新")
        XCTAssertEqual(again.iconImage, Data([3]))
        XCTAssertEqual(again.zIndex, 3, "最前面に出す")
    }

    func testReExchangeKeepsPlacedSticker() throws {
        let ctx = try context()
        let a = try StickerStore.saveReceived(payload("a"), icon: Data([1]), in: ctx)
        StickerStore.place(a, x: 0.3, y: 0.4, in: ctx)
        let again = try StickerStore.saveReceived(payload("a"), icon: Data([2]), in: ctx)
        XCTAssertTrue(again.isPlaced)
        XCTAssertEqual(again.positionX, 0.3, accuracy: 1e-9, "貼っていた位置はそのまま")
    }

    func testPlaceBringsToFront() throws {
        let ctx = try context()
        let a = try StickerStore.saveReceived(payload("a"), icon: Data([1]), in: ctx)
        try StickerStore.saveReceived(payload("b"), icon: Data([2]), in: ctx)
        StickerStore.place(a, x: 0.3, y: 0.4, in: ctx)
        XCTAssertEqual(a.zIndex, 3)
        XCTAssertEqual(a.positionX, 0.3, accuracy: 1e-9)
        XCTAssertTrue(a.isPlaced)
    }

    func testUnplaceKeepsStickerAndDeleteRemovesIt() throws {
        let ctx = try context()
        let a = try StickerStore.saveReceived(payload("a"), icon: Data([1]), in: ctx)
        StickerStore.placeAtFreeSpot(a, in: ctx)
        XCTAssertTrue(a.isPlaced)
        StickerStore.unplace(a, in: ctx)
        XCTAssertFalse(a.isPlaced)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Sticker>()).count, 1)
        StickerStore.delete(a, in: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Sticker>()).count, 0)
    }

    func testFreeSpotIgnoresUnplacedStickers() throws {
        let ctx = try context()
        let a = try StickerStore.saveReceived(payload("a"), icon: Data([1]), in: ctx)
        let b = try StickerStore.saveReceived(payload("b"), icon: Data([2]), in: ctx)
        // どちらも貼っていないので、空いている位置の計算では同じ候補になる（ずらしの分だけ違う）
        XCTAssertEqual(a.positionX, b.positionX, accuracy: 0.061)
        XCTAssertEqual(a.positionY, b.positionY, accuracy: 0.061)
    }
}
