# BATTARI 画面モックアップ生成（HTML → headless Chromeで PNG化）
import os, subprocess

OUT = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CSS = r"""
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:"Hiragino Sans","Hiragino Kaku Gothic ProN",sans-serif;color:#1F2330;background:#fff;-webkit-font-smoothing:antialiased}
.phone{position:relative;width:390px;height:844px;overflow:hidden;background:#F6F5FB}
.status{height:47px;display:flex;justify-content:space-between;align-items:flex-end;padding:0 30px 8px 34px;font-size:15px;font-weight:600}
.status .r{letter-spacing:2px;font-size:12px}
.home-ind{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);width:134px;height:5px;border-radius:3px;background:#1F2330}
.pad{padding:0 24px}
h1{font-size:26px;font-weight:800}
.sub{font-size:14px;color:#6B6F80;line-height:1.6}
.label{font-size:13px;font-weight:700;color:#4A4E5E;margin-bottom:8px}
.field{height:52px;border-radius:14px;background:#fff;border:1.5px solid #DCDCE8;display:flex;align-items:center;padding:0 16px;font-size:16px}
.field.focus{border-color:#5B5BD6;box-shadow:0 0 0 4px rgba(91,91,214,.12)}
.ph{color:#A9ACBC}
.btn{height:54px;border-radius:27px;background:#5B5BD6;color:#fff;font-weight:800;font-size:17px;display:flex;align-items:center;justify-content:center;box-shadow:0 6px 16px rgba(91,91,214,.35)}
.btn.ghost{background:#fff;color:#5B5BD6;border:1.5px solid #CFCFF3;box-shadow:none}
.btn.gray{background:#ECECF3;color:#4A4E5E;box-shadow:none}
.btn.danger{background:#fff;color:#E5484D;border:1.5px solid #F5C2C4;box-shadow:none}
.link{color:#5B5BD6;font-weight:700;font-size:14px}
.err{color:#E5484D;font-size:13px;font-weight:600}
.nav{height:44px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font-size:17px;font-weight:700}
.nav .side{width:96px;white-space:nowrap;color:#5B5BD6;font-weight:600;font-size:16px}
.nav .side.r{text-align:right}
.logo{font-weight:900;letter-spacing:1px;font-size:34px;color:#1F2330}
.logo span{color:#5B5BD6}
/* sticker */
.st{position:absolute;border-radius:50%;border:5px solid #fff;box-shadow:0 3px 8px rgba(0,0,0,.28);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800}
.st.sq{border-radius:28%}
.st .t{text-shadow:0 1px 2px rgba(0,0,0,.25)}
/* laptop */
.lid{position:relative;border-radius:22px;background:linear-gradient(145deg,#D9DCE3 0%,#C3C7D0 45%,#B7BBC5 100%);box-shadow:inset 0 0 0 2px rgba(255,255,255,.55),0 14px 30px rgba(30,30,60,.25)}
.lid .mark{position:absolute;left:50%;top:50%;width:38px;height:38px;transform:translate(-50%,-50%);border-radius:50%;background:rgba(255,255,255,.35)}
.hinge{height:12px;border-radius:0 0 12px 12px;background:linear-gradient(#9EA3AE,#C9CCD4);margin:0 26px}
/* badge */
.hl{position:absolute;z-index:98;border:2px dashed #E0002A;border-radius:6px;pointer-events:none}
.b{position:absolute;z-index:99;width:24px;height:24px;border-radius:50%;background:#E0002A;color:#fff;font:800 13px/24px "Helvetica Neue",Arial,sans-serif;text-align:center;box-shadow:0 0 0 2px #fff,0 2px 4px rgba(0,0,0,.3)}
/* web */
.web{position:relative;width:1280px;height:800px;overflow:hidden;background:#F4F5F9}
.bar{height:36px;background:#E4E6EC;display:flex;align-items:center;padding:0 14px;gap:8px}
.bar i{width:12px;height:12px;border-radius:50%;display:inline-block}
.bar .url{margin-left:18px;flex:1;height:22px;border-radius:11px;background:#fff;font-size:12px;color:#6B6F80;display:flex;align-items:center;padding-left:14px}
.card{background:#fff;border-radius:16px;box-shadow:0 8px 30px rgba(30,30,60,.08);border:1px solid #E6E7EE}
table{border-collapse:collapse;width:100%;font-size:14px}
th{background:#F4F5F9;color:#6B6F80;font-size:12px;text-align:left;padding:11px 14px;font-weight:700;border-bottom:1px solid #E6E7EE}
td{padding:12px 14px;border-bottom:1px solid #EEEFF4}
.pill{display:inline-block;padding:3px 10px;border-radius:10px;font-size:12px;font-weight:700}
.pill.on{background:#E3F6EA;color:#1B8A4B}.pill.off{background:#FDE8E9;color:#C9363B}
.sbtn{display:inline-block;padding:6px 12px;border-radius:8px;font-size:12px;font-weight:700;border:1px solid #D7D8E2;background:#fff;color:#4A4E5E;margin-right:6px}
.sbtn.red{color:#E5484D;border-color:#F5C2C4}
.mono{font-family:Menlo,monospace;font-size:12px;color:#4A4E5E}
"""

