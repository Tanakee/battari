import SwiftUI

/// G4 天板の下のステッカーケース。押すとステッカーが横に広がり、貼るものを選ぶ。
/// 見ているステッカーと両隣は離して並べ、それより遠いものは重ねて詰める
struct StickerCaseBar: View {
    let stickers: [Sticker]
    @Binding var open: Bool
    let namespace: Namespace.ID
    let onPlace: (Sticker) -> Void
    let onDetail: (Sticker) -> Void

    /// 見ているステッカーの番号（ドラッグ中は小数）
    @State private var focus: Double = 0
    @State private var dragX: CGFloat = 0

    private let caseWidth: CGFloat = 76
    private let side: CGFloat = 52
    /// 重ならずに並ぶときの間隔
    private var full: CGFloat { side + 16 }
    /// 重ねて詰めるときの間隔
    private var packed: CGFloat { side * 0.28 }

    private var current: Double {
        let raw = focus - Double(dragX / full)
        let last = Double(max(stickers.count - 1, 0))
        // 端より先へは少しだけ引っぱれる
        if raw < 0 { return raw / 3 }
        if raw > last { return last + (raw - last) / 3 }
        return raw
    }

    var body: some View {
        GeometryReader { geo in
            let stripLeft = caseWidth + 12
            // 見ているステッカーの位置。最初のほうは左に寄せ、左側が埋まってきたら中央で止める
            let focusX = min(stripLeft + side / 2 + abs(offset(-current)), stripLeft + (geo.size.width - stripLeft) / 2)
            ZStack(alignment: .leading) {
                Text("天板のステッカーは\nタップで詳細・長押しで移動")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.sub)
                    .lineSpacing(2)
                    .padding(.leading, caseWidth + 12)
                    .opacity(open ? 0 : 1)

                if open {
                    Text(stickers.isEmpty ? "しまってあるステッカーはありません" : "タップで貼る・長押しで詳細")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                        .padding(.leading, caseWidth + 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }

                ForEach(Array(stickers.enumerated()), id: \.element.id) { i, sticker in
                    let d = Double(i) - current
                    StickerImage(image: sticker.iconImage, shapeKey: sticker.partnerUid, size: side)
                        .rotationEffect(.degrees(sticker.rotation))
                        .scaleEffect(open ? scale(d) : 0.4)
                        .matchedGeometryEffect(id: sticker.id, in: namespace)
                        .contentShape(Circle())
                        .onTapGesture { tap(i, sticker) }
                        .onLongPressGesture(minimumDuration: 0.4) { onDetail(sticker) }
                        .position(x: open ? focusX + offset(d) : caseWidth / 2, y: geo.size.height / 2 + 6)
                        .opacity(open ? (focusX + offset(d) < stripLeft || focusX + offset(d) > geo.size.width - side / 2 + 4 ? 0 : 1) : 0)
                        .zIndex(100 - abs(d))
                        .allowsHitTesting(open)
                        .animation(.spring(duration: 0.45, bounce: 0.2).delay(open ? Double(min(i, 6)) * 0.03 : 0), value: open)
                        .accessibilityLabel("\(sticker.displayName)さんのステッカー。タップで天板に貼る")
                        .accessibilityAddTraits(.isButton)
                }

                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { open.toggle() }
                } label: {
                    StickerCaseIcon(stickers: stickers, open: open)
                }
                .buttonStyle(.plain)
                .frame(width: caseWidth)
                .zIndex(200) // 広がるステッカーはケースの後ろから出てくる
                .accessibilityLabel(open ? "ステッカーケースを閉じる" : "ステッカーケースを開く（\(stickers.count)枚）")
            }
            .contentShape(Rectangle())
            .gesture(open ? scrollGesture : nil)
        }
        .frame(height: 92)
        .sensoryFeedback(.selection, trigger: Int(current.rounded()))
        .onChange(of: stickers.count) { _, count in
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                focus = min(focus, Double(max(count - 1, 0)))
                // 最後の1枚を貼ったら閉じる
                if count == 0 { open = false }
            }
        }
    }

    /// 見ているステッカーからの距離 d に応じた横位置。|d|≦1 は離して並べ、それより先は詰めて重ねる
    private func offset(_ d: Double) -> CGFloat {
        let a = abs(d)
        let x = a <= 1 ? CGFloat(a) * full : full + CGFloat(a - 1) * packed
        return d < 0 ? -x : x
    }

    /// 見ているステッカーは大きく、重なっているものは小さく。スワイプ中もなめらかに変わるよう距離から計算する
    private func scale(_ d: Double) -> CGFloat {
        let a = abs(d)
        if a <= 1 { return 1 + 0.2 * CGFloat(1 - a) }
        return 1 - 0.12 * CGFloat(min(a - 1, 1))
    }

    private func tap(_ i: Int, _ sticker: Sticker) {
        if abs(Double(i) - focus) <= 1 {
            onPlace(sticker)
        } else {
            // 重なっているものは、まず見えるところまで送る
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { focus = Double(i) }
        }
    }

    private var scrollGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { dragX = $0.translation.width }
            .onEnded { value in
                let last = Double(max(stickers.count - 1, 0))
                let target = (focus - Double(value.predictedEndTranslation.width / full)).rounded()
                withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                    focus = min(max(target, 0), last)
                    dragX = 0
                }
            }
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
