import Foundation
import SwiftData

/// 自分のプロフィール（端末内に1件だけ）
@Model
final class MyProfile {
    var id: UUID
    @Attribute(.unique) var uid: String
    var displayName: String
    var department: String
    var grade: Int
    var message: String
    @Attribute(.externalStorage) var iconImage: Data
    var updatedAt: Date

    init(uid: String, displayName: String, department: String, grade: Int, message: String, iconImage: Data) {
        self.id = UUID()
        self.uid = uid
        self.displayName = displayName
        self.department = department
        self.grade = grade
        self.message = message
        self.iconImage = iconImage
        self.updatedAt = Date()
    }
}

/// 交換した相手のステッカー（交換時点のプロフィールと貼り付け位置）
@Model
final class Sticker {
    var id: UUID
    @Attribute(.unique) var partnerUid: String
    var displayName: String
    var department: String
    var grade: Int
    var message: String
    @Attribute(.externalStorage) var iconImage: Data
    var exchangedAt: Date
    /// 天板の左端0.0〜右端1.0
    var positionX: Double
    /// 天板の上端0.0〜下端1.0
    var positionY: Double
    /// 度。±15度
    var rotation: Double
    var zIndex: Int

    init(partnerUid: String, displayName: String, department: String, grade: Int, message: String,
         iconImage: Data, positionX: Double, positionY: Double, rotation: Double, zIndex: Int) {
        self.id = UUID()
        self.partnerUid = partnerUid
        self.displayName = displayName
        self.department = department
        self.grade = grade
        self.message = message
        self.iconImage = iconImage
        self.exchangedAt = Date()
        self.positionX = positionX
        self.positionY = positionY
        self.rotation = rotation
        self.zIndex = zIndex
    }
}

extension Sticker {
    /// 「（学科）　（学年）年」
    var departmentAndGrade: String { "\(department)　\(grade)年" }
}
