import SwiftUI

/// 白いふち付きのステッカー。形（丸・角丸）は相手ごとに決まる
struct StickerImage: View {
    let image: Data
    /// 形を決めるためのキー（相手のUIDなど）
    var shapeKey: String = ""
    var size: CGFloat
    var lifted = false

    private var isRounded: Bool { Palette.stableHash(shapeKey) % 3 == 1 }

    var body: some View {
        let border = max(3, size * 0.045)
        let shape = isRounded ? AnyShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)) : AnyShape(Circle())
        Group {
            if let ui = UIImage(data: image) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Theme.gray
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white, lineWidth: border))
        .shadow(color: .black.opacity(lifted ? 0.35 : 0.28), radius: lifted ? 12 : 4, y: lifted ? 8 : 3)
        .scaleEffect(lifted ? 1.08 : 1)
    }
}

/// 仮想ノートパソコンの天板（ヒンジ付き）
struct LaptopLid<Content: View>: View {
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xD9DCE3), Color(hex: 0xC3C7D0), Color(hex: 0xB7BBC5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 2))
                        .shadow(color: Color(hex: 0x1E1E3C).opacity(0.25), radius: 15, y: 14)
                    Circle().fill(Color.white.opacity(0.35)).frame(width: 38, height: 38)
                    content(geo.size)
                }
            }
            .aspectRatio(StickerLayout.lidAspect, contentMode: .fit)
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                .fill(LinearGradient(colors: [Color(hex: 0x9EA3AE), Color(hex: 0xC9CCD4)], startPoint: .top, endPoint: .bottom))
                .frame(height: 12)
                .padding(.horizontal, 26)
        }
    }
}

/// 天板の上にステッカーを並べる（G4・G7）
struct StickerCanvas: View {
    let stickers: [Sticker]
    var size: CGSize
    /// G4: タップで詳細・長押しで移動。G7では nil（貼り済みのステッカーは動かさない）
    var onTap: ((Sticker) -> Void)?
    var onMove: ((Sticker, Double, Double) -> Void)?
    var hidden: Set<UUID> = []

    @State private var draggingId: UUID?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        let side = size.width * StickerLayout.stickerSize
        ForEach(stickers.sorted { $0.zIndex < $1.zIndex }) { sticker in
            if !hidden.contains(sticker.id) {
                let dragging = draggingId == sticker.id
                StickerImage(image: sticker.iconImage, shapeKey: sticker.partnerUid, size: side, lifted: dragging)
                    .rotationEffect(.degrees(sticker.rotation))
                    .position(x: sticker.positionX * size.width, y: sticker.positionY * size.height)
                    .offset(dragging ? dragOffset : .zero)
                    .zIndex(dragging ? 10_000 : Double(sticker.zIndex))
                    .onTapGesture { onTap?(sticker) }
                    .gesture(moveGesture(for: sticker), including: onMove == nil ? .none : .all)
                    .accessibilityLabel("\(sticker.displayName)さんのステッカー")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func moveGesture(for sticker: Sticker) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture())
            .onChanged { value in
                switch value {
                case .first(true):
                    withAnimation(.spring(duration: 0.2)) { draggingId = sticker.id }
                case let .second(true, drag?):
                    draggingId = sticker.id
                    dragOffset = drag.translation
                default: break
                }
            }
            .onEnded { value in
                if case let .second(true, drag?) = value {
                    let x = sticker.positionX + drag.translation.width / size.width
                    let y = sticker.positionY + drag.translation.height / size.height
                    onMove?(sticker, x, y)
                }
                withAnimation(.spring(duration: 0.2)) {
                    draggingId = nil
                    dragOffset = .zero
                }
            }
    }
}
