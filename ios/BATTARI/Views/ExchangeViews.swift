import SwiftData
import SwiftUI

/// G5（交換待機）→ G6（交換確認）→ G7（ステッカー貼り付け）
struct ExchangeFlowView: View {
    let profile: MyProfile
    @EnvironmentObject private var auth: AuthService
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = ExchangeManager()
    /// G7で貼る、受け取ったばかりのステッカー
    @State private var placing: Sticker?
    @State private var saveError: String?

    var body: some View {
        Group {
            if let placing {
                PlaceStickerView(sticker: placing) { continueExchange in
                    if continueExchange {
                        self.placing = nil
                        manager.resume()
                    } else {
                        close()
                    }
                }
                .transition(.move(edge: .bottom))
            } else {
                switch manager.phase {
                case let .searching(lastEnd):
                    SearchingView(profile: profile, radio: manager.radio, lastEnd: saveError ?? lastEnd, onClose: close)
                case let .confirming(preview, thumbnail, waiting):
                    ConfirmView(preview: preview, thumbnail: thumbnail, waiting: waiting, transferring: false,
                                onAccept: manager.accept, onDecline: manager.decline)
                case .transferring:
                    ConfirmView(preview: lastPreview, thumbnail: lastThumbnail, waiting: true, transferring: true,
                                onAccept: {}, onDecline: manager.decline)
                case .completed:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: placing?.id)
        .task {
            #if DEBUG
            if let screen = DemoData.screen {
                if screen == "G7" { placing = try? context.fetch(FetchDescriptor<Sticker>()).first }
                if screen == "G6" { manager.debugShow(DemoData.confirming) }
                if screen != "G5" { return }
            }
            #endif
            // 開いた時点でアカウント状態を確認する。無効化・削除されていればログアウトしてG1へ
            if await auth.checkAccount() == .revoked { return close() }
            manager.start(as: ExchangeManager.Me(
                preview: ProfilePreview(displayName: profile.displayName, department: profile.department, grade: profile.grade),
                thumbnail: ImageTools.thumbnail(profile.iconImage),
                profile: ProfilePayload(uid: profile.uid, displayName: profile.displayName, department: profile.department,
                                        grade: profile.grade, message: profile.message),
                icon: profile.iconImage))
        }
        .onChange(of: manager.phase) { _, phase in
            switch phase {
            case let .confirming(preview, thumbnail, _):
                lastPreview = preview
                lastThumbnail = thumbnail
                saveError = nil
            case let .completed(received):
                do {
                    placing = try StickerStore.saveReceived(received.profile, icon: received.icon, in: context)
                } catch {
                    saveError = "ステッカーを保存できませんでした"
                    manager.resume()
                }
            default: break
            }
        }
        .onDisappear { manager.stop() }
    }

    @State private var lastPreview = ProfilePreview(displayName: "", department: "", grade: 1)
    @State private var lastThumbnail = Data()

    private func close() {
        manager.stop()
        dismiss()
    }
}

// MARK: - G5 交換待機

struct SearchingView: View {
    let profile: MyProfile
    let radio: ExchangeManager.Radio
    let lastEnd: String?
    let onClose: () -> Void
    @State private var pulse = false

    private var radioOK: Bool { radio == .poweredOn }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Label("閉じる", systemImage: "xmark").font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                Spacer()
            }
            .padding(.top, 8)

            Text("相手のスマホに近づけてください")
                .font(.system(size: 22, weight: .heavy))
                .padding(.top, 24)
            Text("スマホ同士をくっつけるくらいの距離で\n相手が見つかります")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            if let lastEnd {
                Text(lastEnd)
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
                    .padding(.top, 12)
            }

            Spacer()
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 150, height: 150)
                        .scaleEffect(pulse && radioOK ? 2.2 : 1)
                        .opacity(pulse && radioOK ? 0 : 0.9)
                        .animation(radioOK ? .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8) : .default,
                                   value: pulse)
                }
                StickerImage(image: profile.iconImage, size: 130)
            }
            .frame(height: 320)
            Text(radioOK ? "探しています…" : "Bluetoothを使えません")
                .font(.system(size: 16, weight: .bold))
            Spacer()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: radioOK ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
                VStack(alignment: .leading, spacing: 6) {
                    Text(radioMessage).fixedSize(horizontal: false, vertical: true)
                    if radio == .poweredOff || radio == .unauthorized {
                        Button("設定を開く") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .underline()
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(16)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .background(Theme.deepGradient.ignoresSafeArea())
        .onAppear { pulse = true }
    }

    private var radioMessage: String {
        switch radio {
        case .poweredOn: return "Bluetooth：オン　／　お互いにこの画面を開いてください"
        case .poweredOff: return "Bluetoothをオンにしてください"
        case .unauthorized: return "Bluetoothの使用が許可されていません。設定アプリで許可してください"
        case .unsupported: return "この端末はBluetooth Low Energyに対応していません"
        case .unknown: return "Bluetoothの状態を確認しています…"
        }
    }
}

