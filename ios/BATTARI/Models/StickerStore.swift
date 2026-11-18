import Foundation
import SwiftData

/// G8で選べる操作
enum StickerAction { case place, unplace, delete }

/// ステッカーの保存・天板への貼り付け・ケースへしまう・削除
@MainActor
enum StickerStore {
    /// 交換で受け取ったプロフィールを保存する。同じ相手なら上書きする。
    /// 貼るかしまうかはG7で決めるので、ここでは天板に貼らない（貼っていたものはそのまま）
    @discardableResult
    static func saveReceived(_ profile: ProfilePayload, icon: Data, in context: ModelContext) throws -> Sticker {
        let all = try context.fetch(FetchDescriptor<Sticker>())
        var rng = SystemRandomNumberGenerator()
        let top = (all.map(\.zIndex).max() ?? 0) + 1

        if let existing = all.first(where: { $0.partnerUid == profile.uid }) {
            existing.displayName = profile.displayName
            existing.department = profile.department
            existing.grade = profile.grade
            existing.message = profile.message
            existing.iconImage = icon
            existing.exchangedAt = Date()
            if !existing.isPlaced {
                let spot = freeSpot(among: all, excluding: existing, using: &rng)
                existing.positionX = spot.x
                existing.positionY = spot.y
                existing.rotation = StickerLayout.randomRotation(using: &rng)
            }
            existing.zIndex = top
            try context.save()
            return existing
        }
        let spot = freeSpot(among: all, excluding: nil, using: &rng)
        let sticker = Sticker(partnerUid: profile.uid, displayName: profile.displayName, department: profile.department,
                              grade: profile.grade, message: profile.message, iconImage: icon,
                              positionX: spot.x, positionY: spot.y,
                              rotation: StickerLayout.randomRotation(using: &rng), zIndex: top, isPlaced: false)
        context.insert(sticker)
        try context.save()
        return sticker
    }

    /// 天板に貼っているステッカーから離れた位置。格子の上にきっちり並ばないように、少しだけずらす
    private static func freeSpot(among all: [Sticker], excluding: Sticker?,
                                 using rng: inout SystemRandomNumberGenerator) -> (x: Double, y: Double) {
        let placed = all.filter { $0.isPlaced && $0.id != excluding?.id }
        let free = StickerLayout.freePosition(existing: placed.map { ($0.positionX, $0.positionY) })
        return StickerLayout.clamp(x: free.x + .random(in: -0.03...0.03, using: &rng),
                                   y: free.y + .random(in: -0.03...0.03, using: &rng))
    }

    /// 指定の位置に貼り、最前面にする（G4の移動・G7の貼り付け）
    static func place(_ sticker: Sticker, x: Double, y: Double, in context: ModelContext) {
        let p = StickerLayout.clamp(x: x, y: y)
        let top = ((try? context.fetch(FetchDescriptor<Sticker>()))?.map(\.zIndex).max() ?? 0)
        sticker.positionX = p.x
        sticker.positionY = p.y
        sticker.isPlaced = true
        if sticker.zIndex < top || top == 0 { sticker.zIndex = top + 1 }
        try? context.save()
    }

    /// ステッカーケースから貼る。空いている位置に置く。位置はG4で長押しして動かせる
    static func placeAtFreeSpot(_ sticker: Sticker, in context: ModelContext) {
        var rng = SystemRandomNumberGenerator()
        let all = (try? context.fetch(FetchDescriptor<Sticker>())) ?? []
        let spot = freeSpot(among: all, excluding: sticker, using: &rng)
        place(sticker, x: spot.x, y: spot.y, in: context)
    }

    /// 天板からはがしてケースにしまう（ステッカーは残る）
    static func unplace(_ sticker: Sticker, in context: ModelContext) {
        sticker.isPlaced = false
        try? context.save()
    }

    /// ステッカーを削除する（元に戻せない）
    static func delete(_ sticker: Sticker, in context: ModelContext) {
        context.delete(sticker)
        try? context.save()
    }

    static func apply(_ action: StickerAction, to sticker: Sticker, in context: ModelContext) {
        switch action {
        case .place: placeAtFreeSpot(sticker, in: context)
        case .unplace: unplace(sticker, in: context)
        case .delete: delete(sticker, in: context)
        }
    }
}
