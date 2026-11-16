import os, sys, copy
import openpyxl
from openpyxl.styles import Border, Side, Alignment, Font
sys.path.insert(0, os.path.dirname(__file__))
from spec import SYSTEM, AUTHOR, DATE, VERSION
from xldraw import Drawing, inject

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "templates", "03_データベース設計書.xlsx")
OUT = sys.argv[1]
thin = Side(style="thin")
BOX = Border(left=thin, right=thin, top=thin, bottom=thin)

# ---------------- エンティティ定義 ----------------
# (論理名, 物理名, 種別, 保存先, 定義, 概要, 属性[], インデックス[], FK側[], PK側[])
# 属性: (論理名, 物理名, データ型, NotNull, デフォルト, 備考)
ENT = [
    ("ユーザーアカウント", "users", "マスタ", "Firebase Auth",
     "本学学生（および管理者）のアカウント情報を管理する",
     "Firebase Authが保持するアカウント情報（UserRecord）。Firestoreには重複して保存しない",
     [("ユーザーID", "uid", "string(128)", "○", "自動採番", "PK。Firebase Authが発行する"),
      ("メールアドレス", "email", "string(254)", "○", "なし", "@s.asojuku.ac.jp 固定（管理者を除く）。一意"),
      ("メール確認済み", "emailVerified", "boolean", "○", "true", "OTP検証に成功してから作成するため常にtrue"),
      ("無効フラグ", "disabled", "boolean", "○", "false", "管理者が無効化するとtrue。trueの間はログイン不可"),
      ("管理者権限", "customClaims.admin", "boolean", "", "なし", "管理者のみtrue。ユーザー一覧には表示しない"),
      ("登録日時", "metadata.creationTime", "timestamp", "○", "作成時刻", "Firebase Authが自動で設定する"),
      ("最終ログイン日時", "metadata.lastSignInTime", "timestamp", "", "なし", "Firebase Authが自動で設定する")],
     [("（標準）", "1: email（昇順）", "○", "Firebase Authがメールアドレスの一意性を保証する")],
     [],
     [("所有する", "uid", "自分のプロフィール", "uid"),
      ("交換相手として記録される", "uid", "交換したステッカー", "partnerUid"),
      ]),
    ("管理者", "admins", "マスタ", "Firestore",
     "管理画面にログインできる管理者を管理する",
     "管理画面にログインできる管理者のメールアドレス一覧。Firebaseコンソールから手動で登録する",
     [("メールアドレス", "email", "string(254)", "○", "なし", "PK。ドキュメントIDとして使用する"),
      ("管理者名", "name", "string(50)", "○", "なし", ""),
      ("登録日時", "createdAt", "timestamp", "○", "サーバー時刻", "")],
     [("（ドキュメントID）", "1: email（昇順）", "○", "ドキュメントIDのため一意")],
     [],
     []),
    ("OTPコード", "otpCodes", "トランザクション", "Firestore",
     "送信した認証コード（OTP）を一時的に管理する",
     "学内メール認証・管理者ログインで送信した認証コードを一時保存する。検証成功時・期限切れ時に削除する",
     [("メールアドレス", "email", "string(254)", "○", "なし", "PK。ドキュメントIDとして使用。再送時は上書きする"),
      ("コードハッシュ", "codeHash", "string(64)", "○", "なし", "6桁コードのSHA-256ハッシュ。平文は保存しない"),
      ("用途", "purpose", "string(5)", "○", "app", "app：学生の登録／admin：管理者ログイン"),
      ("有効期限", "expiresAt", "timestamp", "○", "発行から10分後", ""),
      ("試行回数", "attemptCount", "number", "○", "0", "検証に失敗するたびに加算。5回で無効"),
      ("発行日時", "createdAt", "timestamp", "○", "サーバー時刻", "再送信の間隔（60秒）の判定に使う")],
     [("（ドキュメントID）", "1: email（昇順）", "○", "ドキュメントIDのため一意"),
      ("TTLポリシー", "1: expiresAt（昇順）", "×", "インデックスではなくFirestoreのTTL設定。期限切れのドキュメントを自動で削除する")],
     [],
     []),
    ("自分のプロフィール", "MyProfile", "マスタ", "端末内（SwiftData）",
     "端末の持ち主のプロフィールを管理する",
     "端末内に1件だけ保存する自分のプロフィール。交換時にBLEで相手へ送る",
     [("プロフィールID", "id", "UUID", "○", "UUID()", "PK"),
      ("ユーザーID", "uid", "String(128)", "○", "なし", "ログイン中のFirebase AuthのUID。交換時に相手へ送る。一意"),
      ("表示名", "displayName", "String(20)", "○", "なし", ""),
      ("学科", "department", "String(30)", "○", "なし", "本学の学科一覧から選ぶ（選択肢は画面レイアウトG3の学科選択を参照）"),
      ("学年", "grade", "Int", "○", "1", "1〜4"),
      ("ひとこと", "message", "String(50)", "", "空文字", "任意"),
      ("アイコン画像", "iconImage", "Data", "○", "頭文字から生成", "JPEG・256×256px（約20KB以内）。未選択時は表示名の頭文字から画像を生成して保存する"),
      ("更新日時", "updatedAt", "Date", "○", "Date()", "")],
     [("idx_uid", "1: uid（昇順）", "○", "1端末1件を保証する（@Attribute(.unique)）。作成時に既存レコードがあれば更新する")],
     [("ログイン中のユーザーである", "uid", "ユーザーアカウント", "uid")],
     []),
    ("交換したステッカー", "Sticker", "トランザクション", "端末内（SwiftData）",
     "交換した相手のプロフィールと貼り付け位置を管理する",
     "交換した相手のプロフィール（交換時点のスナップショット）と、仮想ノートパソコン上の貼り付け位置を保存する。交換が成立した時点で空いている位置に仮に保存し、G7（ステッカー貼り付け）では位置だけを更新する",
     [("ステッカーID", "id", "UUID", "○", "UUID()", "PK"),
      ("相手ユーザーID", "partnerUid", "String(128)", "○", "なし", "相手のUID。同じ相手と再交換した場合は上書きする"),
      ("表示名", "displayName", "String(20)", "○", "なし", "交換時点の値"),
      ("学科", "department", "String(30)", "○", "なし", "交換時点の値"),
      ("学年", "grade", "Int", "○", "なし", "交換時点の値"),
      ("ひとこと", "message", "String(50)", "", "空文字", "交換時点の値"),
      ("アイコン画像", "iconImage", "Data", "○", "なし", "交換時点の値（JPEG）"),
      ("交換日時", "exchangedAt", "Date", "○", "Date()", "再交換時は更新する"),
      ("貼り付け位置X", "positionX", "Double", "○", "空いている位置", "天板の左端0.0〜右端1.0の相対座標。受信時に自動で設定し、G7で確定する"),
      ("貼り付け位置Y", "positionY", "Double", "○", "空いている位置", "天板の上端0.0〜下端1.0の相対座標。受信時に自動で設定し、G7で確定する"),
      ("回転角度", "rotation", "Double", "○", "0", "単位は度。貼るときに±15度の範囲で傾ける"),
      ("重なり順", "zIndex", "Int", "○", "0", "大きいほど前面。最後に貼った・動かしたものを最大にする")],
     [("idx_partnerUid", "1: partnerUid（昇順）", "○", "同じ相手の重複を防ぐ（@Attribute(.unique)）")],
     [("交換相手である", "partnerUid", "ユーザーアカウント", "uid")],
     []),
]

