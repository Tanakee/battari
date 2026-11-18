import XCTest
@testable import BATTARI

final class ExchangeMessageTests: XCTestCase {
    private let preview = ProfilePreview(token: "0A1B2C", displayName: "さとう みく", department: "情報システム専攻科", grade: 2)
    private let payload = ProfilePayload(uid: "uid-123", displayName: "さとう みく", department: "情報システム専攻科",
                                         grade: 2, message: "よろしく！")

    func testRoundTrip() throws {
        let icon = Data((0..<20_000).map { UInt8($0 % 251) })
        let messages: [ExchangeMessage] = [
            .hello(preview, thumbnail: Data([1, 2, 3])), .accept, .decline, .profile(payload, icon: icon),
        ]
        for message in messages {
            XCTAssertEqual(try ExchangeMessage.decode(try message.encoded()), message)
        }
    }

    func testMalformed() {
        XCTAssertThrowsError(try ExchangeMessage.decode(Data([9, 0, 0, 0, 0])))
        XCTAssertThrowsError(try ExchangeMessage.decode(Data([1, 0, 0, 0, 99, 1])))
    }

    /// MTUの大きさに関係なく、分割したものを組み立て直せる
    func testChunkingAndReassembly() throws {
        let a = try ExchangeMessage.profile(payload, icon: Data(repeating: 7, count: 18_000)).encoded()
        let b = try ExchangeMessage.accept.encoded()
        for size in [20, 182, 512] {
            var reassembler = Reassembler()
            var got: [Data] = []
            for chunk in Framing.chunks(of: a, size: size) + Framing.chunks(of: b, size: size) {
                XCTAssertLessThanOrEqual(chunk.count, size)
                got += try reassembler.append(chunk)
            }
            XCTAssertEqual(got, [a, b], "size \(size)")
        }
    }

    func testRejectsOversizedLength() {
        var reassembler = Reassembler()
        XCTAssertThrowsError(try reassembler.append(Data([0xFF, 0xFF, 0xFF, 0xFF])))
    }
}

final class ExchangeSessionTests: XCTestCase {
    private func makeSession() -> ExchangeSession {
        ExchangeSession(myPreview: ProfilePreview(token: "AAAAAA", displayName: "me", department: "情報工学科", grade: 1),
                        myThumbnail: Data([1]),
                        myProfile: ProfilePayload(uid: "me", displayName: "me", department: "情報工学科", grade: 1, message: ""),
                        myIcon: Data([2]))
    }
    private let partner = ProfilePreview(token: "BBBBBB", displayName: "you", department: "CGデザイン科", grade: 3)
    private let partnerProfile = ProfilePayload(uid: "you", displayName: "you", department: "CGデザイン科", grade: 3, message: "hi")

    private func confirming() -> ExchangeSession {
        var s = makeSession()
        XCTAssertEqual(s.handle(.linkReady).count, 1)
        _ = s.handle(.received(.hello(partner, thumbnail: Data([9]))))
        return s
    }

    private var myProfileMessage: ExchangeSession.Action {
        .send(.profile(ProfilePayload(uid: "me", displayName: "me", department: "情報工学科", grade: 1, message: ""), icon: Data([2])))
    }

    func testHelloShowsPartner() {
        let s = confirming()
        XCTAssertEqual(s.state, .confirming(partner, thumbnail: Data([9]), localAccepted: false, remoteAccepted: false))
    }

    func testIAcceptFirst() {
        var s = confirming()
        XCTAssertEqual(s.handle(.userAccepted), [.send(.accept), .startApprovalTimer])
        XCTAssertEqual(s.handle(.userAccepted), [], "二重に送らない")
        XCTAssertEqual(s.handle(.received(.accept)), [.cancelApprovalTimer, myProfileMessage])
        XCTAssertEqual(s.handle(.received(.profile(partnerProfile, icon: Data([5])))), [])
        XCTAssertEqual(s.handle(.profileSent), [.close])
        XCTAssertEqual(s.state, .done(.init(profile: partnerProfile, icon: Data([5]))))
    }

    func testPartnerAcceptsFirst() {
        var s = confirming()
        XCTAssertEqual(s.handle(.received(.accept)), [])
        XCTAssertEqual(s.handle(.userAccepted), [.send(.accept), myProfileMessage])
        XCTAssertEqual(s.handle(.profileSent), [])
        XCTAssertEqual(s.handle(.received(.profile(partnerProfile, icon: Data([5])))), [.close])
        XCTAssertTrue(s.isFinished)
    }