BADGE_JS = r"""
<script>
const root=document.querySelector('.phone,.web'), rr=root.getBoundingClientRect();
document.querySelectorAll('[data-p]').forEach(el=>{
  const r=el.getBoundingClientRect(), P=4;
  const L=r.left-rr.left-P, T=r.top-rr.top-P, W=r.width+P*2, H=r.height+P*2;
  const box=document.createElement('i'); box.className='hl';
  Object.assign(box.style,{left:L+'px',top:T+'px',width:W+'px',height:H+'px'});
  root.appendChild(box);
  const a=el.dataset.a||'tl'; let x=L-12, y=T-12;
  if(a==='r'){x=L+W+4; y=T+(H-24)/2;}
  if(a==='l'){x=L-28; y=T+(H-24)/2;}
  if(a==='tr'){x=L+W-12; y=T-12;}
  x=Math.max(0,Math.min(x,rr.width-24)); y=Math.max(0,y);
  const b=document.createElement('i'); b.className='b'; b.textContent=el.dataset.p;
  b.style.left=x+'px'; b.style.top=y+'px';
  root.appendChild(b);
});
</script>"""

def page(body, w, h):
    return f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}</style></head><body style='width:{w}px;height:{h}px'>{body}{BADGE_JS}</body></html>"

STATUS = "<div class='status'><span>13:30</span><span class='r'>▮▮▮ ◠ ▭</span></div>"

def st(ch, c1, c2, x, y, s, rot=0, sq=False, extra="", attrs=""):
    fs = int(s * 0.42)
    return (f"<div class='st{' sq' if sq else ''}' {attrs} style='left:{x}px;top:{y}px;width:{s}px;height:{s}px;"
            f"background:linear-gradient(140deg,{c1},{c2});transform:rotate({rot}deg);font-size:{fs}px;{extra}'><span class='t'>{ch}</span></div>")

PALETTE = [("佐", "#FF8A5B", "#FF4F81"), ("鈴", "#4FC3F7", "#5B5BD6"), ("高", "#7BD88F", "#1FA37A"),
           ("伊", "#FFD166", "#F59E0B"), ("渡", "#C084FC", "#7C3AED"), ("山", "#F472B6", "#DB2777"),
           ("中", "#34D399", "#0EA5E9"), ("小", "#FB7185", "#F97316"), ("加", "#60A5FA", "#2563EB"),
           ("吉", "#A3E635", "#16A34A"), ("松", "#FDBA74", "#EA580C"), ("井", "#93C5FD", "#6366F1")]

def laptop(w, h, stickers_html, attrs=""):
    return (f"<div {attrs} style='position:relative;width:{w}px'><div class='lid' style='width:{w}px;height:{h}px'><div class='mark'></div>{stickers_html}</div>"
            f"<div class='hinge'></div></div>")