wb = openpyxl.load_workbook(SRC)
tmpl = wb["users"]
tmpl.title = "_tmpl"
for n in list(wb.sheetnames):
    if n not in ("_tmpl", "E-Rモデル　　エンティティ一覧", "CRUD図 "):
        del wb[n]

# ------- エンティティ定義書シート -------
attr_style = {c: copy.copy(tmpl[f"{c}11"]._style) for c in "ABCDEFGH"}
idx_style = {c: copy.copy(tmpl[f"{c}34"]._style) for c in "ABCDEFGH"}
rel_style = {c: copy.copy(tmpl[f"{c}50"]._style) for c in "ABCDEFGH"}

for lg, ph, kind, store, defi, summary, attrs, idxs, fks, pks in ENT:
    ws = wb.copy_worksheet(tmpl)
    ws.title = ph
    ws["C2"] = SYSTEM; ws["F2"] = AUTHOR; ws["H2"] = DATE; ws["F3"] = AUTHOR; ws["H3"] = DATE; ws["H4"] = VERSION
    ws["C6"] = lg; ws["C7"] = ph
    ws["C8"] = f"【保存先：{store}】{summary}"
    ws["C8"].alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)
    ws.row_dimensions[8].height = 34
    for r in range(11, 32):
        for c in "ABCDEFGH":
            ws[f"{c}{r}"].value = None
            ws[f"{c}{r}"]._style = copy.copy(attr_style[c])
    for k, (a, b, t, nn, dflt, note) in enumerate(attrs):
        r = 11 + k
        for c, v in zip("ABCEFGH", (k + 1, a, b, t, nn, dflt, note)):
            ws[f"{c}{r}"] = v if v != "" else None
        ws[f"A{r}"].alignment = Alignment(horizontal="center", vertical="center")
        ws[f"F{r}"].alignment = Alignment(horizontal="center", vertical="center")
        ws[f"H{r}"].alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)
        ws[f"H{r}"].font = Font(name=ws[f"H{r}"].font.name, sz=9)
        if len(note) > 16:
            ws.row_dimensions[r].height = 30
    for r in range(34, 39):
        for c in "ABCDEFGH":
            ws[f"{c}{r}"].value = None
            ws[f"{c}{r}"]._style = copy.copy(idx_style[c])
    for k, (nm, cols, uq, note) in enumerate(idxs):
        r = 34 + k
        for c, v in zip("ABDGH", (k + 1, nm, cols, uq, note)):
            ws[f"{c}{r}"] = v if v != "" else None
        ws[f"A{r}"].alignment = Alignment(horizontal="center", vertical="center")
        ws[f"G{r}"].alignment = Alignment(horizontal="center", vertical="center")
        ws[f"H{r}"].alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)
        ws[f"H{r}"].font = Font(name=ws[f"H{r}"].font.name, sz=9)
        ws.row_dimensions[r].height = 30
    for base_r, rels in ((42, fks), (50, pks)):
        for r in range(base_r, base_r + 5):
            for c in "ABCDEFGH":
                ws[f"{c}{r}"].value = None
                ws[f"{c}{r}"]._style = copy.copy(rel_style[c])
        for k, (verb, cols, ent, rcols) in enumerate(rels):
            r = base_r + k
            for c, v in zip("ABCFH", (k + 1, verb, cols, ent, rcols)):
                ws[f"{c}{r}"] = v
            ws[f"A{r}"].alignment = Alignment(horizontal="center", vertical="center")
    ws["A40"] = "リレーションシップ情報(FK側)　※NoSQL・端末内保存のため外部キー制約はなく、論理的な参照を示す"
    ws.print_area = "A1:H54"