// MARK: - G6 交換確認

struct ConfirmView: View {
    let preview: ProfilePreview
    let thumbnail: Data
    let waiting: Bool
    let transferring: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.deepGradient.ignoresSafeArea()
                UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36)
                    .fill(Theme.background)
                    .padding(.top, geo.size.height * 0.34)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Text("相手が見つかりました！")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, geo.size.height * 0.1)
                    StickerImage(image: thumbnail, size: 150)
                        .padding(.top, 28)
                    Text(preview.displayName)
                        .font(.system(size: 26, weight: .heavy))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 20)
                    Text("\(preview.department)　\(preview.grade)年")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.sub)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 6)
                    Text("ステッカーを交換しますか？")
                        .font(.system(size: 18, weight: .heavy))
                        .padding(.top, 28)
                    HStack(spacing: 8) {
                        if waiting { ProgressView().controlSize(.small) }
                        Text(transferring ? "交換しています…" : waiting ? "相手の承認を待っています" : "お互いが「交換する」を押すと交換されます")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.gray, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 14)

                    Spacer()
                    Button("交換する", action: onAccept)
                        .buttonStyle(PillButtonStyle())
                        .disabled(waiting) // 二重に送らない
                    Button("やめる", action: onDecline)
                        .buttonStyle(PillButtonStyle(kind: .gray))
                        .disabled(transferring)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - G7 ステッカー貼り付け

struct PlaceStickerView: View {
    let sticker: Sticker
    /// true: 貼って続けて交換（G5へ）／false: ここに貼る（G4へ）
    let onFinish: (_ continueExchange: Bool) -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \Sticker.zIndex) private var stickers: [Sticker]
    @State private var drag: CGSize = .zero
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 0) {
            Text("NEW STICKER")
                .font(.system(size: 13, weight: .heavy))
                .kerning(2)
                .foregroundStyle(Theme.accent)
                .padding(.top, 16)
            Text("\(sticker.displayName)さんのステッカー")
                .font(.system(size: 22, weight: .heavy))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 6)
            Text("好きな場所にドラッグして貼ろう")
                .font(.system(size: 14))
                .foregroundStyle(Theme.sub)
                .padding(.top, 6)

            LaptopLid { size in
                StickerCanvas(stickers: stickers, size: size, hidden: [sticker.id])
                newSticker(in: size)
            }
            .padding(.top, 20)
            .padding(.horizontal, 4)

            Spacer(minLength: 12)
            Button("ここに貼る") { finish(continueExchange: false) }
                .buttonStyle(PillButtonStyle())
            Button("貼って続けて交換") { finish(continueExchange: true) }
                .buttonStyle(PillButtonStyle(kind: .ghost))
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .background(Theme.background.ignoresSafeArea())
    }

    private func newSticker(in size: CGSize) -> some View {
        let side = size.width * StickerLayout.stickerSize
        let center = CGPoint(x: sticker.positionX * size.width, y: sticker.positionY * size.height)
        return ZStack {
            // 貼る位置の目安
            Circle()
                .strokeBorder(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .frame(width: side * 1.15, height: side * 1.15)
                .position(center)
            StickerImage(image: sticker.iconImage, shapeKey: sticker.partnerUid, size: side * 1.1, lifted: dragging)
                .rotationEffect(.degrees(sticker.rotation))
                .position(center)
                .offset(drag)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragging = true
                            drag = value.translation
                        }
                        .onEnded { value in
                            let x = sticker.positionX + value.translation.width / size.width
                            let y = sticker.positionY + value.translation.height / size.height
                            let p = StickerLayout.clamp(x: x, y: y)
                            sticker.positionX = p.x // 位置の確定はボタンで保存する
                            sticker.positionY = p.y
                            drag = .zero
                            withAnimation(.spring(duration: 0.2)) { dragging = false }
                        }
                )
                .accessibilityLabel("新しいステッカー。ドラッグして位置を決めます")
        }
        .zIndex(100_000)
    }

    private func finish(continueExchange: Bool) {
        StickerStore.place(sticker, x: sticker.positionX, y: sticker.positionY, in: context)
        onFinish(continueExchange)
    }
}
