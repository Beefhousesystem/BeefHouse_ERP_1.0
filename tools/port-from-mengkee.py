#!/usr/bin/env python3
"""从明记 ERP 同步代码到牛室（2026-11-27 起牛室改用明记的设计和功能）。
设计、功能用明记最新的；牛室自己的东西保留：Supabase 项目/key、推送公钥、店（Setapak + 中央厨房）、
供应商目录、菜单、种子数据、logo、岗位代号（hrmanager / manager=店面经理 / ckmanager；明记的店长在牛室叫 storemgr）。
每次都从明记原档重新生成 index.html / sw.js / i18n.js 等，所以牛室这边不要直接改这些文件——
要改的东西要么先在明记改，要么写进本脚本（像「数据兼容」「最高权限账号保护」那几段）。
用法：
  git clone --depth 1 https://github.com/Mengkeesystem/ERP-testing-1.0 /tmp/mk
  python3 tools/port-from-mengkee.py /tmp/mk 1201a
然后照 CLAUDE.md 的流程：语法检查 → Playwright 测 → 提交推 main。
⚠️ 脚本里每一处替换都要求「刚好找到 N 处」，找不到就停下报错（明记改了代码结构时会发生），
   这时要看明记改了什么再调整本脚本，绝不能硬推。
"""
import re, sys, os, shutil

# ================= 工具：找出一整段 const / function =================
def block(src, start_pat):
    """返回 (start,end) 字符位置：从 start_pat 开始，到括号平衡后的 ; 或换行"""
    m=re.search(start_pat, src, re.M)
    if not m: return None
    i=m.start(); j=src.index('=',m.start())+1 if start_pat.startswith('^const') else src.index('{',m.start())
    depth=0; k=j; instr=None; started=False
    while k<len(src):
        c=src[k]
        if instr:
            if c=='\\': k+=2; continue
            if c==instr: instr=None
        elif c in '"\'`': instr=c
        elif c in '([{': depth+=1; started=True
        elif c in ')]}':
            depth-=1
            if started and depth==0:
                k+=1
                if k<len(src) and src[k]==';': k+=1
                return (i,k)
        k+=1
    return None

# ================= 主程序 =================


if len(sys.argv) < 3:
    raise SystemExit('用法：python3 tools/port-from-mengkee.py <明记仓库路径> <新BUILD号，例如 1201a>')
MK = os.path.abspath(sys.argv[1])
BH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = sys.argv[2]

mk = open(f'{MK}/index.html', encoding='utf-8').read()
bh = open(f'{BH}/index.html', encoding='utf-8').read()   # 牛室现在的版本：只从这里拿牛室自己的数据常量（店、供应商、菜单、种子数据、logo）

def must(cond, msg):
    if not cond:
        raise SystemExit('❌ ' + msg)

def sub1(s, old, new, count=1):
    n = s.count(old)
    must(n == count, f'期望 {count} 处，实际 {n} 处：{old[:80]!r}')
    return s.replace(old, new)

# ---------- 1. 岗位代号：明记 → 牛室 ----------
# 明记的 manager 是「店长」，牛室没有这个岗位；先改名 storemgr，避免跟牛室的 manager(店面经理) 撞名。
s = mk
s = re.sub(r"(['\"])manager\1", r"\1storemgr\1", s)
for ln_key in ['  manager:{name:"店长', 'roleName={manager:', 'rolePill={manager:']:
    s = sub1(s, ln_key, ln_key.replace('manager:', 'storemgr:'))
s = re.sub(r'\boutletmgr\b', 'manager', s)
s = re.sub(r'\bhrmgr\b', 'hrmanager', s)
s = re.sub(r'\bckmgr\b', 'ckmanager', s)

# ---------- 2. 牛室的数据常量（店、供应商、菜单、种子数据） ----------
def swap_const(s, name, repl=None):
    a = block(s, r'^const ' + name + r'\s*=')
    must(a, f'明记里找不到 const {name}')
    if repl is None:
        b = block(bh, r'^const ' + name + r'\s*=')
        must(b, f'牛室里找不到 const {name}')
        repl = bh[b[0]:b[1]]
    return s[:a[0]] + repl + s[a[1]:]