del wb["_tmpl"]

# ------- E-Rモデル・エンティティ一覧 -------
er = wb["E-Rモデル　　エンティティ一覧"]
er["C2"] = SYSTEM; er["F2"] = AUTHOR; er["F3"] = DATE; er["F5"] = AUTHOR; er["F6"] = DATE; er["F4"] = VERSION
er["C5"] = "ER001"
er["C6"] = f"{SYSTEM}（BLEプロフィール交換アプリ）のデータモデルを定義する。データはFirebase Auth・Firestore・各端末内（SwiftData）に分かれる"
er["C6"].alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)
er.merge_cells("C6:D6")
er.row_dimensions[6].height = 30
row_style = {c: copy.copy(er[f"{c}10"]._style) for c in "ABCDEF"}
er["D9"] = "エンティティ種別"
er["E9"] = "定義（保存先）"
for rng in [x for x in er.merged_cells.ranges if 10 <= x.min_row <= 21]:
    er.unmerge_cells(str(rng))
for r in range(10, 22):
    for c in "ABCDEF":
        er[f"{c}{r}"].value = None
        er[f"{c}{r}"]._style = copy.copy(row_style[c]) if r < 10 + len(ENT) else copy.copy(er["H40"]._style)
for rng in [x for x in er.merged_cells.ranges if 10 <= x.min_row <= 21]:
    er.unmerge_cells(str(rng))