def collection(n, scale=1.0, p=None):
    pos = [(22,24,74,-8,False),(118,36,62,6,True),(206,20,80,10,False),(30,128,66,4,True),(124,150,58,-14,False),
           (214,122,70,-6,False),(64,214,60,12,False),(166,226,72,-4,True),(250,208,56,8,False),(14,300,58,-10,False),
           (240,292,64,0,True),(130,312,52,16,False)]
    out = ""
    for i in range(n):
        x, y, s, r, sq = pos[i]
        ch, c1, c2 = PALETTE[i]
        attrs = f"data-p='{p}' data-o='-6,-6'" if (p and i == 2) else ""
        out += st(ch, c1, c2, int(x*scale), int(y*scale), int(s*scale), r, sq, attrs=attrs)
    return out

SCREENS = {}

# ---------- G1 メールアドレス入力 ----------
SCREENS["G1"] = ("phone", f"""
<div class='phone'>{STATUS}
 <div class='pad' style='padding-top:70px;text-align:center'>
  <div data-p='1' data-o='-30,-6' style='display:inline-block;position:relative'>
   <div style='position:relative;width:120px;height:92px;margin:0 auto 18px'>
    {st('B','#FF8A5B','#FF4F81',8,6,70,-10)}{st('T','#4FC3F7','#5B5BD6',50,18,66,10,True)}
   </div>
   <div class='logo'>BATT<span>ARI</span></div>
  </div>
  <div class='sub' style='margin-top:6px'>スマホを近づけて、ステッカーを交換しよう</div>
 </div>
 <div class='pad' style='margin-top:58px'>
  <h1 style='font-size:21px'>学籍メールアドレスで登録</h1>
  <div class='sub' data-p='2' data-a='l' style='margin:8px 0 22px;display:inline-block'>入力したアドレスに6桁の認証コードを送ります。</div>
  <div class='label'>学籍メールアドレス</div>
  <div style='display:flex;align-items:center;gap:8px'>
   <div class='field focus' data-p='3' style='flex:1'>s2301234<span style='display:inline-block;width:2px;height:22px;background:#5B5BD6;margin-left:2px'></span></div>
   <div data-p='4' data-a='tr' style='font-size:15px;font-weight:700;color:#4A4E5E'>@s.asojuku.ac.jp</div>
  </div>
  <div class='err' data-p='5' data-a='l' style='margin-top:10px;display:inline-block'>※ 本学の学籍メールアドレスのみ登録できます</div>
 </div>
 <div class='pad' style='position:absolute;bottom:56px;width:100%'>
  <div class='btn' data-p='6'>認証コードを送信</div>
 </div>
 <div class='home-ind'></div>
</div>""")

# ---------- G2 OTPコード入力 ----------
boxes = "".join(f"<div style='width:48px;height:60px;border-radius:14px;background:#fff;border:1.5px solid {'#5B5BD6' if i==4 else '#DCDCE8'};display:flex;align-items:center;justify-content:center;font-size:26px;font-weight:800'>{d}</div>" for i, d in enumerate("4829  "))
SCREENS["G2"] = ("phone", f"""
<div class='phone'>{STATUS}
 <div class='nav'><div class='side'><span data-p='1' data-a='r'>‹ 戻る</span></div><div></div><div class='side'></div></div>
 <div class='pad' style='margin-top:26px'>
  <h1 style='font-size:24px'>認証コードを入力</h1>
  <div class='sub' style='margin-top:10px' data-p='2' data-a='l'><b style='color:#1F2330'>s2301234@s.asojuku.ac.jp</b><br>に届いた6桁のコードを入力してください。</div>
  <div data-p='3' data-o='-14,-10' style='display:flex;justify-content:space-between;margin-top:34px'>{boxes}</div>
  <div class='err' data-p='4' data-a='l' style='margin-top:14px'>コードが正しくありません（残り4回）</div>
  <div style='margin-top:26px;text-align:center' class='sub'>コードが届かない場合 <span class='link' data-p='5' data-a='tr'>再送信（52秒後）</span></div>
 </div>
 <div class='pad' style='position:absolute;bottom:56px;width:100%'>
  <div class='btn' data-p='6'>認証する</div>
 </div>
 <div class='home-ind'></div>
</div>""")