s = swap_const(s, 'OUTLETS')
s = swap_const(s, 'SUPPLIER_CATALOG')
s = swap_const(s, 'SUPPLIER_META', 'const SUPPLIER_META={};')
s = swap_const(s, 'MENU_ITEMS')
a = block(s, r'^function seed\('); b = block(bh, r'^function seed\(')
must(a and b, 'seed() 找不到')
s = s[:a[0]] + bh[b[0]:b[1]] + s[a[1]:]
for name in ['DISH_CATALOG', 'MENU_PRICES', 'MENU_PV', 'SEED_VERSION']:
    x = block(s, r'^const ' + name + r'\s*=') if name != 'SEED_VERSION' else None
    if name == 'SEED_VERSION':
        must('const SEED_VERSION="bh-master-2026-09-1"' in s, 'SEED_VERSION 跟牛室不一致（会重置数据！）')
    else:
        y = block(bh, r'^const ' + name + r'\s*=')
        must(s[x[0]:x[1]] == bh[y[0]:y[1]], f'{name} 跟牛室不一样')

# ---------- 3. Supabase / 推送 / 网址 ----------
s = sub1(s, 'https://kmcdokwiyetlmsrdlgqw.supabase.co', 'https://cogxtzduusuzjumsdkxy.supabase.co', 2)
s = re.sub(r'const SUPABASE_ANON_KEY = "[^"]+"', 'const SUPABASE_ANON_KEY = "sb_publishable_0BSR2rrDXtWGDc_5IgYJmw_4xveik9c"', s)
s = re.sub(r'const VAPID_PUBLIC = "[^"]+"', 'const VAPID_PUBLIC = "BA0zbNjrZ3ifUdLungX8DYv4VHAiftBV2IxO003bKw07HYH4X3CQ00FN7yGpxSjhfKqIDCS5XiGmEFfZA-_BgXM"', s)
must('kmcdokwiyetlmsrdlgqw' not in s and 'HVJ_hcFmSDU' not in s, '还有明记的 Supabase 设定')

# AI 小助手 / 拍照识别：要另外在牛室 Supabase 部署函数并设 API Key，先关掉（网址留空 = 功能隐藏）
s = sub1(s, 'const AI_FN_URL=SUPABASE_URL?(SUPABASE_URL+"/functions/v1/ask-ai"):"";',
         'const AI_FN_URL="";   // 牛室：AI 小助手还没在牛室 Supabase 部署（要 API Key），留空 = 隐藏。开通时改回 SUPABASE_URL+"/functions/v1/ask-ai"')
s = sub1(s, 'const INV_OCR_URL=SUPABASE_URL?(SUPABASE_URL+"/functions/v1/invoice-ocr"):"";',
         'const INV_OCR_URL="";   // 牛室：拍照识别还没在牛室 Supabase 部署（要 API Key），留空 = 隐藏。开通时改回 SUPABASE_URL+"/functions/v1/invoice-ocr"')
s = sub1(s, 'function aiAllowed(){return AI_ROLES', 'function aiAllowed(){return !!AI_FN_URL&&AI_ROLES')
s = sub1(s, 'if(!AUTH()||!INV_OCR_URL)return alert(zh?"拍照识别需要登录云端账号后才能用":"Sign in to use invoice scan");',
         'if(!INV_OCR_URL)return alert(zh?"拍照识别还没开通（需要先在 Supabase 部署识别功能）":"Invoice scan is not enabled yet");if(!AUTH())return alert(zh?"拍照识别需要登录云端账号后才能用":"Sign in to use invoice scan");')

# ---------- 4. 招牌 / logo ----------
bh_logo_css = next(l for l in bh.split('\n') if l.strip().startswith('.bh-logo{display:inline-block;background-image'))
mk_logo_css = next(l for l in s.split('\n') if l.strip().startswith('.bh-logo{display:inline-block;background-image'))
s = sub1(s, mk_logo_css, bh_logo_css)
m = re.search(r'<svg width="34" height="34" viewBox="0 0 100 100" aria-label="明记".*?</svg>', s, re.S)
must(m, '页头明记 logo 找不到')
s = s[:m.start()] + '<span class="bh-logo" style="width:34px;height:34px;border-radius:7px;" aria-label="牛室"></span>' + s[m.end():]
must(not re.search(r'<svg[^>]*aria-label="明记"', s), '还有别的明记 svg logo')

for old, new in [('明记家乡小食店 · Meng Kee', '牛室炙烤牛排 · Beef House'),
                 ('明记家乡小食店', '牛室炙烤牛排'),
                 ('Meng Kee Eatery', 'Beef House'),
                 ('Meng Kee Assistant', 'Beef House Assistant'),
                 ('Meng Kee', 'Beef House'),
                 ('明记ERP_', '牛室ERP_'),
                 ('明记', '牛室')]:
    s = s.replace(old, new)

