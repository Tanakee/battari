import Foundation

/// ステッカーを貼る位置の計算（天板上の相対座標 0.0〜1.0）
enum StickerLayout {
    /// 天板の縦横比（幅 / 高さ）
    static let lidAspect = 0.86
    /// ステッカーの直径（天板の幅に対する割合）
    static let stickerSize = 0.21
    /// ステッカーの中心が動ける範囲（はみ出さないように端を空ける）
    static let minX = stickerSize / 2 + 0.02
    static let maxX = 1 - minX
    static let minY = stickerSize * lidAspect / 2 + 0.02
    static let maxY = 1 - minY

    static func clamp(x: Double, y: Double) -> (x: Double, y: Double) {
        (min(max(x, minX), maxX), min(max(y, minY), maxY))
    }

    /// 既存のステッカーから最も離れた位置を返す（同じ距離なら上・左を優先）
    static func freePosition(existing: [(x: Double, y: Double)], steps: Int = 9) -> (x: Double, y: Double) {
        var best = (x: 0.5, y: 0.5)
        var bestDistance = -1.0
        for j in 0..<steps {
            for i in 0..<steps {
                let x = minX + (maxX - minX) * Double(i) / Double(steps - 1)
                let y = minY + (maxY - minY) * Double(j) / Double(steps - 1)
                // 縦方向は天板の高さで割っているので、距離を測る前に幅基準へそろえる
                let d = existing.map { hypot($0.x - x, ($0.y - y) / lidAspect) }.min() ?? .infinity
                if d > bestDistance + 1e-9 {
                    bestDistance = d
                    best = (x, y)
                }
                if d == .infinity { return (0.5, 0.5) }
            }
        }
        return best
    }

    static func randomRotation<G: RandomNumberGenerator>(using rng: inout G) -> Double {
        Double.random(in: -15...15, using: &rng)
    }
}