# ---------- G3 プロフィール作成・編集 ----------
SCREENS["G3"] = ("phone", f"""
<div class='phone'>{STATUS}
 <div class='nav'><div class='side'><span data-p='1' data-a='r'>キャンセル</span></div><div>プロフィール</div><div class='side r'></div></div>
 <div style='text-align:center;margin-top:14px'>
  <div style='position:relative;width:116px;height:116px;margin:0 auto' data-p='2' data-o='-4,-2'>
   {st('田','#FFD166','#FF6B3D',0,0,116,0)}
   <div data-p='3' data-a='r' style='position:absolute;right:-4px;bottom:2px;width:38px;height:38px;border-radius:50%;background:#5B5BD6;border:3px solid #F6F5FB;color:#fff;font-size:22px;font-weight:800;display:flex;align-items:center;justify-content:center'>＋</div>
  </div>
  <div class='sub' style='font-size:12px;margin-top:8px'>このアイコンがステッカーになります</div>
 </div>
 <div class='pad' style='margin-top:18px'>
  <div class='label'>表示名 <span style='color:#E5484D'>*</span></div>
  <div class='field' data-p='4'>たなか けいと<span style='margin-left:auto;font-size:12px;color:#A9ACBC'>7/20</span></div>
  <div class='label' style='margin-top:16px'>学科 <span style='color:#E5484D'>*</span></div>
  <div class='field' data-p='5'>情報システム専攻科<span style='margin-left:auto;color:#A9ACBC'>⌄</span></div>
  <div class='label' style='margin-top:16px'>学年 <span style='color:#E5484D'>*</span></div>
  <div data-p='6' style='display:flex;background:#ECECF3;border-radius:12px;padding:3px;height:42px'>
   {''.join(f"<div style='flex:1;border-radius:10px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:15px;{'background:#fff;box-shadow:0 1px 4px rgba(0,0,0,.12)' if g==3 else 'color:#6B6F80'}'>{g}年</div>" for g in range(1,5))}
  </div>
  <div class='label' style='margin-top:16px'>ひとこと</div>
  <div class='field' data-p='7' style='height:74px;align-items:flex-start;padding-top:14px;font-size:15px'>Swiftでアプリ作ってます。話しかけてください！</div>
 </div>
 <div class='pad' style='position:absolute;bottom:56px;width:100%'>
  <div class='btn' data-p='8'>保存する</div>
 </div>
 <div class='home-ind'></div>
</div>""")

# ---------- G4 ホーム ----------
SCREENS["G4"] = ("phone", f"""
<div class='phone' style='background:linear-gradient(#F6F5FB,#ECEBF7)'>{STATUS}
 <div style='display:flex;align-items:center;justify-content:space-between;padding:6px 22px 0'>
  <div class='logo' style='font-size:26px' data-p='1' data-a='r'>BATT<span>ARI</span></div>
  <div data-p='2' data-a='l' style='position:relative;width:44px;height:44px'>{st('田','#FFD166','#FF6B3D',0,0,44,0,extra='border-width:3px')}</div>
 </div>
 <div style='padding:14px 22px 0'><div style='display:inline-flex;align-items:baseline;gap:8px' data-p='3' data-a='r'>
  <span style='font-size:30px;font-weight:900'>12</span><span class='sub' style='font-weight:700'>枚のステッカー</span>
 </div></div>
 <div style='margin:16px auto 0;width:334px' data-p='4' data-o='-10,-10'>
  {laptop(334, 390, collection(12, 1.0, p='5'))}
 </div>
 <div class='sub' style='text-align:center;font-size:12px;margin-top:14px'>ステッカーをタップで詳細・長押しで移動</div>
 <div class='pad' style='position:absolute;bottom:56px;width:100%'>
  <div class='btn' data-p='6' style='height:60px;border-radius:30px;font-size:18px'>📡 近くの人と交換する</div>
 </div>
 <div class='home-ind'></div>
</div>""")