# ---------- 4b. 图标网址加版本号：iPhone/Safari 不会拿旧的缓存图标（牛室旧图标有白边） ----------
s = sub1(s, '<link rel="apple-touch-icon" href="apple-touch-icon.png">', '<link rel="apple-touch-icon" href="apple-touch-icon.png?v=bh2">')
s = sub1(s, '<link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">', '<link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png?v=bh2">')
s = sub1(s, '<link rel="icon" href="icon-192.png" sizes="192x192">', '<link rel="icon" href="icon-192.png?v=bh2" sizes="192x192">')

# ---------- 4c. 牛室的 Default 主题：蓝色为主、白色为辅（业主 2026-11-27 要求；明记的 Default 是象牙底+酒红） ----------
BH_BLUE_CSS = """/* ---- 牛室 Default：蓝色为主、白色为辅（只换颜色变量，版面不动；由 tools/port-from-mengkee.py 加进来） ---- */
html.ui2[data-theme="classic"]{
  --ink:#0F2336;--ink2:#34506B;--paper:#DCE9F6;--card:#FFFFFF;--line:#C6D8EB;--line2:#AFC6DD;
  --brand:#0F5A8C;--brand2:#1F72AB;--brand-dk:#0A3F63;--gold:#2E86C1;--red:#C0392B;--amber:#A8731A;--green:#2E7D52;
  --blue:#1F72AB;--purple:#5B5FA8;--grey:#5F7489;--soft:#EAF2FA;--hover:#D6E5F4;--row-hover:#F3F8FD;--row-line:#E3EDF7;--hint-bg:#E8F1FA;
  --btn:#0F5A8C;--btn-hover:#0A3F63;--focus:rgba(15,90,140,.18);--shadow-bub:rgba(15,90,140,.4);
  --top-bg:#0B3D5F;--top-solid:#0B3D5F;--top-ink:#FFFFFF;--top-line:#0B3D5F;--top-btn-bg:rgba(255,255,255,.12);--top-btn-line:rgba(255,255,255,.35);--top-btn-hover:rgba(255,255,255,.22);
  --sel-bg:rgba(255,255,255,.14);--sel-ink:#FFFFFF;--sel-line:rgba(255,255,255,.45);
  --side-bg:#0F4A73;--side-ink:#D6E6F5;--side-hover:rgba(255,255,255,.10);--side-active-bg:#FFFFFF;--side-active-ink:#0B3D5F;--side-bar:#FFFFFF;--side-icon-on:#0F5A8C;--side-grp:#9DBEDB;
  --th-ink:#3E5F80;--th-line:#C6D8EB;--tab-bg:rgba(255,255,255,.97);
  --grid-line:#C3D5E8;--grid-line2:#AFC6DD;--grid-head:#E3EDF7;--grid-c1:#F3F8FD;--grid-c2:#EAF2FA;--grid-lab:#D6E5F4;
}
"""
s = sub1(s, '/* ---- 机械风：钢灰', BH_BLUE_CSS + '/* ---- 机械风：钢灰')
s = re.sub(r"classic:\{zh:'Default 默认',en:'Default',desc:'[^']*',color:'#[0-9A-Fa-f]+',sw:\[[^\]]*\]\}",
           "classic:{zh:'Default 默认',en:'Default',desc:'牛室蓝：蓝色为主、白色为辅；清爽、好读',color:'#0B3D5F',sw:['#0B3D5F','#0F5A8C','#DCE9F6','#FFFFFF']}", s, count=1)
must("desc:'牛室蓝" in s, 'UI2_THEMES.classic 没换到')
s = s.replace('classic  = Default 默认（暖象牙底 + 牛室酒红 + 金色点缀）', 'classic  = Default 默认（牛室：蓝色为主、白色为辅，见下面「牛室 Default」那段）')

# ---------- 5. 版本号 ----------
s = re.sub(r'const BUILD="[^"]+";', f'const BUILD="{BUILD}";', s, count=1)

# ---------- 6. 数据兼容：牛室员工档案的登录邮箱字段叫 loginEmail，明记叫 email ----------
s = sub1(s, "  for(const {o,data:d0} of got){\n    let data=d0;\n",
         "  for(const {o,data:d0} of got){\n    let data=d0;\n"
         "    if(data&&Array.isArray(data.staff))data.staff.forEach(e=>{if(e&&!e.email&&e.loginEmail)e.email=e.loginEmail;});   // 牛室旧档案：登录邮箱存在 loginEmail\n")

