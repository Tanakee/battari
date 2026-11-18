import SwiftData
import SwiftUI

/// G4 ホーム（ステッカーコレクション）
struct HomeView: View {
    let profile: MyProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \Sticker.zIndex) private var stickers: [Sticker]
    @State private var editing = false
    @State private var exchanging = false
    /// ステッカーケースを開いているか
    @State private var caseOpen = false
    /// ケースと天板のあいだでステッカーが移る動き
    @Namespace private var stickerSpace
    @State private var selected: Sticker?
    /// G8で選んだ操作。シートを閉じてから反映する（表示中のステッカーを消すと落ちるため）
    @State private var pending: (Sticker, StickerAction)?

    private var placed: [Sticker] { stickers.filter(\.isPlaced) }
    /// ケースにしまってあるステッカー（新しく交換した順）
    private var stored: [Sticker] { stickers.filter { !$0.isPlaced }.sorted { $0.exchangedAt > $1.exchangedAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Logo()
                Spacer()
                Button { editing = true } label: {
                    StickerImage(image: profile.iconImage, size: 48)
                }
                .accessibilityLabel("プロフィールを編集")
            }
            .padding(.top, 12)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(Format.stickerCount(stickers.count))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                Text("枚のステッカー")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.sub)
            }
            .padding(.top, 8)

            LaptopLid { size in
                StickerCanvas(stickers: placed, size: size,
                              onTap: { selected = $0 },
                              onMove: { sticker, x, y in StickerStore.place(sticker, x: x, y: y, in: context) },
                              namespace: stickerSpace)
                if placed.isEmpty {
                    Text(stickers.isEmpty ? "まだステッカーがありません\n近くの人と交換してみよう" : "ステッカーケースから\n貼りたいステッカーを選ぼう")
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.label.opacity(0.7))
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 4)

            StickerCaseBar(stickers: stored, open: $caseOpen, namespace: stickerSpace,
                           onPlace: { sticker in
                               withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                                   StickerStore.placeAtFreeSpot(sticker, in: context)
                               }
                           },
                           onDetail: { selected = $0 })
                .padding(.top, 14)

            Spacer(minLength: 12)
            Button { exchanging = true } label: {
                Label("近くの人と交換する", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(PillButtonStyle())
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .background(Theme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $editing) {
            ProfileEditView(mode: .edit(profile))
        }
        .fullScreenCover(isPresented: $exchanging) {
            ExchangeFlowView(profile: profile)
        }
        #if DEBUG
        .onAppear {
            switch DemoData.screen {
            case "G3": editing = true
            case "G5", "G6", "G7": exchanging = true
            case "G8": selected = placed.first
            case "case": caseOpen = true
            default: break
            }
        }
        #endif
        .sheet(item: $selected, onDismiss: {
            if let (sticker, action) = pending {
                withAnimation(.spring(duration: 0.45, bounce: 0.2)) { StickerStore.apply(action, to: sticker, in: context) }
                pending = nil
            }
        }) { sticker in
            StickerDetailView(sticker: sticker) { pending = (sticker, $0) }
        }
    }
}

/// G8 ステッカー詳細
struct StickerDetailView: View {
    let sticker: Sticker
    /// 選んだ操作。呼び出し側がシートを閉じたあとで反映する
    let onAction: (StickerAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.label)
                        .frame(width: 36, height: 36)
                        .background(Theme.gray, in: Circle())
                }
                .accessibilityLabel("閉じる")
            }
            .padding(.top, 16)

            StickerImage(image: sticker.iconImage, shapeKey: sticker.partnerUid, size: 168)
                .rotationEffect(.degrees(sticker.rotation))
                .padding(.top, 8)

            Text(sticker.displayName)
                .font(.system(size: 26, weight: .heavy))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 24)
            Text(sticker.departmentAndGrade)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.sub)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 6)

            if !sticker.message.isEmpty {
                Text(sticker.message)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 24)
            }

            HStack {
                Text("交換日時").foregroundStyle(Theme.sub)
                Spacer()
                Text(Format.dateTime(sticker.exchangedAt)).fontWeight(.semibold)
            }
            .font(.system(size: 14))
            .padding(.top, 20)

            Spacer()
            if sticker.isPlaced {
                Button("はがしてケースにしまう") { finish(.unplace) }
                    .buttonStyle(PillButtonStyle(kind: .gray))
            } else {
                Button("天板に貼る") { finish(.place) }
                    .buttonStyle(PillButtonStyle())
            }
            Button("ステッカーを削除") { confirmDelete = true }
                .buttonStyle(PillButtonStyle(kind: .danger))
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .background(Theme.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .alert("\(sticker.displayName)さんのステッカーを削除しますか？", isPresented: $confirmDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除する", role: .destructive) { finish(.delete) }
        } message: {
            Text("削除すると元に戻せません。はがすだけならケースに残ります")
        }
    }

    private func finish(_ action: StickerAction) {
        onAction(action)
        dismiss()
    }
}