# ---------- G5 交換待機 ----------
rings = "".join(f"<div style='position:absolute;left:50%;top:50%;width:{d}px;height:{d}px;transform:translate(-50%,-50%);border-radius:50%;border:2px solid rgba(255,255,255,{a})'></div>" for d, a in [(300,.10),(230,.18),(160,.28)])
SCREENS["G5"] = ("phone", f"""
<div class='phone' style='background:radial-gradient(circle at 50% 42%,#6E6EF0 0%,#3F3FB8 55%,#2A2A86 100%);color:#fff'>{STATUS.replace("class='status'","class='status' style='color:#fff'")}
 <div class='nav'><div class='side' style='color:#fff'><span data-p='1' data-a='r'>✕ 閉じる</span></div><div></div><div class='side'></div></div>
 <div style='text-align:center;margin-top:22px' class='pad' data-p='2' data-o='4,-18'>
  <div style='font-size:21px;font-weight:800;white-space:nowrap'>相手のスマホに近づけてください</div>
  <div style='font-size:14px;opacity:.8;margin-top:8px;line-height:1.6'>スマホ同士をくっつけるくらいの距離で<br>相手が見つかります</div>
 </div>
 <div data-p='3' data-o='40,30' style='position:relative;width:320px;height:320px;margin:30px auto 0'>{rings}
  <div data-p='4' data-o='-6,-6' style='position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:120px;height:120px'>{st('田','#FFD166','#FF6B3D',0,0,120,0)}</div>
 </div>
 <div style='text-align:center;margin-top:6px;font-size:15px;font-weight:700;opacity:.95'>探しています…</div>
 <div data-p='5' data-o='-12,-8' style='margin:34px 24px 0;background:rgba(255,255,255,.14);border-radius:14px;padding:14px 16px;font-size:13px;display:flex;gap:10px;align-items:center'>
  <span style='font-size:18px'>ᛒ</span><span>Bluetooth：オン　／　お互いにこの画面を開いてください</span>
 </div>
 <div class='home-ind' style='background:#fff'></div>
</div>""")

# ---------- G6 交換確認 ----------
SCREENS["G6"] = ("phone", f"""
<div class='phone' style='background:radial-gradient(circle at 50% 30%,#6E6EF0 0%,#3F3FB8 60%,#2A2A86 100%)'>{STATUS.replace("class='status'","class='status' style='color:#fff'")}
 <div style='text-align:center;color:#fff;margin-top:60px;font-size:15px;font-weight:700;opacity:.9'>相手が見つかりました！</div>
 <div style='position:absolute;left:0;right:0;bottom:0;height:560px;background:#fff;border-radius:30px 30px 0 0;padding:0 24px'>
  <div style='position:relative;width:150px;height:150px;margin:-76px auto 0' data-p='1' data-o='-8,4'>{st('佐','#FF8A5B','#FF4F81',0,0,150,-6)}</div>
  <div style='text-align:center;margin-top:16px' data-p='2' data-o='40,-4'>
   <div style='font-size:26px;font-weight:900'>さとう みく</div>
   <div class='sub' style='margin-top:6px;font-weight:600'>情報システム専攻科　2年</div>
  </div>
  <div style='margin-top:22px;text-align:center;font-size:17px;font-weight:700'>ステッカーを交換しますか？</div>
  <div data-p='5' data-o='-10,-8' style='margin-top:16px;background:#F1F1FC;border-radius:14px;padding:12px 14px;font-size:13px;color:#4A4E5E;text-align:center'>お互いが「交換する」を押すと交換されます</div>
  <div style='position:absolute;left:24px;right:24px;bottom:52px'>
   <div class='btn' data-p='3'>交換する</div>
   <div class='btn gray' data-p='4' style='margin-top:12px'>やめる</div>
  </div>
 </div>
 <div class='home-ind'></div>
</div>""")

