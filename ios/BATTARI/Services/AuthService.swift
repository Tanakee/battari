import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import Foundation

/// 学内メール認証（G1・G2）とアカウント状態の確認
@MainActor
final class AuthService: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(uid: String)
        /// GoogleService-Info.plist がない
        case notConfigured
    }

    enum AccountStatus { case active, revoked, offline }

    /// requestOtp の結果
    enum Sent { case sent(resendAfter: Int), alreadySent(retryAfter: Int) }

    struct Failure: Error, Equatable {
        let message: String
    }

    @Published private(set) var state: State = .loading
    private var listener: AuthStateDidChangeListenerHandle?
    /// デモモード（DEBUGのみ）。Firebaseを使わずにログイン済みとして扱う
    private var demo = false
    private let region = "asia-northeast1"

    /// アプリ起動時に一度だけ呼ぶ
    static func configureFirebase() -> Bool {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        FirebaseApp.configure()
        // ローカルの Firebase エミュレータにつなぐ（スキームの起動引数 -useEmulator YES）
        if UserDefaults.standard.bool(forKey: "useEmulator") {
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            Functions.functions(region: "asia-northeast1").useEmulator(withHost: "127.0.0.1", port: 5001)
        }
        return true
    }

    init(configured: Bool) {
        guard configured else {
            state = .notConfigured
            return
        }
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.state = user.map { .signedIn(uid: $0.uid) } ?? .signedOut
            }
        }
    }

    #if DEBUG
    init(demoUid: String) {
        demo = true
        state = .signedIn(uid: demoUid)
    }
    #endif

    private var functions: Functions { Functions.functions(region: region) }

    // MARK: - G1

    func requestCode(email: String) async throws -> Sent {
        do {
            let result = try await functions.httpsCallable("requestOtp").call(["email": email, "purpose": "app"])
            let after = (result.data as? [String: Any])?["resendAfter"] as? Int ?? Limits.resendSeconds
            return .sent(resendAfter: after)
        } catch {
            let info = Self.details(of: error)
            if info.reason == "too-soon" {
                // 前に送ったコードがまだ使えるので、そのままG2へ進める
                return .alreadySent(retryAfter: info.int("retryAfter") ?? Limits.resendSeconds)
            }
            throw Failure(message: "送信できませんでした。時間をおいて再度お試しください")
        }
    }

    // MARK: - G2

    func verify(email: String, code: String) async throws {
        let token: String
        do {
            let result = try await functions.httpsCallable("verifyOtp").call(["email": email, "code": code, "purpose": "app"])
            guard let t = (result.data as? [String: Any])?["token"] as? String else {
                throw Failure(message: "認証できませんでした。時間をおいて再度お試しください")
            }
            token = t
        } catch let failure as Failure {
            throw failure
        } catch {
            let info = Self.details(of: error)
            switch info.reason {
            case "mismatch": throw Failure(message: "コードが正しくありません（残り\(info.int("remaining") ?? 0)回）")
            case "expired": throw Failure(message: "有効期限が切れています。再送信してください")
            case "locked": throw Failure(message: "入力回数の上限に達しました。再送信してください")
            case "disabled": throw Failure(message: "このアカウントは利用できません")
            default: throw Failure(message: "認証できませんでした。時間をおいて再度お試しください")
            }
        }
        do {
            try await Auth.auth().signIn(withCustomToken: token)
        } catch {
            throw Failure(message: "ログインできませんでした。時間をおいて再度お試しください")
        }
    }

    // MARK: - アカウント状態（起動時・G5を開いたとき）

    /// IDトークンを更新して、無効化・削除されていないか確かめる。無効ならログアウトする
    func checkAccount() async -> AccountStatus {
        if demo { return .active }
        guard let user = Auth.auth().currentUser else { return .revoked }
        do {
            _ = try await user.getIDTokenResult(forcingRefresh: true)
            return .active
        } catch {
            let code = AuthErrorCode(rawValue: (error as NSError).code)
            switch code {
            case .userDisabled, .userNotFound, .userTokenExpired, .invalidUserToken:
                try? Auth.auth().signOut()
                return .revoked
            default:
                // 通信できない場合は、イベント会場での利用を優先して交換を許可する
                return .offline
            }
        }
    }

    // MARK: - エラーの読み取り

    private struct Details {
        let reason: String
        let values: [String: Any]
        func int(_ key: String) -> Int? { (values[key] as? NSNumber)?.intValue }
    }

    private static func details(of error: Error) -> Details {
        let ns = error as NSError
        let values = (ns.domain == FunctionsErrorDomain ? ns.userInfo[FunctionsErrorDetailsKey] : nil) as? [String: Any] ?? [:]
        return Details(reason: values["reason"] as? String ?? "", values: values)
    }
}
