import Foundation
import SwiftData

/// ステッカーの保存・位置の確定・削除
@MainActor
enum StickerStore {
    /// 交換で受け取ったプロフィールを保存する。同じ相手なら上書きし、空いている位置に仮置きする
    @discardableResult
    static func saveReceived(_ profile: ProfilePayload, icon: Data, in context: ModelContext) throws -> Sticker {
        let all = try context.fetch(FetchDescriptor<Sticker>())
        let others = all.filter { $0.partnerUid != profile.uid }
        var rng = SystemRandomNumberGenerator()
        let free = StickerLayout.freePosition(existing: others.map { ($0.positionX, $0.positionY) })
        // 格子の上にきっちり並ばないように、少しだけずらす
        let spot = StickerLayout.clamp(x: free.x + .random(in: -0.03...0.03, using: &rng),
                                       y: free.y + .random(in: -0.03...0.03, using: &rng))
        let top = (all.map(\.zIndex).max() ?? 0) + 1

        if let existing = all.first(where: { $0.partnerUid == profile.uid }) {
            existing.displayName = profile.displayName
            existing.department = profile.department
            existing.grade = profile.grade
            existing.message = profile.message
            existing.iconImage = icon
            existing.exchangedAt = Date()
            existing.positionX = spot.x
            existing.positionY = spot.y
            existing.rotation = StickerLayout.randomRotation(using: &rng)
            existing.zIndex = top
            try context.save()
            return existing
        }
        let sticker = Sticker(partnerUid: profile.uid, displayName: profile.displayName, department: profile.department,
                              grade: profile.grade, message: profile.message, iconImage: icon,
                              positionX: spot.x, positionY: spot.y,
                              rotation: StickerLayout.randomRotation(using: &rng), zIndex: top)
        context.insert(sticker)
        try context.save()
        return sticker
    }

    /// 位置を確定し、最前面にする（G4の移動・G7の貼り付け）
    static func place(_ sticker: Sticker, x: Double, y: Double, in context: ModelContext) {
        let p = StickerLayout.clamp(x: x, y: y)
        let top = ((try? context.fetch(FetchDescriptor<Sticker>()))?.map(\.zIndex).max() ?? 0)
        sticker.positionX = p.x
        sticker.positionY = p.y
        if sticker.zIndex < top || top == 0 { sticker.zIndex = top + 1 }
        try? context.save()
    }

    static func peel(_ sticker: Sticker, in context: ModelContext) {
        context.delete(sticker)
        try? context.save()
    }
}