# ---------- G7 ステッカー貼り付け ----------
SCREENS["G7"] = ("phone", f"""
<div class='phone' style='background:linear-gradient(#F6F5FB,#ECEBF7)'>{STATUS}
 <div style='text-align:center;margin-top:18px' data-p='1' data-o='10,-6'>
  <div style='font-size:13px;font-weight:800;color:#5B5BD6;letter-spacing:2px'>NEW STICKER</div>
  <div style='font-size:24px;font-weight:900;margin-top:4px'>さとう みく さんのステッカー</div>
  <div class='sub' style='margin-top:4px'>好きな場所にドラッグして貼ろう</div>
 </div>
 <div style='margin:30px auto 0;width:334px;position:relative' data-p='3' data-o='-10,40'>
  {laptop(334, 390, collection(9, 1.0))}
  <div style='position:absolute;left:150px;top:296px;width:96px;height:96px;border:3px dashed #5B5BD6;border-radius:50%;background:rgba(91,91,214,.08)'></div>
  <div data-p='2' data-o='-4,-4' style='position:absolute;left:186px;top:262px;width:110px;height:110px'>
   {st('佐','#FF8A5B','#FF4F81',0,0,110,-6,extra='box-shadow:0 18px 30px rgba(0,0,0,.35);transform:rotate(-6deg) scale(1.05)')}
  </div>
 </div>
 <div class='pad' style='position:absolute;bottom:56px;width:100%'>
  <div class='btn' data-p='4'>ここに貼る</div>
  <div class='btn ghost' data-p='5' style='margin-top:12px'>貼って続けて交換</div>
 </div>
 <div class='home-ind'></div>
</div>""")

# ---------- G8 ステッカー詳細 ----------
SCREENS["G8"] = ("phone", f"""
<div class='phone' style='background:#8A8B96'>{STATUS.replace("class='status'","class='status' style='color:#fff'")}
 <div style='position:absolute;left:0;right:0;bottom:0;height:720px;background:#fff;border-radius:28px 28px 0 0;padding:0 24px'>
  <div style='width:40px;height:5px;border-radius:3px;background:#D4D5DE;margin:10px auto 0'></div>
  <div style='position:absolute;right:20px;top:18px;width:32px;height:32px;border-radius:50%;background:#ECECF3;color:#6B6F80;display:flex;align-items:center;justify-content:center;font-weight:800' data-p='1' data-a='l'>✕</div>
  <div style='position:relative;width:170px;height:170px;margin:36px auto 0' data-p='2' data-o='-6,6'>{st('高','#7BD88F','#1FA37A',0,0,170,-4)}</div>
  <div style='text-align:center;margin-top:20px'>
   <div style='font-size:27px;font-weight:900;display:inline-block' data-p='3' data-a='l'>たかはし そうた</div>
   <div class='sub' style='margin-top:6px;font-weight:600;display:inline-block' data-p='4' data-a='l'>ゲームクリエイター学科　1年</div>
  </div>
  <div data-p='5' data-o='-8,-8' style='margin-top:24px;background:#F6F5FB;border-radius:16px;padding:16px 18px'>
   <div class='label' style='margin-bottom:6px'>ひとこと</div>
   <div style='font-size:15px;line-height:1.6'>Unityで2Dアクション作ってます🎮 学園祭で展示するので見に来てね</div>
  </div>
  <div data-p='6' data-o='-8,-8' style='margin-top:12px;display:flex;justify-content:space-between;background:#F6F5FB;border-radius:16px;padding:16px 18px;font-size:14px'>
   <span class='label' style='margin:0'>交換した日</span><span style='font-weight:700'>2026/11/03 14:22</span>
  </div>
  <div style='position:absolute;left:24px;right:24px;bottom:52px'>
   <div class='btn danger' data-p='7'>ステッカーをはがす</div>
  </div>
 </div>
 <div class='home-ind'></div>
</div>""")

