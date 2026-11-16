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
            _ = try? StickerStore.saveReceived(profile, icon: ImageTools.initialIcon(for: name), in: context)
        }
        return container
    }
}
#endif
