import Foundation

/// 1人の相手との交換の進み方（G6）。BLEには依存せず、入力に対して「次にすること」を返す
struct ExchangeSession {
    enum EndReason: Equatable {
        case cancelled // 自分が「やめる」を押した
        case partnerDeclined
        case timeout
        case disconnected

        /// G5に戻ったときに表示する理由（自分でやめた場合は出さない）
        var message: String? {
            switch self {
            case .cancelled: return nil
            case .partnerDeclined: return "相手が交換をやめました"
            case .timeout: return "相手の応答がありませんでした"
            case .disconnected: return "通信が切れました"
            }
        }
    }

    enum State: Equatable {
        /// 接続済み。相手の情報を待っている
        case handshaking
        /// 相手の情報を表示して、双方の承認を待っている
        case confirming(ProfilePreview, thumbnail: Data, localAccepted: Bool, remoteAccepted: Bool)
        /// プロフィールを送受信している
        case transferring(sent: Bool, received: Received?)
        case done(Received)
        case ended(EndReason)
    }

    struct Received: Equatable {
        var profile: ProfilePayload
        var icon: Data
    }

    enum Action: Equatable {
        case send(ExchangeMessage)
        case startApprovalTimer
        case cancelApprovalTimer
        /// 送信中のデータを送り切ってから切断する
        case close
    }

    enum Input {
        case linkReady
        case received(ExchangeMessage)
        case userAccepted
        case userDeclined
        case approvalTimedOut
        /// 自分のプロフィールを送り切った
        case profileSent
        case linkClosed
    }

    private(set) var state: State = .handshaking
    let myPreview: ProfilePreview
    let myThumbnail: Data
    let myProfile: ProfilePayload
    let myIcon: Data

    init(myPreview: ProfilePreview, myThumbnail: Data, myProfile: ProfilePayload, myIcon: Data) {
        self.myPreview = myPreview
        self.myThumbnail = myThumbnail
        self.myProfile = myProfile
        self.myIcon = myIcon
    }

    var isFinished: Bool {
        switch state {
        case .done, .ended: return true
        default: return false
        }
    }

    mutating func handle(_ input: Input) -> [Action] {
        if isFinished { return [] }
        switch (input, state) {
        case (.linkReady, .handshaking):
            return [.send(.hello(myPreview, thumbnail: myThumbnail))]

        case let (.received(.hello(preview, thumb)), .handshaking):
            state = .confirming(preview, thumbnail: thumb, localAccepted: false, remoteAccepted: false)
            return []

        case let (.userAccepted, .confirming(p, t, false, remote)):
            if remote { return startTransfer(extra: [.send(.accept)]) }
            state = .confirming(p, thumbnail: t, localAccepted: true, remoteAccepted: false)
            return [.send(.accept), .startApprovalTimer]

        case let (.received(.accept), .confirming(p, t, local, _)):
            if local { return startTransfer(extra: [.cancelApprovalTimer]) }
            state = .confirming(p, thumbnail: t, localAccepted: false, remoteAccepted: true)
            return []

        // 自分が承認済みなら、相手のプロフィールが先に届いても受け取る
        case let (.received(.profile(profile, icon)), .confirming(_, _, true, _)):
            var actions = startTransfer(extra: [.cancelApprovalTimer])
            actions += receive(Received(profile: profile, icon: icon))
            return actions

        case let (.received(.profile(profile, icon)), .transferring):
            return receive(Received(profile: profile, icon: icon))

        case let (.profileSent, .transferring(_, received)):
            if let received {
                state = .done(received)
                return [.close]
            }
            state = .transferring(sent: true, received: nil)
            return []

        case (.received(.decline), _):
            state = .ended(.partnerDeclined)
            return [.cancelApprovalTimer, .close]

        case (.userDeclined, _):
            state = .ended(.cancelled)
            return [.cancelApprovalTimer, .send(.decline), .close]

        case (.approvalTimedOut, .confirming(_, _, true, false)):
            state = .ended(.timeout)
            return [.send(.decline), .close]

        case (.linkClosed, _):
            // 相手のプロフィールを受け取っていれば、こちらの送信が終わっていなくても成立とする
            if case let .transferring(_, received?) = state {
                state = .done(received)
                return []
            }
            state = .ended(.disconnected)
            return [.cancelApprovalTimer]

        default:
            return []
        }
    }

    private mutating func startTransfer(extra: [Action]) -> [Action] {
        state = .transferring(sent: false, received: nil)
        return extra + [.send(.profile(myProfile, icon: myIcon))]
    }

    private mutating func receive(_ received: Received) -> [Action] {
        guard case let .transferring(sent, _) = state else { return [] }
        if sent {
            state = .done(received)
            return [.close]
        }
        state = .transferring(sent: false, received: received)
        return []
    }
}
