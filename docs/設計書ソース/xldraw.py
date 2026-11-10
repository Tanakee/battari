# Excel(DrawingML)の図形を絶対座標(px)で生成し、openpyxlが保存したxlsxへ注入する
import re, zipfile, shutil, os
from xml.sax.saxutils import escape

EMU = 9525  # 1px
NS = ('xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
FONT = "ＭＳ Ｐゴシック"


class Drawing:
    def __init__(self):
        self.parts = []
        self.nid = 2

    def _id(self):
        self.nid += 1
        return self.nid

    @staticmethod
    def _runs(lines, size, bold, color):
        ps = []
        for ln in lines:
            if isinstance(ln, tuple):
                txt, b, sz, col = (list(ln) + [None, None, None])[:4]
            else:
                txt, b, sz, col = ln, None, None, None
            b = bold if b is None else b
            sz = size if sz is None else sz
            col = color if col is None else col
            ps.append((txt, b, sz, col))
        return ps

    def _txbody(self, lines, size, bold, color, align, anchor, inset):
        out = [f'<xdr:txBody><a:bodyPr vertOverflow="overflow" horzOverflow="overflow" wrap="square" lIns="{inset}" tIns="{inset}" rIns="{inset}" bIns="{inset}" rtlCol="0" anchor="{anchor}"/><a:lstStyle/>']
        for txt, b, sz, col in self._runs(lines, size, bold, color):
            out.append(f'<a:p><a:pPr algn="{align}"/>')
            if txt:
                out.append(f'<a:r><a:rPr lang="ja-JP" altLang="en-US" sz="{int(sz*100)}" b="{1 if b else 0}">'
                           f'<a:solidFill><a:srgbClr val="{col}"/></a:solidFill>'
                           f'<a:latin typeface="{FONT}"/><a:ea typeface="{FONT}"/></a:rPr><a:t>{escape(txt)}</a:t></a:r>')
            out.append(f'<a:endParaRPr lang="ja-JP" sz="{int(sz*100)}"/></a:p>')
        if not lines:  # Excelは段落が1つもないtxBodyを不正とみなす
            out.append(f'<a:p><a:endParaRPr lang="ja-JP" sz="{int(size*100)}"/></a:p>')
        out.append('</xdr:txBody>')
        return "".join(out)

    def shape(self, x, y, w, h, lines=(), geom="rect", fill="FFFFFF", line="000000", lw=1.0,
              size=9, bold=False, color="000000", align="ctr", anchor="ctr", dash=None, inset=45720, name=None):
        i = self._id()
        fill_xml = f'<a:solidFill><a:srgbClr val="{fill}"/></a:solidFill>' if fill else '<a:noFill/>'
        if line:
            d = f'<a:prstDash val="{dash}"/>' if dash else ''
            ln = f'<a:ln w="{int(lw*12700)}"><a:solidFill><a:srgbClr val="{line}"/></a:solidFill>{d}</a:ln>'
        else:
            ln = '<a:ln><a:noFill/></a:ln>'
        av = '<a:avLst><a:gd name="adj" fmla="val 12000"/></a:avLst>' if geom == "roundRect" else '<a:avLst/>'
        self.parts.append(
            f'<xdr:absoluteAnchor><xdr:pos x="{int(x*EMU)}" y="{int(y*EMU)}"/><xdr:ext cx="{int(w*EMU)}" cy="{int(h*EMU)}"/>'
            f'<xdr:sp macro="" textlink=""><xdr:nvSpPr><xdr:cNvPr id="{i}" name="{escape(name or f"shape{i}")}"/><xdr:cNvSpPr/></xdr:nvSpPr>'
            f'<xdr:spPr><a:xfrm><a:off x="{int(x*EMU)}" y="{int(y*EMU)}"/><a:ext cx="{int(w*EMU)}" cy="{int(h*EMU)}"/></a:xfrm>'
            f'<a:prstGeom prst="{geom}">{av}</a:prstGeom>{fill_xml}{ln}</xdr:spPr>'
            f'{self._txbody(lines, size, bold, color, align, anchor, inset)}</xdr:sp><xdr:clientData/></xdr:absoluteAnchor>')
        return i

    def text(self, x, y, w, h, lines, size=8, bold=False, color="000000", align="ctr", fill="FFFFFF", anchor="ctr"):
        return self.shape(x, y, w, h, lines, fill=fill, line=None, size=size, bold=bold, color=color,
                          align=align, anchor=anchor, inset=0)

    def poly(self, pts, head=False, tail=True, color="000000", lw=1.25, dash=None, name=None):
        """pts: [(x,y),...] px。直線の線分(プリセット line)を繋いで描く。tail=終点に矢印、head=始点に矢印"""
        n = len(pts) - 1
        for k in range(n):
            (x1, y1), (x2, y2) = pts[k], pts[k + 1]
            i = self._id()
            x0, y0 = min(x1, x2), min(y1, y2)
            w, h = abs(x2 - x1), abs(y2 - y1)
            flip = (' flipH="1"' if x2 < x1 else '') + (' flipV="1"' if y2 < y1 else '')
            d = f'<a:prstDash val="{dash}"/>' if dash else ''
            he = '<a:headEnd type="triangle" w="med" len="med"/>' if (head and k == 0) else ''
            te = '<a:tailEnd type="triangle" w="med" len="med"/>' if (tail and k == n - 1) else ''
            self.parts.append(
                f'<xdr:absoluteAnchor><xdr:pos x="{int(x0*EMU)}" y="{int(y0*EMU)}"/><xdr:ext cx="{int(w*EMU)}" cy="{int(h*EMU)}"/>'
                f'<xdr:cxnSp macro=""><xdr:nvCxnSpPr><xdr:cNvPr id="{i}" name="{escape(name or f"line{i}")}"/><xdr:cNvCxnSpPr/></xdr:nvCxnSpPr>'
                f'<xdr:spPr><a:xfrm{flip}><a:off x="{int(x0*EMU)}" y="{int(y0*EMU)}"/><a:ext cx="{int(w*EMU)}" cy="{int(h*EMU)}"/></a:xfrm>'
                f'<a:prstGeom prst="line"><a:avLst/></a:prstGeom><a:noFill/>'
                f'<a:ln w="{int(lw*12700)}" cap="sq"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill>{d}<a:round/>{he}{te}</a:ln></xdr:spPr>'
                f'</xdr:cxnSp><xdr:clientData/></xdr:absoluteAnchor>')

    def xml(self):
        return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<xdr:wsDr {NS}>' + "".join(self.parts) + '</xdr:wsDr>'


def inject(xlsx_path, sheet_title, drawing):
    """openpyxlで保存済みのxlsxの指定シートへ図形を追加する(既存drawingがあれば追記)"""
    tmp = xlsx_path + ".tmp"
    zin = zipfile.ZipFile(xlsx_path)
    files = {n: zin.read(n) for n in zin.namelist()}
    infos = {i.filename: i for i in zin.infolist()}
    zin.close()
    wbx = files["xl/workbook.xml"].decode()
    rels = files["xl/_rels/workbook.xml.rels"].decode()
    rid = re.search(r'<sheet [^>]*name="%s"[^>]*r:id="(rId\d+)"' % re.escape(escape(sheet_title, {'"': '&quot;'})), wbx).group(1)
    target = re.search(r'Id="%s"[^>]*Target="([^"]+)"' % rid, rels) or re.search(r'Target="([^"]+)"[^>]*Id="%s"' % rid, rels)
    sheet_path = "xl/" + target.group(1).lstrip("/").replace("xl/", "")
    sheet_rels = sheet_path.replace("worksheets/", "worksheets/_rels/") + ".rels"
    sx = files[sheet_path].decode()
    srels = files.get(sheet_rels, b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>').decode()
    m = re.search(r'<drawing r:id="(rId\d+)"', sx)
    body = drawing.xml()
    if m:  # 既存drawingに追記
        dt = re.search(r'Id="%s"[^>]*Target="([^"]+)"' % m.group(1), srels) or re.search(r'Target="([^"]+)"[^>]*Id="%s"' % m.group(1), srels)
        dpath = os.path.normpath(os.path.join(os.path.dirname(sheet_path), dt.group(1))).replace("\\", "/")
        dx = files[dpath].decode()
        inner = body[body.index(">", body.index("<xdr:wsDr")) + 1: body.rindex("</xdr:wsDr>")]
        # id重複を避けるため既存の最大idより大きく振り直し
        mx = max([int(v) for v in re.findall(r'<xdr:cNvPr id="(\d+)"', dx)] + [1])
        inner = re.sub(r'<xdr:cNvPr id="(\d+)"', lambda k: f'<xdr:cNvPr id="{int(k.group(1)) + mx}"', inner)
        files[dpath] = dx.replace("</xdr:wsDr>", inner + "</xdr:wsDr>").encode()
    else:
        n = 1
        while f"xl/drawings/drawing{n}.xml" in files:
            n += 1
        dpath = f"xl/drawings/drawing{n}.xml"
        files[dpath] = body.encode()
        ids = [int(v) for v in re.findall(r'Id="rId(\d+)"', srels)] + [0]
        nr = f"rId{max(ids) + 1}"
        srels = srels.replace("</Relationships>",
                              f'<Relationship Id="{nr}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing{n}.xml"/></Relationships>')
        files[sheet_rels] = srels.encode()
        tag = f'<drawing r:id="{nr}"/>'
        if "<legacyDrawing" in sx:
            sx = sx.replace("<legacyDrawing", tag + "<legacyDrawing", 1)
        else:
            for t in ("<tableParts", "<extLst", "</worksheet>"):
                if t in sx:
                    sx = sx.replace(t, tag + t, 1)
                    break
        if 'xmlns:r=' not in sx[:500]:
            sx = sx.replace("<worksheet ", '<worksheet xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ', 1)
        files[sheet_path] = sx.encode()
        ct = files["[Content_Types].xml"].decode()
        ct = ct.replace("</Types>", f'<Override PartName="/{dpath}" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/></Types>')
        files["[Content_Types].xml"] = ct.encode()
    zout = zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED)
    for name, data in files.items():
        zout.writestr(name, data)
    zout.close()
    shutil.move(tmp, xlsx_path)
