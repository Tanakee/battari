import os, sys, copy, math, unicodedata
import openpyxl
from openpyxl.drawing.image import Image as XLImage
from openpyxl.drawing.spreadsheet_drawing import OneCellAnchor, AnchorMarker
from openpyxl.drawing.xdr import XDRPositiveSize2D
from openpyxl.styles import Alignment, Font
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from spec import *

SRC = os.path.expanduser("~/Downloads/02_画面設計書(画面レイアウト).xlsx")
MOCK = os.path.join(os.path.dirname(__file__), "mock")
OUT = sys.argv[1]
EMU = 9525

wb = openpyxl.load_workbook(SRC)
base = wb["G1"]
base.title = "_base"
for n in list(wb.sheetnames):
    if n not in ("_base", "(Gxx)フォーマット"):
        del wb[n]
# 部品行（32行目）の各セルのスタイルを控える
part_style = {c: copy.copy(base[f"{c}32"]._style) for c in "ABCDEFGHIJKLMNOPQRST"}

def fill_common(ws):
    ws["D2"] = SYSTEM
    ws["S2"] = AUTHOR
    ws["S3"] = DATE
    ws["S4"] = VERSION
    ws["S5"] = AUTHOR
    ws["S6"] = DATE

fmt = wb["(Gxx)フォーマット"]
fill_common(fmt)

def width_units(s):
    return sum(2 if unicodedata.east_asian_width(ch) in "WFA" else 1 for ch in str(s))

# 画像を縮小して保存（ファイルサイズ対策）
os.makedirs(os.path.join(MOCK, "small"), exist_ok=True)

for sid, name, func, desc, note in SCREENS:
    ws = wb.copy_worksheet(base)
    ws.title = f"({sid}){name}"
    steps, parts = LAYOUT[sid]
    fill_common(ws)
    ws.column_dimensions["K"].width = 18
    ws["D6"] = sid
    ws["H6"] = name
    ws["G7"] = None
    ws.merge_cells("D7:P7")
    ws["D7"] = desc
    ws["D7"].alignment = Alignment(horizontal="left", vertical="center")
    ws["B10"] = None
    ws["N9"] = steps
    ws["N9"].alignment = Alignment(vertical="top", wrap_text=True)

    # 部品行（P01〜）。7行を超える場合は行を追加
    for rng in [r for r in ws.merged_cells.ranges if r.min_row >= 32]:
        ws.unmerge_cells(str(rng))
    nrows = max(7, len(parts))
    for k in range(nrows):
        r = 32 + k
        for c in "ABCDEFGHIJKLMNOPQRST":
            ws[f"{c}{r}"].value = None
            ws[f"{c}{r}"]._style = copy.copy(part_style[c])
        ws.merge_cells(f"B{r}:C{r}")
        ws.merge_cells(f"E{r}:F{r}")
        ws.merge_cells(f"L{r}:M{r}")
        ws.merge_cells(f"N{r}:O{r}")
        ws.merge_cells(f"P{r}:T{r}")
        ws.row_dimensions[r].height = 18
        if k >= len(parts):
            continue
        label, io, kind, dlen, ilen, dtype, chars, init, src, dst, expl = parts[k]
        vals = {"A": f"P{k+1:02d}", "B": label, "D": io, "E": kind, "G": dlen, "H": ilen, "I": dtype,
                "J": chars, "K": init, "L": src, "N": dst, "P": expl}
        # 列幅(全角換算の文字数)と折り返し
        cap = {"B": 22, "E": 18, "G": 8, "H": 8, "J": 9, "K": 20, "L": 17, "N": 17, "P": 44}
        lines = 1
        for c, v in vals.items():
            cell = ws[f"{c}{r}"]
            cell.value = v if v != "" else None
            al = copy.copy(cell.alignment)
            cell.alignment = Alignment(horizontal=al.horizontal, vertical="center", wrap_text=True)
            if c in "GHJKLN":
                cell.font = Font(name=cell.font.name, sz=9)
            if c in cap and v:
                lines = max(lines, math.ceil(width_units(v) / cap[c]))
        ws.row_dimensions[r].height = 18 if lines == 1 else 13 * lines + 4
    last = 32 + nrows - 1
    ws[f"A{last + 1}"] = LAYOUT_NOTE
    ws[f"A{last + 1}"].font = Font(name=ws["A32"].font.name, sz=9)
    ws[f"A{last + 1}"].alignment = Alignment(wrap_text=True, vertical="top")
    ws.merge_cells(f"A{last + 1}:T{last + 1}")
    ws.row_dimensions[last + 1].height = 28
    ws.print_area = f"A1:T{last + 1}"

    # レイアウト図（B10:K28 の領域に収める）
    src_png = os.path.join(MOCK, f"{sid}.png")
    im = Image.open(src_png)
    phone = im.width < im.height
    # A〜M列 × 10〜28行（ＭＳ Ｐゴシック11ptの最大数字幅8px換算）
    area_w = sum(int(ws.column_dimensions[c].width * 8 + 5) for c in "ABCDEFGHIJKLM")
    area_h = 456
    h = 440
    w = round(h * im.width / im.height)
    small = os.path.join(MOCK, "small", f"{sid}.png")
    im.resize((w * 2, h * 2), Image.LANCZOS).save(small, optimize=True)
    xi = XLImage(small)
    xi.width, xi.height = w, h
    ox = (area_w - w) // 2
    oy = (area_h - h) // 2
    col, rest = 0, ox
    for c in "ABCDEFGHIJKLM":
        cw = int(ws.column_dimensions[c].width * 8 + 5)
        if rest < cw:
            break
        rest -= cw
        col += 1
    marker = AnchorMarker(col=col, colOff=rest * EMU, row=9, rowOff=oy * EMU)
    xi.anchor = OneCellAnchor(_from=marker, ext=XDRPositiveSize2D(w * EMU, h * EMU))
    ws.add_image(xi)

# 同級生の画面シートを削除（フォーマットシートは残す）
for n in list(wb.sheetnames):
    if n != "(Gxx)フォーマット" and n not in [f"({s[0]}){s[1]}" for s in SCREENS]:
        del wb[n]
# 印刷範囲の定義名が削除済みシートを指さないよう整理
for n in list(wb.defined_names.keys()) if hasattr(wb.defined_names, "keys") else []:
    pass
order = ["(Gxx)フォーマット"] + [f"({s[0]}){s[1]}" for s in SCREENS]
wb._sheets.sort(key=lambda w: order.index(w.title))
wb.active = 1
wb.properties.creator = AUTHOR
wb.properties.lastModifiedBy = AUTHOR
wb.properties.title = f"{SYSTEM} 画面設計書（画面レイアウト）"
wb.save(OUT)
print("ok", OUT)
