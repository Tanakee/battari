import SwiftUI

/// G4 天板の下のステッカーケース。押すと横に開き、しまってあるステッカーから貼るものを選ぶ
struct StickerCaseBar: View {
    let stickers: [Sticker]
    @Binding var open: Bool
    let namespace: Namespace.ID
    let onPlace: (Sticker) -> Void
    let onDetail: (Sticker) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { open.toggle() }
                } label: {
                    StickerCaseIcon(stickers: stickers, open: open)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "ステッカーケースを閉じる" : "ステッカーケースを開く（\(stickers.count)枚）")

                if open {
                    tray.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            .padding(6)
            .frame(maxWidth: open ? .infinity : nil, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.fieldBorder, lineWidth: 1.5))

            if !open {
                Text("天板のステッカーは\nタップで詳細・長押しで移動")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.sub)
                    .lineSpacing(2)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 92)
        .onChange(of: stickers.isEmpty) { _, empty in
            // 最後の1枚を貼ったら閉じる
            if empty && open { withAnimation(.spring(duration: 0.4, bounce: 0.2).delay(0.3)) { open = false } }
        }
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stickers.isEmpty ? "しまってあるステッカーはありません" : "タップで天板に貼る・長押しで詳細")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.sub)
                .padding(.leading, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stickers) { sticker in
                        StickerImage(image: sticker.iconImage, shapeKey: sticker.partnerUid, size: 48)
                            .rotationEffect(.degrees(sticker.rotation))
                            .matchedGeometryEffect(id: sticker.id, in: namespace)
                            .frame(width: 56, height: 56)
                            .contentShape(Rectangle())
                            .onTapGesture { onPlace(sticker) }
                            .onLongPressGesture(minimumDuration: 0.4) { onDetail(sticker) }
                            .accessibilityLabel("\(sticker.displayName)さんのステッカー。タップで天板に貼る")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3) // 影が切れないように
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// カード入れのような見た目のケース。しまってあるステッカーが上から少しのぞく
private struct StickerCaseIcon: View {
    let stickers: [Sticker]
    let open: Bool

    var body: some View {
        let peek = Array(stickers.prefix(3))
        let empty = stickers.isEmpty
        ZStack(alignment: .bottom) {
            // 背面の板
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(empty ? Color(hex: 0xC9CBD6) : Color(hex: 0x3F3FB0))
                .frame(width: 66, height: 52)
                .offset(y: -10)
            ForEach(Array(peek.enumerated()), id: \.element.id) { i, sticker in
                StickerImage(image: sticker.iconImage, shapeKey: sticker.partnerUid, size: 30)
                    .rotationEffect(.degrees(Double(i - 1) * 14))
                    .offset(x: CGFloat(i - 1) * 15, y: open ? -38 : -30)
            }
            // 手前のポケット
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 14, bottomTrailingRadius: 14,
                                   topTrailingRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: empty ? [Color(hex: 0xDADCE5), Color(hex: 0xC3C6D2)]
                                                   : [Color(hex: 0x7373EE), Theme.accent],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 11, bottomTrailingRadius: 11,
                                           topTrailingRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .padding(4)
                )
                .overlay(
                    Text("\(stickers.count)")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                )
                .frame(width: 72, height: 40)
                .shadow(color: Color(hex: 0x1E1E3C).opacity(0.18), radius: 4, y: 3)
        }
        .frame(width: 76, height: 80)
        .scaleEffect(open ? 0.96 : 1)
    }
}
