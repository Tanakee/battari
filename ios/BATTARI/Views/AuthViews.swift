import SwiftUI

/// G1（メールアドレス入力）→ G2（認証コード入力）
struct AuthFlowView: View {
    @State private var path: [CodeRoute] = []
    /// G2から戻ったときも残しておく
    @State private var studentId = ""

    var body: some View {
        NavigationStack(path: $path) {
            EmailEntryView(studentId: $studentId) { email, wait in
                path.append(CodeRoute(email: email, wait: wait))
            }
            .navigationDestination(for: CodeRoute.self) { route in
                CodeEntryView(email: route.email, initialWait: route.wait)
            }
        }
    }
}

struct CodeRoute: Hashable {
    let email: String
    let wait: Int
}

// MARK: - G1 メールアドレス入力

struct EmailEntryView: View {
    @Binding var studentId: String
    let onSent: (_ email: String, _ resendWait: Int) -> Void

    @EnvironmentObject private var auth: AuthService
    @FocusState private var focused: Bool
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 56)
            Logo(size: 40)
            Text("話した相手と、スマホを近づけて\nステッカーを交換しよう")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.sub)
                .padding(.top, 8)

            Text("学籍メールで登録")
                .font(.system(size: 22, weight: .heavy))
                .padding(.top, 48)
            Text("学籍番号を入力すると、学籍メールに6桁の認証コードを送ります。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.sub)
                .lineSpacing(4)
                .padding(.top, 8)

            FieldLabel(text: "学籍番号", required: true).padding(.top, 28).padding(.bottom, 8)
            HStack(spacing: 4) {
                TextField("s2301234", text: $studentId)
                    .font(.system(size: 17, weight: .semibold))
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .onChange(of: studentId) { _, new in
                        studentId = Validation.truncated(new, to: Limits.studentIdLength)
                    }
                Text("@\(School.mailDomain)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .fieldStyle(focused: focused, error: error != nil)
            ErrorText(text: error).padding(.top, 8)

            Spacer()
            Button(action: send) {
                if sending { ProgressView().tint(.white) } else { Text("認証コードを送信") }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(studentId.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onTapGesture { focused = false }
    }

    private func send() {
        guard !sending else { return }
        guard case let .valid(id) = Validation.studentId(studentId) else {
            error = Validation.studentId(studentId).errorMessage
            return
        }
        error = nil
        sending = true
        let email = Validation.studentEmail(id)
        Task {
            defer { sending = false }
            do {
                switch try await auth.requestCode(email: email) {
                case let .sent(wait), let .alreadySent(wait):
                    onSent(email, wait)
                }
            } catch {
                self.error = (error as? AuthService.Failure)?.message
            }
        }
    }
}

// MARK: - G2 認証コード入力

struct CodeEntryView: View {
    let email: String
    let initialWait: Int

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var code = ""
    @State private var error: String?
    @State private var info: String?
    @State private var verifying = false
    @State private var resendAt = Date()
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var waitSeconds: Int { max(0, Int(ceil(resendAt.timeIntervalSince(now)))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Label("戻る", systemImage: "chevron.left").font(.system(size: 16, weight: .semibold))
            }
            .padding(.top, 8)

            Text("認証コードを入力")
                .font(.system(size: 26, weight: .heavy))
                .padding(.top, 32)
            Text(email)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("に届いた6桁のコードを入力してください。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.sub)

            codeBoxes.padding(.top, 24)
            ErrorText(text: error).padding(.top, 10)
            if let info {
                Text(info).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x1B8A4B)).padding(.top, 10)
            }

            HStack(spacing: 4) {
                Text("コードが届かない場合").foregroundStyle(Theme.sub)
                Button(waitSeconds > 0 ? "再送信（\(waitSeconds)秒後）" : "再送信", action: resend)
                    .font(.system(size: 14, weight: .bold))
                    .disabled(waitSeconds > 0)
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            Spacer()
            Button(action: verify) {
                if verifying { ProgressView().tint(.white) } else { Text("認証する") }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!Validation.isOtp(code) || verifying)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            resendAt = Date().addingTimeInterval(TimeInterval(initialWait))
            focused = true
        }
        .onReceive(ticker) { now = $0 }
    }

    /// 6マスの見た目。入力は見えない TextField が受ける（ワンタイムコードの自動入力に対応）
    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(Limits.otpLength))
                    if digits != new { code = digits }
                    if !digits.isEmpty { error = nil }
                }
            HStack(spacing: 8) {
                ForEach(0..<Limits.otpLength, id: \.self) { i in
                    let chars = Array(code)
                    let active = focused && i == min(chars.count, Limits.otpLength - 1)
                    Text(i < chars.count ? String(chars[i]) : "")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(active ? Theme.accent : Theme.fieldBorder, lineWidth: active ? 2 : 1.5))
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .accessibilityLabel("認証コード")
    }

    private func verify() {
        guard Validation.isOtp(code), !verifying else { return }
        verifying = true
        info = nil
        Task {
            defer { verifying = false }
            do {
                try await auth.verify(email: email, code: code)
                // 成功するとログイン状態が変わり、RootView がG3かG4を表示する
            } catch {
                self.error = (error as? AuthService.Failure)?.message
                code = "" // 入力したコードを消して1マス目から入れ直してもらう
                focused = true
            }
        }
    }

    private func resend() {
        error = nil
        info = nil
        Task {
            do {
                switch try await auth.requestCode(email: email) {
                case let .sent(wait):
                    info = "再送信しました"
                    code = ""
                    resendAt = Date().addingTimeInterval(TimeInterval(wait))
                case let .alreadySent(wait):
                    resendAt = Date().addingTimeInterval(TimeInterval(wait))
                }
            } catch {
                self.error = (error as? AuthService.Failure)?.message
            }
        }
    }
}