BAR = "<div class='bar'><i style='background:#FF5F57'></i><i style='background:#FEBC2E'></i><i style='background:#28C840'></i><div class='url'>https://battari-admin.web.app/</div></div>"

def login_card(inner):
    return f"""<div class='web'>{BAR}
 <div style='display:flex;align-items:center;justify-content:center;height:764px'>
  <div class='card' style='width:440px;padding:44px 44px 40px'>
   <div class='logo' style='font-size:30px;text-align:center'>BATT<span>ARI</span></div>
   <div style='text-align:center;font-size:13px;font-weight:700;color:#6B6F80;margin-top:4px;letter-spacing:2px'>管理画面</div>
   {inner}
  </div>
 </div>
</div>"""

SCREENS["W1"] = ("web", login_card("""
   <div style='font-size:20px;font-weight:800;margin-top:30px' data-p='1' data-o='-30,0'>管理者ログイン</div>
   <div class='sub' style='margin:6px 0 22px'>登録済みの管理者メールアドレスに認証コードを送ります。</div>
   <div class='label'>メールアドレス</div>
   <div class='field focus' data-p='2'>admin@asojuku.ac.jp</div>
   <div class='err' style='margin-top:10px' data-p='3' data-o='-30,-4'>管理者として登録されていないメールアドレスです</div>
   <div class='btn' style='margin-top:26px;border-radius:12px' data-p='4'>認証コードを送信</div>"""))

wboxes = "".join(f"<div style='width:50px;height:58px;border-radius:12px;border:1.5px solid {'#5B5BD6' if i==6 else '#DCDCE8'};display:flex;align-items:center;justify-content:center;font-size:24px;font-weight:800'>{d}</div>" for i, d in enumerate("731940"))
SCREENS["W2"] = ("web", login_card(f"""
   <div style='font-size:20px;font-weight:800;margin-top:30px'>認証コードを入力</div>
   <div class='sub' style='margin:6px 0 22px' data-p='1' data-o='-30,0'><b style='color:#1F2330'>admin@asojuku.ac.jp</b> に送信しました。</div>
   <div data-p='2' data-o='-14,-10' style='display:flex;justify-content:space-between'>{wboxes}</div>
   <div class='err' style='margin-top:12px' data-p='3' data-o='-30,-4'>認証コードの有効期限が切れています</div>
   <div class='btn' style='margin-top:24px;border-radius:12px' data-p='4'>認証する</div>
   <div style='display:flex;justify-content:space-between;margin-top:18px'>
    <span class='link' data-p='5' data-o='-28,-4'>‹ メールアドレスを変更</span><span class='link' data-p='6' data-o='-28,-4'>コードを再送信</span>
   </div>"""))

users = [("s2301234@s.asojuku.ac.jp","Xk3p9QwZ…","2026/10/28 10:12","2026/11/03 14:22",True),
         ("s2304411@s.asojuku.ac.jp","b7LmR2aT…","2026/10/28 10:40","2026/11/03 13:05",True),
         ("s2402871@s.asojuku.ac.jp","Qe8vN1cY…","2026/10/29 09:03","2026/10/30 18:47",False),
         ("s2203356@s.asojuku.ac.jp","h2PwK7uF…","2026/10/30 12:55","2026/11/02 11:20",True),
         ("s2408890@s.asojuku.ac.jp","Zr5tA0dM…","2026/10/31 16:31","2026/11/03 09:58",True),
         ("s2305127@s.asojuku.ac.jp","m9GsE4jB…","2026/11/01 08:44","2026/11/01 08:46",True),
         ("s2401063@s.asojuku.ac.jp","Tc1yH6wL…","2026/11/02 17:10","2026/11/03 15:31",True)]
