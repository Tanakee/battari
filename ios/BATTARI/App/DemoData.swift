#if DEBUG
import SwiftData
import UIKit

/// 起動引数 -demo YES のときに使うサンプルデータ（メモリ上のみ）
enum DemoData {
    static let uid = "demo-me"
    /// 起動引数 -demoScreen G3 など。指定した画面を開いた状態で起動する
    static var screen: String? { UserDefaults.standard.string(forKey: "demoScreen") }

    static var confirming: ExchangeManager.Phase {
        .confirming(ProfilePreview(displayName: "さとう みく", department: "情報システム専攻科", grade: 2),
                    thumbnail: ImageTools.thumbnail(ImageTools.initialIcon(for: "佐藤")), waiting: false)
    }

    /// 起動引数 -sampleStickers 2 など：端末に保存されたデータへ、交換済みのサンプルを足す。
    /// UIDは固定なので、何度起動しても増えすぎない（同じ相手は上書き）
    @MainActor
    static func addSampleStickers(to container: ModelContainer) {
        let count = UserDefaults.standard.integer(forKey: "sampleStickers")
        guard count > 0 else { return }
        let samples: [(String, String, Int, String)] = [
            ("佐藤 みく", "情報システム専攻科", 2, "よろしくお願いします！"),
            ("鈴木 そうた", "ゲームクリエイター学科", 1, "Unityでゲーム作ってます"),
            ("高橋 ゆい", "CGデザイン科", 3, ""),
            ("伊藤 れん", "情報工学科", 2, "話しかけてください"),
        ]
        for (i, (name, department, grade, message)) in samples.prefix(count).enumerated() {
            let profile = ProfilePayload(uid: "sample-\(i)", displayName: name, department: department, grade: grade, message: message)
            _ = try? StickerStore.saveReceived(profile, icon: ImageTools.initialIcon(for: name), in: container.mainContext)
        }
        try? container.mainContext.save()
    }

    @MainActor
    static func container() -> ModelContainer {
        let container = try! ModelContainer(for: MyProfile.self, Sticker.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(MyProfile(uid: uid, displayName: "田中 けいと", department: "情報システム専攻科", grade: 3,
                                 message: "Swiftでアプリ作ってます。話しかけてください！",
                                 iconImage: ImageTools.initialIcon(for: "田中")))
        let names = ["佐藤 みく", "鈴木 そうた", "高橋 ゆい", "伊藤 れん", "渡辺 あおい", "山本 はると", "中村 さくら", "小林 ゆうと"]
        for (i, name) in names.enumerated() {
            let profile = ProfilePayload(uid: "demo-\(i)", displayName: name, department: Departments.all[i % Departments.all.count],
                                         grade: i % 4 + 1, message: i % 2 == 0 ? "よろしくお願いします！" : "")
            if let sticker = try? StickerStore.saveReceived(profile, icon: ImageTools.initialIcon(for: name), in: context), i < 3 {
                StickerStore.placeAtFreeSpot(sticker, in: context) // 残りはケースにしまっておく
            }
        }
        return container
    }
}
#endif
