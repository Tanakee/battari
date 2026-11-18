import Foundation

/// 学科の選択肢（G3）。名称は仮で、学校の正式な学科名称一覧が決まったら差し替える
enum Departments {
    static let all = [
        "情報工学科",
        "情報システム専攻科",
        "情報ビジネス科",
        "ゲームクリエイター学科",
        "CGデザイン科",
        "電気・電子工学科",
    ]
}

enum Limits {
    static let studentIdLength = 20
    static let displayNameLength = 20
    static let departmentLength = 30
    static let messageLength = 50
    static let grades = 1...4
    static let iconSize = 256 // px
    static let iconMaxBytes = 20_000
    static let otpLength = 6
    static let resendSeconds = 60
}

enum Exchange {
    /// この値以上の電波強度が続いた相手だけを「スマホを近づけた相手」とみなす（暫定値・実機で調整）
    static let rssiThreshold = -45
    /// 閾値以上の状態が続く必要がある時間
    static let dwell: TimeInterval = 1.0
    /// 「交換する」を押してから相手の承認を待つ時間
    static let approvalTimeout: TimeInterval = 30
    /// 交換を終えた相手を、離れるまで（最長この時間）再検知しない
    static let rematchCooldown: TimeInterval = 20
}

enum School {
    static let mailDomain = "s.asojuku.ac.jp"
}