for k, e in enumerate(ENT):
    r = 10 + k
    er.merge_cells(f"E{r}:F{r}")
    er[f"A{r}"] = k + 1; er[f"B{r}"] = e[0]; er[f"C{r}"] = e[1]; er[f"D{r}"] = e[2]
    er[f"E{r}"] = f"{e[4]}（{e[3]}）"
    for c in "ABCDEF":
        er[f"{c}{r}"].border = BOX
        er[f"{c}{r}"].alignment = Alignment(horizontal="center" if c == "A" else "left", vertical="center", wrap_text=True)
    er.row_dimensions[r].height = 30
for r in range(15, 22):
    er.row_dimensions[r].height = 15
for r in range(22, 120):
    for c in "ABCDEFGH":
        er[f"{c}{r}"].value = None
        er[f"{c}{r}"]._style = copy.copy(er["H40"]._style)
er["A23"] = "E-Rモデル図"
er["A23"].font = Font(name=er["A9"].font.name, sz=11, b=True)
for r in range(22, 80):
    if r > 15:
        er.row_dimensions[r].height = 15
er.print_area = "A1:F62"

# ------- CRUD図 -------
cr = wb["CRUD図 "]
cr["B2"] = SYSTEM; cr["I2"] = AUTHOR; cr["L2"] = DATE; cr["I3"] = AUTHOR; cr["L3"] = DATE; cr["L4"] = VERSION
cr["B6"] = f"{SYSTEM} CRUD図"
cr["B7"] = f"{SYSTEM}における主要機能とエンティティのCRUD関係を示す"
hdr_fill = copy.copy(cr["A2"].fill)
for rng in [x for x in cr.merged_cells.ranges if x.min_row >= 9]:
    cr.unmerge_cells(str(rng))
blank = copy.copy(cr["Z99"]._style)
for r in range(9, 45):
    for c in "ABCDEFGHIJKLMNOPQ":
        cr[f"{c}{r}"].value = None
        cr[f"{c}{r}"]._style = copy.copy(blank)
ents = ["ユーザー\nアカウント", "管理者", "OTPコード", "自分の\nプロフィール", "交換した\nステッカー"]
FUNCS = [
    ("学内メール認証", "認証コードの送信（学生）", ["R", "", "C、U", "", ""]),
    ("学内メール認証", "認証コードの検証・アカウント作成", ["C、R", "", "R、U、D", "", ""]),
    ("学内メール認証", "アカウント状態の確認（起動時・交換開始時）", ["R", "", "", "", ""]),
    ("プロフィール", "プロフィールの作成", ["", "", "", "C", ""]),
    ("プロフィール", "プロフィールの編集", ["", "", "", "R、U", ""]),
    ("プロフィール交換", "至近距離検知・プロフィール交換（受信したステッカーの保存）", ["", "", "", "R", "C、U"]),
    ("ステッカー", "ステッカーコレクションの表示", ["", "", "", "", "R"]),
    ("ステッカー", "ステッカーの位置の確定・移動（G7・G4）", ["", "", "", "", "U"]),
    ("ステッカー", "ステッカー詳細の表示", ["", "", "", "", "R"]),
    ("ステッカー", "ステッカーをはがす", ["", "", "", "", "D"]),
    ("管理（Web）", "管理者ログイン（認証コードの送信）", ["", "R", "C、U", "", ""]),
    ("管理（Web）", "管理者ログイン（認証コードの検証）", ["C、R", "R", "R、U、D", "", ""]),
    ("管理（Web）", "ユーザー一覧の表示・検索", ["R", "", "", "", ""]),
    ("管理（Web）", "アカウントの無効化・有効化", ["U", "", "", "", ""]),
    ("管理（Web）", "アカウントの削除", ["D", "", "", "", ""]),
]
font = cr["C12"].font.name
def put(cell, v, bold=False, sz=10, align="center", fill=None):
    c = cr[cell]
    if not isinstance(c, openpyxl.cell.cell.MergedCell):
        c.value = v
    c.font = Font(name=font, sz=sz, b=bold)
    c.alignment = Alignment(horizontal=align, vertical="center", wrap_text=True)
    c.border = BOX
    if fill is not None:
        c.fill = copy.copy(fill)