rows = ""
for i, (m, u, c, l, on) in enumerate(users):
    pa = "data-p='8' data-a='r'" if i == 0 else ""
    pu = "data-p='7' data-a='r'" if i == 0 else ""
    pd = "data-p='9' data-a='r'" if i == 0 else ""
    pl = "data-p='10' data-a='r'" if i == 0 else ""
    ps = "data-p='11' data-a='r'" if i == 0 else ""
    pb = "data-p='12' data-o='-10,-10'" if i == 0 else ""
    pc = "data-p='13' data-o='-10,-10'" if i == 0 else ""
    rows += (f"<tr><td class='mono'><span {pu}>{u}</span></td><td><span {pa}>{m}</span></td><td><span {pd}>{c}</span></td><td><span {pl}>{l}</span></td>"
             f"<td><span {ps} class='pill {'on' if on else 'off'}'>{'有効' if on else '無効'}</span></td>"
             f"<td><span class='sbtn' {pb}>{'無効化' if on else '有効化'}</span><span class='sbtn red' {pc}>削除</span></td></tr>")
SCREENS["W3"] = ("web", f"""<div class='web'>{BAR}
 <div style='height:60px;background:#fff;border-bottom:1px solid #E6E7EE;display:flex;align-items:center;padding:0 32px'>
  <div class='logo' style='font-size:22px'>BATT<span>ARI</span></div><span style='margin-left:12px;font-size:13px;font-weight:700;color:#6B6F80'>管理画面</span>
  <div style='margin-left:auto;font-size:13px;color:#4A4E5E' data-p='1' data-o='-30,-2'>admin@asojuku.ac.jp</div>
  <span class='sbtn' style='margin-left:16px' data-p='2' data-o='-10,-12'>ログアウト</span>
 </div>
 <div style='padding:28px 32px'>
  <div style='display:flex;align-items:center'>
   <div style='font-size:22px;font-weight:800'>ユーザー管理</div>
   <div style='margin-left:14px;font-size:14px;color:#6B6F80' data-p='3' data-a='r'>登録ユーザー <b style='color:#1F2330'>128</b> 名</div>
  </div>
  <div style='display:flex;gap:12px;margin-top:18px'>
   <div class='field' style='width:380px;height:42px;border-radius:10px;font-size:14px' data-p='4'><span class='ph'>🔍 メールアドレスで検索</span></div>
   <div data-p='5' style='display:flex;background:#E9EAF0;border-radius:10px;padding:3px;height:42px;font-size:13px;font-weight:700'>
    <div style='padding:0 16px;display:flex;align-items:center;background:#fff;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.1)'>すべて</div>
    <div style='padding:0 16px;display:flex;align-items:center;color:#6B6F80'>有効</div>
    <div style='padding:0 16px;display:flex;align-items:center;color:#6B6F80'>無効</div>
   </div>
  </div>
  <div class='card' style='margin-top:18px;overflow:hidden' data-p='6' data-o='-10,-10'>
   <table><tr><th>UID</th><th>メールアドレス</th><th>登録日時</th><th>最終ログイン日時</th><th>状態</th><th>操作</th></tr>{rows}</table>
   <div style='display:flex;justify-content:space-between;align-items:center;padding:14px 18px;font-size:13px;color:#6B6F80'>
    <span data-p='14' data-a='r'>1〜20件 / 128件</span>
    <span data-p='15' data-o='-28,-4'><span class='sbtn'>‹ 前へ</span><span class='sbtn'>次へ ›</span></span>
   </div>
  </div>
 </div>
</div>""")

if __name__ == "__main__":
    import sys
    targets = sys.argv[1:] or list(SCREENS)
    for sid in targets:
        kind, body = SCREENS[sid]
        w, h = (390, 844) if kind == "phone" else (1280, 800)
        html = os.path.join(OUT, f"{sid}.html")
        open(html, "w", encoding="utf-8").write(page(body, w, h))
        png = os.path.join(OUT, f"{sid}.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        f"--window-size={w},{h}", "--force-device-scale-factor=2",
                        f"--screenshot={png}", "file://" + html],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        print(sid, os.path.exists(png))
