# BATTARI

システム開発実習で作る、スマホを近づけるだけでプロフィールを交換し、相手のアイコンを仮想ノートパソコンにステッカーとして貼っていくiOSアプリ。

## 構成

| ディレクトリ | 内容 | 画面 |
| --- | --- | --- |
| `ios/` | iOSアプリ（Swift / SwiftUI / CoreBluetooth / SwiftData） | G1〜G8 |
| `functions/` | Cloud Functions（TypeScript）。認証コードの発行・検証、ユーザー管理 | — |
| `admin/` | 管理画面（Firebase Hosting、素のHTML/JS） | W1〜W3 |
| `docs/` | 企画書・設計書 | — |

```
iPhone ──BLE── iPhone          （プロフィール交換は端末同士だけ。サーバーに送らない）
  │
  └─ Cloud Functions ─┬─ Firestore（otpCodes・admins）
       │               ├─ Firebase Auth（ユーザーアカウント）
管理画面 ┘               └─ SendGrid（認証コードのメール）
```

### BLEでの交換のしくみ（`ios/BATTARI/BLE/`）

1. G5を開いた端末は、アドバタイズ（見つけてもらう）とスキャン（探す）を同時に行う。アドバタイズ名はランダムな6桁のトークン
2. RSSIが -45dBm 以上の状態が1秒続いた相手を「近づけた相手」とする（`ProximityDetector`）
3. トークンの小さい方がセントラルとして接続し、もう一方はペリフェラルとして待つ
4. 接続後、互いに表示名・学科・学年・小さいアイコンを送り合い、G6に表示する（`ExchangeSession`）
5. 双方が「交換する」を押したら、プロフィール（JSON）とアイコン（JPEG）をMTUごとに分割して送る（`Framing` / `Reassembler`）
6. 交換を終えた相手は、一度はっきり離れるか20秒たつまで再検知しない（続けて交換するとき同じ相手を拾わないため）

## セットアップ

### 1. Firebase プロジェクト

1. Firebaseコンソールでプロジェクトを作り、**Blazeプラン**にする（Cloud Functions とシークレットに必要）
2. Authentication・Firestore（ネイティブモード、`asia-northeast1`）・Hosting を有効にする
3. `.firebaserc.example` を `.firebaserc` にコピーし、プロジェクトIDを書く
4. Firestore の `otpCodes` コレクションに、`expiresAt` フィールドの **TTLポリシー** を設定する（期限切れのコードを自動で消す）
5. Cloud Functions の実行サービスアカウント（`<プロジェクト番号>-compute@developer.gserviceaccount.com`）に **サービス アカウント トークン作成者** のロールを付ける（カスタムトークンの発行に必要）
6. 管理者を登録する：Firestore に `admins/{メールアドレス}` を作り、`name`（文字列）と `createdAt`（タイムスタンプ）を入れる

### 2. メール送信（SendGrid）

```sh
firebase functions:secrets:set SENDGRID_API_KEY   # SendGridのAPIキー
```

デプロイ時に `MAIL_FROM`（SendGridで認証済みの送信元アドレス）を聞かれるので入力する。

### 3. デプロイ

```sh
cd functions && npm install && cd ..
firebase deploy --only functions,firestore:rules,hosting
```

### 4. iOSアプリ

```sh
brew install xcodegen
cd ios && xcodegen generate && open BATTARI.xcodeproj
```

- Firebaseコンソールで iOS アプリ（バンドルID `io.github.tanakee.battari`）を追加し、`GoogleService-Info.plist` を `ios/BATTARI/` に置く（公開しないため `.gitignore` 済み）
- BLEはシミュレータで動かないので、**実機2台**で試す

### 実機で動かす

1. `ios/Local.xcconfig` を作り、自分のチームIDを書く（`.gitignore` 済み）。チームIDは Xcode の Settings → Accounts で確認できる
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```
2. `cd ios && xcodegen generate && open BATTARI.xcodeproj` で開き、iPhoneを選んで実行する
3. iPhone側で「設定 → 一般 → VPNとデバイス管理」から開発元を信頼する（初回のみ）

`GoogleService-Info.plist` を置いていなくても、DEBUGビルドなら最初の画面の **「ログインせずに試す」** で認証を飛ばせる。プロフィール作成・ステッカー台紙・BLEでの交換を、Firebaseなしで試せる（UIDは端末ごとにランダム、データは端末に保存）。

## 開発

| やること | コマンド |
| --- | --- |
| Functions のテスト | `cd functions && npm test` |
| iOS のテスト | `cd ios && xcodebuild test -project BATTARI.xcodeproj -scheme BATTARI -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |
| エミュレータ（要Java） | `firebase emulators:start --only functions,firestore,auth,hosting`。iOSは起動引数 `-useEmulator YES` でつなぐ。SendGridのキーがなければ認証コードはFunctionsのログに出る |
| 実機にサンプルのステッカーを足す（DEBUGのみ） | 起動引数 `-sampleStickers 2`（1〜4）。`xcrun devicectl device process launch --device <ID> io.github.tanakee.battari -- -sampleStickers 2` でも可 |
| 画面だけ確認（DEBUGのみ） | iOSの起動引数 `-demo YES`（サンプルデータで起動）、`-demoScreen G3` などで指定の画面を開く |

## ドキュメント（`docs/`）

| ファイル | 内容 |
| --- | --- |
| `00企画書_田中渓都.docx` | 企画書 |
| `01_画面設計書(画面一覧・画面遷移図)_田中渓都.xlsx` | 画面一覧・画面遷移図（v1.2） |
| `02_画面設計書(画面レイアウト)_田中渓都.xlsx` | 画面レイアウト（v1.2） |
| `03_データベース設計書_田中渓都.xlsx` | E-R図・CRUD図・テーブル定義（v1.2） |
| `システム構成図_v1.2.drawio` / `.png` | システム構成図 |
| `設計書ソース/` | 設計書を生成するスクリプト（`spec.py`, `build01〜03.py`, `xldraw.py`）と画面モック（`mock/`） |

`build01〜03.py` は授業で配布された設計書テンプレートを `docs/templates/`から読み込む。テンプレートはこのリポジトリに含めていない。

## 未確定事項

- 学科の選択肢は仮の名称（`ios/BATTARI/App/Constants.swift` の `Departments` と、`docs/設計書ソース/spec.py` の `DEPARTMENTS`）。正式な学科名称一覧が決まったら両方を差し替える
- RSSIの閾値（-45dBm）は暫定値。実機で調整する（`Exchange.rssiThreshold`）
