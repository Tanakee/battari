import os, sys, copy
import openpyxl
from openpyxl.styles import Border, Side, Alignment
sys.path.insert(0, os.path.dirname(__file__))
from spec import *
from xldraw import Drawing, inject

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "templates", "01_画面設計書(画面一覧・画面遷移図).xlsx")
OUT = sys.argv[1]

wb = openpyxl.load_workbook(SRC)
ws = wb["画面一覧"]
hdr = {c: copy.copy(ws[f"{c}3"]._style) for c in "ABCDE"}
st_id, st_name, st_desc = (copy.copy(ws[c]._style) for c in ("A4", "B4", "D4"))
thin = Side(style="thin")
box = Border(left=thin, right=thin, top=thin, bottom=thin)

# 既存の内容を消去（A〜H列・4行目以降）
for row in ws.iter_rows(min_row=1, max_row=ws.max_row, max_col=8):
    for c in row:
        if c.row >= 4 or c.column >= 6:
            c.value = None
            c._style = copy.copy(ws["A40"]._style)
ws["A1"] = f"{SYSTEM}　画面設計書（画面一覧）"
for c in "GH":
    ws.column_dimensions[c].width = 9
ws.column_dimensions["E"].width = 40
ws.column_dimensions["C"].width = 30
for k in range(4, 60):
    ws.row_dimensions[k].height = None

for i, (sid, name, func, desc, note) in enumerate(SCREENS):
    r = 4 + i
    vals = [sid, name, func, desc, note]
    styles = [st_id, st_name, st_name, st_desc, st_desc]
    for j, (v, s) in enumerate(zip(vals, styles)):
        c = ws.cell(r, j + 1, v)
        c._style = copy.copy(s)
        c.border = box
        c.alignment = Alignment(vertical="center", wrap_text=(j >= 3), horizontal="center" if j == 0 else None)
    ws.row_dimensions[r].height = 30
last = 4 + len(SCREENS) - 1
for k, t in enumerate(NOTES):
    ws[f"A{last + 2 + k}"] = t
last += len(NOTES) - 1
ws.print_area = f"A1:E{last + 2}"
ws.page_setup.orientation = "landscape"
ws.page_setup.fitToWidth = 1
ws.page_setup.fitToHeight = 0
ws.sheet_properties.pageSetUpPr.fitToPage = True

# 画面遷移図シート
ws2 = wb["画面遷移図"]
ws2.sheet_view.showGridLines = False
from openpyxl.utils import get_column_letter
blank = copy.copy(ws2["BZ200"]._style)
for row in ws2.iter_rows():
    for c in row:
        c.value = None
        c._style = copy.copy(blank)
ws2.column_dimensions.clear()
for k in range(1, 61):
    ws2.column_dimensions[get_column_letter(k)].width = 4.33
for k in range(1, 61):
    ws2.row_dimensions[k].height = 13.5
ws2.print_area = "A1:AK52"
ws2.page_setup.orientation = "landscape"
ws2.sheet_properties.pageSetUpPr.fitToPage = True
ws2.page_setup.fitToWidth = 1
ws2.page_setup.fitToHeight = 1
wb.properties.creator = AUTHOR
wb.properties.lastModifiedBy = AUTHOR
wb.properties.title = f"{SYSTEM} 画面設計書（画面一覧・画面遷移図）"
wb.save(OUT)

# ---- 画面遷移図（図形） ----
d = Drawing()
W, H = 150, 54
names = {s[0]: s[1] for s in SCREENS}
pos = {"G1": (220, 160), "G2": (450, 160), "G3": (680, 160), "G4": (680, 320),
       "G5": (910, 320), "G6": (1140, 320), "G7": (1140, 480), "G8": (450, 480),
       "W1": (220, 700), "W2": (450, 700), "W3": (680, 700)}

def scr(sid):
    x, y = pos[sid]
    name = names[sid]
    d.shape(x, y, W, H, [(f"【{sid}】", True, 9), (name, False, 9)], geom="roundRect",
            fill="FFFFFF" if sid[0] == "G" else "F3F3F3", lw=1.0, name=f"{sid}_box")

def L(x, y, w, h, *lines):
    d.text(x, y, w, h, list(lines), size=8)

# レーン
d.text(30, 106, 200, 22, [("【iOSアプリ】", True, 10)], align="l", fill=None)
d.poly([(20, 600), (1320, 600)], tail=False, color="808080", lw=1.0, dash="dash")
d.text(30, 626, 220, 22, [("【管理画面（Webブラウザ）】", True, 10)], align="l", fill=None)