cr.merge_cells("G9:K9")
for c in "GHIJK":
    put(f"{c}9", "エンティティ" if c == "G" else None, True, 10, fill=hdr_fill)
cr.merge_cells("B9:F10")
put("B9", "機能", True, 10, fill=hdr_fill)
for c in "CDEF":
    put(f"{c}9", None, fill=hdr_fill); put(f"{c}10", None, fill=hdr_fill)
put("B10", None, fill=hdr_fill)
for c, e in zip("GHIJK", ents):
    put(f"{c}10", e, True, 9, fill=hdr_fill)
cr.row_dimensions[10].height = 30
r0 = 11
groups = []
for k, (grp, fn, cells) in enumerate(FUNCS):
    r = r0 + k
    cr.merge_cells(f"C{r}:F{r}")
    put(f"B{r}", grp, False, 9)
    put(f"C{r}", fn, False, 9, "left")
    for c in "DEF":
        cr[f"{c}{r}"].border = BOX
    for c, v in zip("GHIJK", cells):
        put(f"{c}{r}", v or None, False, 10)
    cr.row_dimensions[r].height = 30 if len(fn) > 22 else 20
# 機能グループ（B列）を結合
start = r0
for k in range(1, len(FUNCS) + 1):
    if k == len(FUNCS) or FUNCS[k][0] != FUNCS[k - 1][0]:
        if r0 + k - 1 > start:
            cr.merge_cells(f"B{start}:B{r0 + k - 1}")
        start = r0 + k
lastr = r0 + len(FUNCS) - 1
cr[f"B{lastr + 2}"] = "凡例　C：作成（Create）　R：参照（Read）　U：更新（Update）　D：削除（Delete）"
cr[f"B{lastr + 2}"].font = Font(name=font, sz=9)
cr[f"B{lastr + 3}"] = "※ 管理者ログインの検証時、初回はFirebase Authに管理者のアカウントを作成し、管理者権限（customClaims.admin）を付与する"
cr[f"B{lastr + 3}"].font = Font(name=font, sz=9)
cr[f"B{lastr + 4}"] = "※ 交換したステッカーは、交換成立時に作成（再交換時は更新）し、貼り付け位置はその後の操作で更新する"
cr[f"B{lastr + 4}"].font = Font(name=font, sz=9)
cr[f"B{lastr + 5}"] = "※ 管理用のCloud Functionsは、呼び出し元のIDトークンでcustomClaims.adminを必ず確認する（ユーザーアカウントのR）"
cr[f"B{lastr + 5}"].font = Font(name=font, sz=9)
cr.column_dimensions["B"].width = 12
for c in "GHIJK":
    cr.column_dimensions[c].width = 12
cr.print_area = f"A1:M{lastr + 6}"

wb._sheets.sort(key=lambda w: (["E-Rモデル　　エンティティ一覧", "CRUD図 "] + [e[1] for e in ENT]).index(w.title))
wb.active = 0
wb.properties.creator = AUTHOR
wb.properties.lastModifiedBy = AUTHOR
wb.properties.title = f"{SYSTEM} データベース設計書"
wb.save(OUT)

# ------- E-R図（図形） -------
heights = [er.row_dimensions[r].height or er.sheet_format.defaultRowHeight for r in range(1, 120)]
def ytop(row):  # 行の上端(px)
    return sum(h * 96 / 72 for h in heights[:row - 1])
Y0 = ytop(25)
d = Drawing()
LH = 15