# ---------- 6b. 数据兼容：牛室旧版的 erpv2:payroll:<店> 直接就是 payrollRuns（{"2026-10":{…}}），
# 明记格式是 {v:1,staff:{…},payrollRuns:{…}}。不转换的话，载入时会被当成空的再覆盖掉（薪资发放记录会丢）。
s = sub1(s, "  let pay=f.val;const legacy=hasLegacyPay(db);let changed=false;\n",
  "  let pay=f.val;const legacy=hasLegacyPay(db);let changed=false;\n"
  "  if(pay&&typeof pay==='object'&&!Array.isArray(pay)&&pay.v==null&&!pay.staff&&!PAY_TOP.some(k=>k in pay)&&Object.keys(pay).every(k=>/^\\d{4}-\\d{2}$/.test(k))){\n"
  "    // 牛室旧格式：整份就是薪资发放记录。先原样备份（只有执行董事/人事经理写得进），再转成新格式\n"
  "    if(payWriter()){if(!(await payWriteNow('erpv2:payroll:bak:bhv1:'+oid,pay)))return false;}\n"
  "    pay={v:1,staff:{},payrollRuns:pay};if(payWriter())changed=true;\n"
  "  }\n")

# ---------- 7. 系统最高权限账号保护（牛室原有，明记没有） ----------
guard = '''// 牛室：系统最高权限账号（创办人）保护——别的账号改不了、删不了它；执行董事(owner)账号只有执行董事能动。
// 数据库 erp_users 的写入规则也有同样的条件（bh-erp-upgrade.sql），两边邮箱要一致。
const SUPREME_OWNER_EMAIL=NO_CODE_EMAIL;
function supremeGuard(target,newRole){
  const zh=LANG==="zh";const me=((curUser&&curUser.email)||'').toLowerCase();const t=(target||'').toLowerCase();
  if(!curUser)return null;
  if(t===SUPREME_OWNER_EMAIL&&me!==SUPREME_OWNER_EMAIL)return zh?"这是系统最高权限账号，只有本人能修改。":"Only the system owner can change this account.";
  const old=(USERS||[]).find(u=>(u.email||'').toLowerCase()===t);
  if(((old&&old.role==='owner')||newRole==='owner')&&curUser.role!=='owner')return zh?"执行董事账号只有执行董事能新增/修改/删除。":"Only a Director can manage Director accounts.";
  return null;
}
async function saveUser(orig){'''
s = sub1(s, 'async function saveUser(orig){', guard)
s = sub1(s, "  if(!email){alert(LANG===\"zh\"?\"邮箱必填\":\"Email required\");return;}\n",
         "  if(!email){alert(LANG===\"zh\"?\"邮箱必填\":\"Email required\");return;}\n  {const g=supremeGuard(email,role);if(g){alert(g);return;}}\n")
s = sub1(s, "async function delUser(email){\n",
         "async function delUser(email){\n  {const g=supremeGuard(email,null);if(g){alert(g);return;}}\n")

open(f'{BH}/index.html', 'w', encoding='utf-8').write(s)

# ---------- sw.js ----------
sw = open(f'{MK}/sw.js', encoding='utf-8').read()
sw = sw.replace('明记家乡小食店', '牛室炙烤牛排').replace("'mengkee-erp-'", "'beefhouse-erp-'")
sw = re.sub(r"const SW_VERSION = '[^']+'", f"const SW_VERSION = '{BUILD}'", sw)
must("'beefhouse-erp-'" in sw and BUILD in sw, 'sw.js 替换失败')
open(f'{BH}/sw.js', 'w', encoding='utf-8').write(sw)

# ---------- i18n.js（越南文/缅甸文词典，词条要跟 index.html 的中文一致）----------
i18 = open(f'{MK}/i18n.js', encoding='utf-8').read()
for old, new in [('明记家乡小食店', '牛室炙烤牛排'), ('Meng Kee', 'Beef House'), ('明记', '牛室')]:
    i18 = i18.replace(old, new)
open(f'{BH}/i18n.js', 'w', encoding='utf-8').write(i18)

# ---------- 其他文件 ----------
shutil.copy(f'{MK}/icon-update.png', f'{BH}/icon-update.png')
open(f'{BH}/404.html', 'w', encoding='utf-8').write(
    open(f'{MK}/404.html', encoding='utf-8').read().replace('ERP-testing-1.0', 'BeefHouse_ERP_1.0'))
print('OK', BUILD, len(s))

