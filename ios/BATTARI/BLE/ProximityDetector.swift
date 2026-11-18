import Foundation

/// 電波強度（RSSI）から「スマホを近づけた相手」を判定する。
/// 閾値以上の状態が dwell 秒続いたら検知する。交換を終えた相手は、一度はっきり離れるか cooldown 秒たつまで検知しない
struct ProximityDetector {
    var threshold: Int = Exchange.rssiThreshold
    /// 閾値をこれだけ下回ったら「離れた」とみなす（RSSIの揺れで再検知しないように）
    var separationMargin: Int = 10
    var dwell: TimeInterval = Exchange.dwell
    var cooldown: TimeInterval = Exchange.rematchCooldown

    private var nearSince: [String: Date] = [:]
    private var blockedUntil: [String: Date] = [:]

    /// RSSIを1件反映し、この相手を検知したら true を返す
    mutating func update(peer: String, rssi: Int, at now: Date) -> Bool {
        // 127 は「測定できなかった」を表す値なので無視する
        guard rssi != 127 else { return false }
        if rssi < threshold {
            nearSince[peer] = nil
            if rssi < threshold - separationMargin { blockedUntil[peer] = nil } // 一度離れたら、また交換できる
            return false
        }
        if let until = blockedUntil[peer] {
            if now < until { return false }
            blockedUntil[peer] = nil
        }
        guard let since = nearSince[peer] else {
            nearSince[peer] = now
            return dwell <= 0
        }
        return now.timeIntervalSince(since) >= dwell
    }

    /// 交換を終えた（またはやめた）相手を、しばらく検知しないようにする
    mutating func block(peer: String, at now: Date) {
        nearSince[peer] = nil
        blockedUntil[peer] = now.addingTimeInterval(cooldown)
    }

    mutating func reset() {
        nearSince.removeAll()
    }
}
