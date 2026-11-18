import SwiftData
import SwiftUI

@main
struct BATTARIApp: App {
    @StateObject private var auth: AuthService
    private let container: ModelContainer

    init() {
        #if DEBUG
        // 起動引数 -demo YES: サンプルデータで画面を確認する（Firebase・端末内データは使わない）
        if UserDefaults.standard.bool(forKey: "demo") {
            _auth = StateObject(wrappedValue: AuthService(demoUid: DemoData.uid))
            container = DemoData.container()
            return
        }
        #endif
        _auth = StateObject(wrappedValue: AuthService(configured: AuthService.configureFirebase()))
        container = try! ModelContainer(for: MyProfile.self, Sticker.self)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

/// ログイン状態とプロフィールの有無で、最初に出す画面を決める
struct RootView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        switch auth.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        case .notConfigured:
            NotConfiguredView()
        case .signedOut:
            AuthFlowView()
        case let .signedIn(uid):
            #if DEBUG
            if DemoData.screen == "G1" { AuthFlowView() } else { SignedInView(uid: uid) }
            #else
            SignedInView(uid: uid)
            #endif
        }
    }
}

/// ログイン済み。プロフィールがなければ作成（G3）、あればホーム（G4）
struct SignedInView: View {
    let uid: String
    @EnvironmentObject private var auth: AuthService
    @Environment(\.modelContext) private var context
    @Query private var profiles: [MyProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                HomeView(profile: profile)
            } else {
                ProfileEditView(mode: .create(uid: uid))
            }
        }
        .task(id: uid) {
            // 別のアカウントでログインし直した場合は、端末内のプロフィールをそのアカウントに付け替える
            if let profile = profiles.first, profile.uid != uid {
                profile.uid = uid
                try? context.save()
            }
            // 起動時にアカウントが無効化・削除されていないか確かめる（無効ならG1へ）
            _ = await auth.checkAccount()
        }
    }
}

struct NotConfiguredView: View {
    #if DEBUG
    @EnvironmentObject private var auth: AuthService
    #endif

    var body: some View {
        VStack(spacing: 16) {
            Logo()
            Text("Firebaseの設定ファイルがありません")
                .font(.headline)
            Text("GoogleService-Info.plist を ios/BATTARI/ に置いてから、もう一度ビルドしてください。")
                .font(.subheadline)
                .foregroundStyle(Theme.sub)
                .multilineTextAlignment(.center)
            #if DEBUG
            Button("ログインせずに試す") { auth.startTrial() }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 24)
            Text("開発用です。認証を飛ばして、プロフィール作成とBLEでの交換を試せます。データはこの端末に保存されます。")
                .font(.footnote)
                .foregroundStyle(Theme.sub)
                .multilineTextAlignment(.center)
            #endif
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