# ================= 其他文件（推送函数、文档、工作流） =================
URL_MK='https://kmcdokwiyetlmsrdlgqw.supabase.co'; URL_BH='https://cogxtzduusuzjumsdkxy.supabase.co'
PAGES_BH='https://beefhousesystem.github.io/BeefHouse_ERP_1.0/'
def roles(s):
    s=re.sub(r'(["\'])manager\1',r'\1storemgr\1',s)
    s=re.sub(r'\boutletmgr\b','manager',s); s=re.sub(r'\bhrmgr\b','hrmanager',s); s=re.sub(r'\bckmgr\b','ckmanager',s)
    return s
def brand(s):
    for a,b in [('明记家乡小食店','牛室炙烤牛排'),('Meng Kee','Beef House'),('明记','牛室'),('admin@mengkee.local','admin@beefhouse.local'),
                (URL_MK,URL_BH),('kmcdokwiyetlmsrdlgqw','cogxtzduusuzjumsdkxy'),('https://mengkeesystem.github.io/ERP-testing-1.0/',PAGES_BH),
                ('Mengkeesystem/ERP-testing-1.0','Beefhousesystem/BeefHouse_ERP_1.0'),('PUSH_SETUP_MENGKEE.md','PUSH_SETUP.md'),('STORAGE_SETUP_MENGKEE.md','STORAGE_SETUP.md')]:
        s=s.replace(a,b)
    return s
# 推送函数
f=open(f'{MK}/supabase/functions/send-order-push/index.ts',encoding='utf-8').read()
f=brand(roles(f))
f=f.replace('const ALLOWED_ORIGIN = "https://mengkeesystem.github.io";',
 '// 牛室：允许的网页来源放在 Secret ALLOWED_ORIGINS（多个用逗号隔开）；没设就用默认值\nconst ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "https://beefhousesystem.github.io").split(",").map((x) => x.trim()).filter(Boolean);')
f=f.replace('if ((req.headers.get("origin") || "") === ALLOWED_ORIGIN) h["Access-Control-Allow-Origin"] = ALLOWED_ORIGIN;',
 'const og = req.headers.get("origin") || "";\n  if (ALLOWED_ORIGINS.includes(og)) h["Access-Control-Allow-Origin"] = og;')
f=f.replace('const OUTLET_RE = /^(b([1-9]|1[01])|ck)$/;','const OUTLET_RE = /^(b[0-9]+|ck)$/;')
assert 'ALLOWED_ORIGIN ' not in f and 'ALLOWED_ORIGIN)' not in f, 'ALLOWED_ORIGIN 还有残留'
assert 'mengkee' not in f.lower() and 'hrmgr' not in f
open(f'{BH}/supabase/functions/send-order-push/index.ts','w',encoding='utf-8').write(f)
# AI / 拍照识别函数（先放着，牛室还没开通）
for fn in ['ask-ai','invoice-ocr']:
    os.makedirs(f'{BH}/supabase/functions/{fn}',exist_ok=True)
    t=brand(roles(open(f'{MK}/supabase/functions/{fn}/index.ts',encoding='utf-8').read()))
    t=t.replace('"https://mengkeesystem.github.io"','"https://beefhousesystem.github.io"')
    open(f'{BH}/supabase/functions/{fn}/index.ts','w',encoding='utf-8').write(t)
# 文档 / SQL / 工作流 / 工具
for src,dst in [('PUSH_DIGEST_SETUP.md','PUSH_DIGEST_SETUP.md'),('push-digest-cron.sql','push-digest-cron.sql'),
                ('AI_ASSISTANT_SETUP.md','AI_ASSISTANT_SETUP.md'),('INVOICE_OCR_SETUP.md','INVOICE_OCR_SETUP.md'),
                ('.github/workflows/notify-update.yml','.github/workflows/notify-update.yml'),('tools/code-page.py','tools/code-page.py'),
                ('.claude/skills/owner-deploy-guide/SKILL.md','.claude/skills/owner-deploy-guide/SKILL.md')]:
    os.makedirs(os.path.dirname(f'{BH}/{dst}') or BH,exist_ok=True)
    t=brand(roles(open(f'{MK}/{src}',encoding='utf-8').read()))
    open(f'{BH}/{dst}','w',encoding='utf-8').write(t)
for p in ['supabase/functions','PUSH_DIGEST_SETUP.md','push-digest-cron.sql','AI_ASSISTANT_SETUP.md','INVOICE_OCR_SETUP.md','.github/workflows/notify-update.yml','.claude']:
    os.system(f"grep -rln 'mengkee\\|kmcdok\\|明记\\|hrmgr' {BH}/{p} 2>/dev/null")
print('其他文件 OK')