    func testProfileArrivesBeforeAccept() {
        var s = confirming()
        _ = s.handle(.userAccepted)
        let actions = s.handle(.received(.profile(partnerProfile, icon: Data([5]))))
        XCTAssertEqual(actions, [.cancelApprovalTimer, myProfileMessage])
        XCTAssertEqual(s.handle(.profileSent), [.close])
        XCTAssertEqual(s.state, .done(.init(profile: partnerProfile, icon: Data([5]))))
    }

    func testDecline() {
        var s = confirming()
        XCTAssertEqual(s.handle(.userDeclined), [.cancelApprovalTimer, .send(.decline), .close])
        XCTAssertEqual(s.state, .ended(.cancelled))
        XCTAssertNil(ExchangeSession.EndReason.cancelled.message)
    }

    func testPartnerDeclines() {
        var s = confirming()
        _ = s.handle(.userAccepted)
        _ = s.handle(.received(.decline))
        XCTAssertEqual(s.state, .ended(.partnerDeclined))
        XCTAssertEqual(ExchangeSession.EndReason.partnerDeclined.message, "相手が交換をやめました")
    }

    func testTimeoutOnlyAfterIAccepted() {
        var s = confirming()
        XCTAssertEqual(s.handle(.approvalTimedOut), [], "自分が押す前はタイムアウトしない")
        _ = s.handle(.userAccepted)
        XCTAssertEqual(s.handle(.approvalTimedOut), [.send(.decline), .close])
        XCTAssertEqual(s.state, .ended(.timeout))
    }

    func testDisconnect() {
        var s = confirming()
        _ = s.handle(.linkClosed)
        XCTAssertEqual(s.state, .ended(.disconnected))
        XCTAssertEqual(s.handle(.received(.accept)), [], "終わった後の入力は無視する")
    }

    func testDisconnectAfterReceivingProfileStillSucceeds() {
        var s = confirming()
        _ = s.handle(.received(.accept))
        _ = s.handle(.userAccepted)
        _ = s.handle(.received(.profile(partnerProfile, icon: Data([5]))))
        _ = s.handle(.linkClosed)
        XCTAssertEqual(s.state, .done(.init(profile: partnerProfile, icon: Data([5]))))
    }
}

final class ProximityDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testNeedsOneSecondAboveThreshold() {
        var d = ProximityDetector()
        XCTAssertFalse(d.update(peer: "A", rssi: -40, at: t0))
        XCTAssertFalse(d.update(peer: "A", rssi: -44, at: t0 + 0.5))
        XCTAssertTrue(d.update(peer: "A", rssi: -45, at: t0 + 1.0))
    }

    func testDropBelowResets() {
        var d = ProximityDetector()
        _ = d.update(peer: "A", rssi: -40, at: t0)
        XCTAssertFalse(d.update(peer: "A", rssi: -60, at: t0 + 0.6))
        XCTAssertFalse(d.update(peer: "A", rssi: -40, at: t0 + 1.2))
        XCTAssertTrue(d.update(peer: "A", rssi: -40, at: t0 + 2.2))
    }

    func testIgnoresUnavailableRssiAndFarPeers() {
        var d = ProximityDetector()
        XCTAssertFalse(d.update(peer: "A", rssi: 127, at: t0))
        XCTAssertFalse(d.update(peer: "B", rssi: -70, at: t0))
        XCTAssertFalse(d.update(peer: "B", rssi: -70, at: t0 + 5))
    }

    func testBlockedPeerNeedsSeparationOrCooldown() {
        var d = ProximityDetector()
        d.block(peer: "A", at: t0)
        XCTAssertFalse(d.update(peer: "A", rssi: -40, at: t0 + 1))
        XCTAssertFalse(d.update(peer: "A", rssi: -40, at: t0 + 5))
        XCTAssertFalse(d.update(peer: "A", rssi: -50, at: t0 + 6), "少し下がっただけでは離れたとみなさない")
        XCTAssertFalse(d.update(peer: "A", rssi: -40, at: t0 + 7))
        // はっきり離れたら解除
        XCTAssertFalse(d.update(peer: "A", rssi: -70, at: t0 + 8))
        XCTAssertFalse(d.update(peer: "A", rssi: -40, at: t0 + 9))
        XCTAssertTrue(d.update(peer: "A", rssi: -40, at: t0 + 10))
        // 離れなくても cooldown がたてば解除
        d.block(peer: "B", at: t0)
        XCTAssertFalse(d.update(peer: "B", rssi: -40, at: t0 + 19))
        XCTAssertFalse(d.update(peer: "B", rssi: -40, at: t0 + 20))
        XCTAssertTrue(d.update(peer: "B", rssi: -40, at: t0 + 21))
    }
}

