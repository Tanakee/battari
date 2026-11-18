import SwiftData
import SwiftUI

/// G9 ステッカー一覧。持っているステッカーを全部並べ、貼るもの・はがすものを選ぶ
struct StickerListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Sticker.exchangedAt, order: .reverse) private var stickers: [Sticker]
    @State private var selected: Sticker?
    @State private var pending: (Sticker, StickerAction)?

    private var stored: [Sticker] { stickers.filter { !$0.isPlaced } }
    private var placed: [Sticker] { stickers.filter(\.isPlaced) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("ステッカー一覧").font(.system(size: 17, weight: .bold))
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
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if stickers.isEmpty {
                Spacer()
                Text("まだステッカーがありません\n近くの人と交換してみよう")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.label.opacity(0.7))
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        section("まだ貼っていない", stored, empty: "全部のステッカーを貼っています")
                        section("天板に貼っている", placed, empty: "天板にはまだ何も貼っていません")
                            .padding(.top, 28)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .sheet(item: $selected, onDismiss: {
            if let (sticker, action) = pending {
                withAnimation { StickerStore.apply(action, to: sticker, in: context) }
                pending = nil
            }
        }) { sticker in
            StickerDetailView(sticker: sticker) { pending = (sticker, $0) }
        }
    }

    private func section(_ title: String, _ items: [Sticker], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(items.count)").foregroundStyle(Theme.sub)
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Theme.ink)

            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.sub)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { sticker in
                        Button { selected = sticker } label: { cell(sticker) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(sticker.displayName)さんのステッカー")
                    }
                }
            }
        }
    }

    private func cell(_ sticker: Sticker) -> some View {
        VStack(spacing: 8) {
            StickerImage(image: sticker.iconImage, shapeKey: sticker.partnerUid, size: 76)
                .rotationEffect(.degrees(sticker.rotation))
                .frame(width: 88, height: 88)
            Text(sticker.displayName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
    }
}