def entity(x, y, w, e, name=None):
    lg, ph, attrs = e[0], e[1], e[6]
    pk = {a[1] for a in attrs if a[5].startswith("PK")}
    lines = []
    for a in attrs:
        mark = "#" if a[1] in pk else " "
        mark += "*" if a[3] == "○" else "o"
        lines.append(f"{mark} {a[1]}")
    d.shape(x, y, w, 24, [(f"{lg}（{ph}）", True, 9, "FFFFFF")], fill="0070C0", line="000000", lw=0.75)
    h = 10 + LH * len(lines)
    d.shape(x, y + 24, w, h, lines, size=8.5, align="l", anchor="t", fill="FFFFFF", line="000000", lw=0.75, inset=60000)
    return (x, y, w, 24 + h)

def group(x, y, w, h, title, tx=None):
    d.shape(x, y, w, h, [], geom="roundRect", fill="F7F9FC", line="7F7F7F", lw=1.0, dash="dash")
    tx = x + 10 if tx is None else tx
    d.text(tx, y + 6, x + w - tx - 10, 18, [(title, True, 9, "404040")], align="l", fill=None)

E = {e[1]: e for e in ENT}
# グループ枠
group(20, Y0, 300, 220, "クラウド：Firebase Auth")
group(340, Y0, 640, 220, "クラウド：Firestore")
group(20, Y0 + 270, 960, 300, "端末内：SwiftData（学生の各iPhone）", tx=750)
bu = entity(40, Y0 + 34, 260, E["users"])
bo = entity(380, Y0 + 34, 250, E["otpCodes"])
ba = entity(700, Y0 + 34, 250, E["admins"])
bm = entity(40, Y0 + 306, 260, E["MyProfile"])
bs = entity(470, Y0 + 306, 260, E["Sticker"])

def mid_y(b): return b[1] + b[3] / 2
# otpCodes は認証前のアドレスを保持するため、users・admins と参照関係を持たない
yl = bu[1] + 24 + 10 + LH * 1.5
d.text(bo[0], bo[1] + bo[3] + 6, bo[2], 30, ["※ 他のエンティティとの参照関係なし", "（認証前のアドレスを保持するため）"], size=8, fill=None)
# users — MyProfile（uid）
x1 = bu[0] + bu[2] * 0.3
d.poly([(x1, bu[1] + bu[3]), (x1, bm[1])], tail=False, dash="dash")
d.text(x1 + 6, bu[1] + bu[3] + 14, 110, 28, ["uid", "（ログイン中の本人）"], size=8, align="l", fill=None)
d.text(x1 + 6, bu[1] + bu[3] + 2, 18, 12, ["1"], size=8, align="l", fill=None)
d.text(x1 + 6, bm[1] - 14, 30, 12, ["0..1"], size=8, align="l", fill=None)
# users — Sticker（partnerUid）
x2 = bu[0] + bu[2] * 0.7
ym = Y0 + 245
xs = bs[0] + bs[2] / 2
d.poly([(x2, bu[1] + bu[3]), (x2, ym), (xs, ym), (xs, bs[1])], tail=False, dash="dash")
d.text(x2 + 30, ym - 16, 220, 14, ["partnerUid（交換相手のuid）"], size=8, fill=None)
d.text(x2 + 6, bu[1] + bu[3] + 2, 18, 12, ["1"], size=8, align="l", fill=None)
d.text(xs + 6, bs[1] - 14, 18, 12, ["N"], size=8, align="l", fill=None)
# 凡例
d.text(20, Y0 + 585, 960, 60, [
    "凡例　#：主キー　*：必須　o：任意　　点線：論理的な関連（NoSQL・端末内保存のため外部キー制約はない）　型の(n)は最大文字数",
    "※ OTPコードは認証前のアドレスを保持するため参照関係なし（purposeがadminの場合は送信前にadminsと照合する）",
    "※ 自分のプロフィールと交換したステッカーは各端末内にのみ保存し、クラウドには送らない（交換はBLEで端末同士が直接行う）"],
    size=8.5, align="l", fill=None, anchor="t")
inject(OUT, "E-Rモデル　　エンティティ一覧", d)
print("ok", OUT)