# 起点
d.shape(30, 320, 130, H, [("アプリ起動", True, 9)], geom="ellipse", fill="E8E8E8", lw=1.0)
d.shape(30, 700, 130, H, [("管理画面を開く", True, 9)], geom="ellipse", fill="E8E8E8", lw=1.0)
for s in pos:
    scr(s)

cy = lambda s: pos[s][1] + H / 2          # 縦中央
cx = lambda s: pos[s][0] + W / 2          # 横中央
R = lambda s: pos[s][0] + W               # 右端
B = lambda s: pos[s][1] + H               # 下端

# 起動 → G1（未登録）／ G4（登録済み）
d.poly([(95, 320), (95, cy("G1")), (pos["G1"][0], cy("G1"))])
L(100, 194, 112, 30, "未登録・", "アカウント無効")
d.poly([(160, cy("G4")), (pos["G4"][0], cy("G4"))])
L(380, 326, 90, 16, "登録済み")
# G1 ⇄ G2 → G3 ⇄ G4
d.poly([(R("G1"), cy("G1")), (pos["G2"][0], cy("G1"))], head=True)
L(R("G1") + 4, 150, 72, 30, "コード送信／", "戻る")
d.poly([(R("G2"), cy("G2")), (pos["G3"][0], cy("G2"))])
L(R("G2") + 4, 150, 72, 30, "認証成功", "（初回）")
x34 = pos["G3"][0] + W * 0.7
d.poly([(x34, B("G3")), (x34, pos["G4"][1])], head=True)
L(x34 + 8, 236, 110, 30, "保存／", "プロフィール編集")
# G2 → G4（認証成功・プロフィール保存済み）
x24 = pos["G4"][0] + W * 0.3
d.poly([(cx("G2"), B("G2")), (cx("G2"), 272), (x24, 272), (x24, pos["G4"][1])])
L(cx("G2") + 10, 254, 150, 16, "認証成功（保存済み）")
# G4 ⇄ G5 ⇄ G6 → G7 → G4
d.poly([(R("G4"), cy("G4")), (pos["G5"][0], cy("G4"))], head=True)
L(R("G4") + 4, 304, 72, 30, "交換する／", "閉じる")
d.poly([(R("G5"), cy("G5")), (pos["G6"][0], cy("G5"))], head=True)
L(R("G5") + 2, 290, 76, 44, "相手を検知／", "やめる・拒否・", "時間切れ")
d.poly([(cx("G6"), B("G6")), (cx("G7"), pos["G7"][1])])
L(cx("G6") + 8, 412, 110, 30, "双方が", "「交換する」")
x7 = pos["G4"][0] + W * 0.7
y7a = pos["G7"][1] + H * 0.3
y7b = pos["G7"][1] + H * 0.7
d.poly([(pos["G7"][0], y7b), (x7, y7b), (x7, B("G4"))])
L(880, y7b + 4, 120, 16, "ここに貼る")
# G7 → G5（貼って続けて交換）
d.poly([(pos["G7"][0], y7a), (cx("G5"), y7a), (cx("G5"), B("G5"))])
L(cx("G5") + 10, y7a - 20, 130, 16, "貼って続けて交換")
# G5 → G1（交換開始時にアカウント無効）
d.poly([(cx("G5"), pos["G5"][1]), (cx("G5"), 130), (cx("G1"), 130), (cx("G1"), pos["G1"][1])])
L(560, 112, 220, 16, "アカウント無効（交換開始時に確認）")
# G4 ⇄ G8
x8 = pos["G4"][0] + W * 0.3
d.poly([(x8, B("G4")), (x8, cy("G8")), (R("G8"), cy("G8"))], head=True)
L(R("G8") + 6, 514, 100, 30, "タップ／", "閉じる・はがす")
# 管理画面
d.poly([(160, cy("W1")), (pos["W1"][0], cy("W1"))])
d.poly([(R("W1"), cy("W1")), (pos["W2"][0], cy("W1"))], head=True)
L(R("W1") + 4, 690, 72, 30, "コード送信／", "戻る")
d.poly([(R("W2"), cy("W2")), (pos["W3"][0], cy("W2"))])
L(R("W2") + 4, 698, 72, 16, "認証成功")
d.poly([(cx("W3"), B("W3")), (cx("W3"), 800), (cx("W1"), 800), (cx("W1"), B("W1"))])
L(430, 804, 140, 16, "ログアウト／権限なし")

# 注記
d.text(30, 850, 900, 50, [
    "※ 往復できる遷移は両方向の矢印で示す。",
    "※ G4でステッカーを長押しした位置移動は、画面内の操作のため遷移に含めない。"], size=9, align="l", fill=None)
d.text(30, 60, 500, 30, [(f"{SYSTEM}　画面遷移図", True, 14)], align="l", fill=None)

inject(OUT, "画面遷移図", d)
print("ok", OUT)
