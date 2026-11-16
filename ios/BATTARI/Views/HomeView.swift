import SwiftData
import SwiftUI

/// G4 ホーム（ステッカーコレクション）
struct HomeView: View {
    let profile: MyProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \Sticker.zIndex) private var stickers: [Sticker]
    @State private var editing = false
    @State private var exchanging = false
    @State private var selected: Sticker?
    /// G8で「はがす」を選んだステッカー。シートを閉じてから削除する
    @State private var peeling: Sticker?

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
                StickerCanvas(stickers: stickers, size: size,
                              onTap: { selected = $0 },
                              onMove: { sticker, x, y in StickerStore.place(sticker, x: x, y: y, in: context) })
                if stickers.isEmpty {
                    Text("まだステッカーがありません\n近くの人と交換してみよう")
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.label.opacity(0.7))
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 4)

            Text("ステッカーをタップで詳細・長押しで移動")
                .font(.system(size: 13))
                .foregroundStyle(Theme.sub)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

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
            case "G8": selected = stickers.first
            default: break
            }
        }
        #endif
        .sheet(item: $selected, onDismiss: {
            if let peeling {
                withAnimation { StickerStore.peel(peeling, in: context) }
                self.peeling = nil
            }
        }) { sticker in
            StickerDetailView(sticker: sticker) { peeling = sticker }
        }
    }
}

/// G8 ステッカー詳細
struct StickerDetailView: View {
    let sticker: Sticker
    let onPeel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPeel = false

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
            Button("ステッカーをはがす") { confirmPeel = true }
                .buttonStyle(PillButtonStyle(kind: .danger))
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .background(Theme.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .alert("\(sticker.displayName)さんのステッカーをはがしますか？", isPresented: $confirmPeel) {
            Button("キャンセル", role: .cancel) {}
            Button("はがす", role: .destructive) {
                onPeel()
                dismiss()
            }
        } message: {
            Text("はがすと元に戻せません")
        }
    }
}
