# 项目备忘 (CLAUDE.md)

本仓库是 **牛室炙烤牛排 (Beef House)** 的单文件 HTML ERP（`index.html`）。
业主同时经营 **明记家乡小食店（马来西亚中餐）**，后续会**把 Beef House 这套 ERP 复制给明记用**——
但两间店有些设定不一样，复制时要**因店制宜**，不能照搬。以下是必须记住的差异点。

## 两间店的定位
- **牛室 Beef House** = Western **buffet（自助餐，吃到饱）** + 部分单点牛扒/饮料。
- **明记** = 马来西亚**中餐小食店**（煮炒/单点 + 可能有经济饭/杂饭）。

## 成本核算差异（重要 · 复制 ERP 时要调整）
这是业主明确点出的第一个「不一样」的例子：**要不要用 BOM（配方成本，逐道列食材自动算成本）**。

| | 做 BOM（配方成本） | 走「月度核算」(月初库存 + 进货 − 月末库存) |
|---|---|---|
| **牛室 buffet** | ⚠️ 自助餐**主体(B1 纯爱自助吧)**不逐道 BOM（客人拿多少不固定，算不准）；但**单点菜 B2–D4（牛扒/鸡扒/鱼排/海鲜/饮料）要做 BOM** | ✅ 自助餐主体走月度核算：月底盘点一次，算整体食材成本与成本率(健康 30–38%) |
| **明记 中餐** | ✅ **主力单点/煮炒菜（招牌、卖最多的 10–20 道）值得做 BOM**：配方较固定，进货价一涨系统自动重算毛利 | ✅ 兜底：杂饭/夹菜/少卖的小菜走月度核算 |

**一句话：** 牛室 = 自助餐主体(B1)走月度核算 + **单点 B2–D4 做 BOM**；明记 = 主力单点菜做 BOM + 杂饭小菜走月度核算。**两店都是 BOM + 月度核算并用，只是比重不同。**

## 盘点 vs 月末算货差异（第二个两店不一样的例子）
两个是不同功能、都要月底数实物，但角度不同：
- **📋 盘点 (Stock Take)**：库存组独立页，逐品项录入实盘 → 算「**理论 vs 实盘 盘差**」，抓**隐性损耗**（被偷/浪费/漏记）。数据 `d().stocktakes`。
- **🧮 月末算货 (Month-End)**：在「采购进销」作业中心里，按供应商整表录入 → 得「**月末库存值**」，喂给**月度核算**算 COGS(`月初+进货−月末`)。数据 `d().monthEnd`。

| | 主用 | 辅助 |
|---|---|---|
| **🥩 牛室 buffet** | **月末算货**（算成本率） | 盘点（偶尔抓贵货如牛肉/海鲜的损耗） |
| **🍜 明记 中餐** | **盘点**（配合 BOM，用理论用量抓损耗） | 月末算货（杂饭/小菜兜底走月度核算） |

**逻辑同 BOM 那条：牛室=整体看（月度核算+月末算货）；明记=逐道看（BOM+盘点抓差异）。**

### 牛室已做的调整（2026-09，BUILD 0913c）
- 已把 **月末算货合并到侧栏「库存」组、放在原「盘点」的位置，改名「月末盘点」**（`monthend` 页，图标📋）。牛室 buffet 主用它，所以放到最顺手的位置。
- **作业中心(采购进销)里原本的「月末算货」卡片已移除**，避免重复入口。
- 逐品项的旧「盘点」页 `pgStock`（`stock`）**代码仍保留在文件里，只是从侧栏菜单拿掉了**。
- ⚠️ **复制给明记时要改回来**：明记主用逐品项盘点(pgStock)，需要把 `stock` 重新放回侧栏「库存」组（配合 BOM 的理论用量抓盘差）；月末算货可留在作业中心或按需摆放。

## 复制到明记时的注意事项（通则）
1. **数据完全隔离**：明记必须用**独立的 Supabase 项目**，绝不能碰到牛室（或 815 明记家乡小食店网站）的数据。
2. 复制的是**功能/结构**，不是**内容**：菜单菜品、供应商、配方、OpEx 科目、buffet vs 单点的核算方式等，都要按明记实际情况重设。
3. 遇到「这个不一样」的地方，**先问业主 / 按本备忘调整**，不要照抄牛室的默认值。
4. 之后每发现一个两店差异，**追加记录到本文件**，方便复制时逐条对照。

## ⭐ 用 Beef House 更新明记 ERP（保留明记数据）——复制清单
业主确认：**明记已有自己的 ERP（旧版），数据存在明记自己独立的 Supabase 项目**。
目标：把牛室的**新功能/代码改动**搬过去，但**明记的数据(供应商/BOM/月末等)一律保留**。

### 核心原理：代码 ≠ 数据
- **数据**（供应商、BOM 配方、月末算货、库存…）存在**各店自己的 Supabase + 浏览器**，**不在 `index.html` 里**。
- 所以「更新代码」**不会动到明记的数据**——前提是明记继续连**它自己的 Supabase**（下列配置不改）。
- 这条路最安全：不需要为了共享而开放任何 Supabase 数据。

### 复制时【必须保留明记自己的】（逐行核对，别照抄牛室）
1. **Supabase 配置**（`index.html` 内）——改了会连错库/丢数据，务必用明记的：
   - `const SUPABASE_URL = ...`（约 955 行）
   - `const SUPABASE_ANON_KEY = ...`（约 956 行，publishable key）
   - `VAPID_PUBLIC` / `PUSH_FN_URL` / `RECEIPT_BUCKET`（约 961-964 行，如明记有自己的推送/存储则用明记的）
2. **名字/招牌**：`appTitle`、页头 logo（约 270、595-597 行；明记用「Meng Kee」相关，别显示牛室）。
3. **明记自己的种子供应商**：`const SUPPLIER_CATALOG = {...}`（约 299 行）用明记的；牛室的供应商别带过去。
   - 注：即使种子不改，明记 Supabase 里已保存的供应商也会覆盖种子；但仍建议换成明记的，避免新/空门店显示牛室供应商。
4. **盘点 + BOM 的摆位**（见上文两店差异）：明记主用**逐品项盘点(pgStock)**，要把 `stock` 重新放回侧栏「库存」组（牛室已从菜单拿掉但代码仍在）；BOM 是明记主用，保留。
5. `const OUTLETS = [...]`（约 294 行）：明记的门店列表，用明记的。

### 复制时【一律用牛室最新的】
- 其余所有新功能/改动：运营开销录入(opexm)、订单发票(orderinv)、应付账款对账/付款、进货单&月末盘点表格的**排序/复制/删除(cid)**、Invoice 弹窗、库存页「需要注意」折叠、月末盘点(只留当月最后一天)、**薪资发放 Payroll(payrun)+Payslip** 等。
- 薪资发放(payrun)用**马来西亚法定公式**(全国通用，两店相同)：EPF 第三附表(依**国籍**判本地，马来西亚=本地有EPF)、SOCSO/EIS 第二附表(费率×薪级中点)、SL24J 员工承担(封顶6000，**按工龄自动** 0.75%<2年 / 1.0%第3-5年 / 1.25%第6年+，从入职日期算)、PCB 为 YA2025 累进税估算(可手改，正式以 LHDN e-PCB 为准)。OT=时数×(底薪÷26÷8)×倍数(1.0-3.0)。表格**一填即时结算**(payLiveRecalc,不整页重绘)、满宽(`.main.wide`)。数据存 `d().payrollRuns[月]`；已婚/孩子/国籍/职位等存员工档案。
- 薪资发放(payrun)**仅老板/HR(salaryView:"full")可看与编辑**(pageAllowed 加 canSeeSalary)；表格含**雇主承担列**(EPF雇/SOCSO雇/EIS雇)。
- **运营开销的人工成本 = Payroll 的雇主总成本**：`payrollLabour()` 已改用同一套法定引擎(computeRow)计算(salaries=底薪+津贴+奖励、ot=加班额、epf/socso/eis=雇主承担、levy)，两处数字一致；改动员工后需点『🔗同步人事薪资』或自动联动刷新。
- 员工档案(pgHR/emp表单)字段：员工号(EMP001起,自动)、姓名、职位(下拉,`d().positions`可增删改)、国籍(下拉,`d().nationalities`默认马来西亚/缅甸,可增删改)、IC/护照、电话、地址、紧急联络人、入职日期、婚姻(未婚/已婚/离婚)、孩子数、底薪、津贴。国籍→EPF本地判定(`empIsLocal`)。
- 作业中心六项均**按月份分开**：进货单/月末盘点(网格月份tab)、报废损耗/招待/调拨(flatMonthTabs 按月筛选)；**退货/补货(grn)已重做**成「供应商→选月份→逐笔表单登记(退货/补货)」风格(pgReturns/formReturn，数据仍存 d().grn，settle=退货|补货)，不再用每日网格。订货单是实时模板(其订单在订单发票按月归档)。
- 复制完，明记那边**可继续自行修改**（它有独立的一份代码+数据）。

## 注册邀请码（牛室，2026-09）
员工/管理层首次注册账号时，在注册表单「邀请码 / 口令」栏填入对应邀请码，由 Supabase 触发器识别并赋予角色和分店：

| 角色 | 邀请码 | 分店 |
|---|---|---|
| 区域副经理 `area` | `tcymgmt888` | 全分店 |
| Setapak店 店面经理 `manager` | `stpbhmgr888` | Setapak店 (b1) |
| Setapak店 厨师长 `headchef` | `stpbhchef888` | Setapak店 (b1) |
| Setapak店 员工 `staff` | `stpbhstaff888` | Setapak店 (b1) |
| 中央经理 `ckmanager` | `tcymgr888` | 中央厨房 (ck) |
| 中央员工 `ckstaff` | `tcystaff888` | 中央厨房 (ck) |

⚠️ **2026-09-19 二次更新**：店面/厨师长/员工的邀请码从原本通用的 `bfmgr888`/`chef888`/`bfstaff888` 改成带 **Setapak 店名前缀**的 `stpbh*888`——因为以后可能会开更多分店，以后每开一间新分店都要给它专属的一组邀请码（不能沿用 Setapak 这组，否则新店员工会被分到 Setapak 去）。新增两个「中央厨房」专属角色 `ckmanager`/`ckstaff`（锁定在 `outlet='ck'`，见下方权限说明）。

✅ **2026-09-19 更新**：邀请码判定逻辑已写进 `supabase-schema.sql`（第 3 部分，函数名 `handle_new_user`，绑在 `on_auth_user_created` 触发器上），需要去 Supabase SQL Editor 手动跑一遍脚本才会生效。前端 (`index.html` 的 `doAuthSignup`) 也加了「必填」校验，不填不给交。
🐛 **踩过的坑（关键）**：牛室这个正式 Supabase 项目里，**`auth.users` 早就绑了一个同名触发器 `on_auth_user_created`（函数 `handle_new_user`）**，是这次对话之前就已经存在的旧逻辑——它认的邀请码是 `bmr888` / `BHMGR888` / `BHSTAFF123` 这种跟本备忘完全对不上的词，而且**任何邀请码填错/填了不认识的词，它都默默给 staff，不会拒绝**。一开始我们另外新建了一个名字不同的触发器 `on_auth_user_created_invite`，结果实际生效的还是旧的那个（新的建立指令当时没跑到/没生效），导致填对邀请码也还是被分配成 staff。**最终修法：直接把 `handle_new_user` 这个既有函数的内容覆盖成正确逻辑，不再另外建新触发器**——如果你之后又发现邀请码不生效，第一件事就是去查 `auth.users` 上实际绑的是哪个触发器、对应哪个函数，不要假设一定是本文件里这份在跑：
```sql
select tgname, proname from pg_trigger t join pg_proc p on t.tgfoid=p.oid
where tgrelid='auth.users'::regclass and not t.tgisinternal;
```
✅ **免邀请码例外**：`yxchong3@gmail.com`（老板本人）注册时永远免填邀请码、直接给『老板』角色——前端 `codeExemptEmails` 和后台触发器 `v_code_exempt_emails` 两处都要同步改（目前只放了这一个邮箱，之后如需再加免邀请码账号，两处都要加）。
⚠️ 复制给明记时，明记要用**自己的邀请码**（配合明记自己独立的 Supabase 项目），触发器里的 `case` 对照表和免邀请码邮箱清单也要换成明记的一套，不要沿用牛室这组。
🐛 **踩过的坑（2026-09-19）**：`erp_is_admin()` 一开始写成 `language sql`，导致登录时 `select * from erp_users` 报 `42P17 infinite recursion detected in policy for relation "erp_users"`（500 错误，网页显示"白名单表尚未建立"）——原因是 sql 函数会被规划器内联展开，函数内部又查 `erp_users` 本身，被判定成策略里查自己触发死循环。改成 `language plpgsql` 后还没完全好，因为策略里**还直接裸写了一句 `not exists (select 1 from public.erp_users)`**（判断白名单是否为空），同样的坑犯了两次——同样会被内联触发递归。**最终把这句也包进一个 `erp_users_is_empty()` 的 plpgsql 函数**才彻底解决。**教训**：任何 RLS 策略的 `using`/`with check` 里，只要会查到「策略所在的那张表本身」，不管是直接写裸查询还是包在函数里，都必须用 `language plpgsql`（不能是 `language sql`），逐条检查，不要漏掉任何一处裸查询。

## 安全加固：erp_store 按分店隔离 + 薪资单独上锁（2026-09-19）
上线前审核发现 `erp_store`（存全部业务数据的表）原本是「只要登录就能读写全部 key」——任何员工账号理论上都能在浏览器开发者工具里直接调 API 读到所有分店、包括薪资在内的全部数据。已改成：
1. **按分店隔离**：`erpv2:<outletId>` 这种一般业务数据，只有**本人所属分店**或**老板/人事经理/区域副经理（全分店角色）**能读写。见 `supabase-schema.sql` 第 4 部分 `erp_can_read_key`/`erp_can_write_key`。
2. **薪资发放结果单独拆出来上锁**：`payrollRuns`（薪资发放的月度计算结果/finalize 状态）已经从主档案 JSON 里拆成独立的 key `erpv2:payroll:<outletId>`，**只有老板/人事经理能读，只有人事经理能写**（连老板都不给写，配合前端 `canRunPayroll` 锁死），区域副经理/店长/厨师长/员工一律不给读写。对应改动：
   - `index.html` 的 `save(oid)`：写入时会把 `payrollRuns` 从主档案里剥离，分开存到 `erpv2:payroll:<outletId>`。
   - `index.html` 的 `loadDB()`：读取时额外去读 `erpv2:payroll:<outletId>`，读不到（没权限/还没有）就给空对象 `{}`，不影响其它模块。
   - `supabase-schema.sql` 第 4 部分末尾有**一次性迁移 SQL**：把之前已经塞在主档案里的旧 `payrollRuns` 挪到新 key、再从主档案删掉（可重复执行，第二次没东西可挪会自动跳过）。
3. **权限配置 `erpv2:roleperms`**：任何登录用户可读（App 要用它判断能看哪些页面），只有老板/人事经理/区域副经理能写。
4. `erp_store` **没有开放 delete 权限**（App 从不删除这张表的行，直接不给更安全）。
5. ⚠️ **已知限制（还没堵上的洞）**：员工每人的底薪/津贴等字段目前还是存在 `erpv2:<outletId>` 主档案里的 `staff` 数组中，**没有**跟着搬到上面拆出来的 `payroll` key——因为店长现在按下面的新需求要能看到「本店每个人的薪资明细」，本店主档案本来就要对同店的店长/厨师长/员工开放读取（不然打卡/排班/库存等其它功能也用不了）。也就是说，技术熟悉的厨师长/员工理论上仍可能在浏览器里翻到同店其他同事的底薪字段——UI 上「只看自己」这层保护目前也还没做好（`currentEmpId()` 硬编码见下）。要彻底堵住，需要把员工的底薪/津贴等敏感字段也搬出主档案、单独配一把「只认本人」的锁，是比这次更大的一次改动，先记录着，未来排期再做。

## 岗位角色调整：新增「人事经理」+ 薪资可见范围四级制（2026-09-19）
业主要求把原本"老板/人事经理"合并的角色拆开，并重新定义薪资可见范围：
- **老板 `owner`**：权限不变（全权、全部分店），能看**全部分店每个人的薪资明细**，但**不能编辑/执行薪资发放**（`canRunPayroll:false`）——只能看，不能动。
- **人事经理 `hrmanager`**（新增角色）：**权限和老板完全一样**（同样的 `can` 模块清单、全分店、系统设置等），额外多一条：**唯一能编辑/执行薪资发放的角色**（`canRunPayroll:true`）。**不走邀请码注册**，由老板在「设置 → 白名单/用户管理」里直接把某个已注册账号的岗位改成「人事经理」即可（`erp_users.role='hrmanager'`，不需要 Supabase 触发器改动，因为白名单角色本来就能在 App 里手动改）。
- **区域副经理 `area`**：不变——薪资只看总数，但现在总数包含**全部分店合计 + 各分店细分小计**（原本只有一个笼统总数），需要把门店切到「全部分店 ALL」视图才看得到分店小计。
- **店长/店面经理 `manager`**（沿用原本 `manager` 角色）：从原本只能看自己薪资，升级成**能看本店每一位员工的薪资明细**（因为 `manager` 本身 `allBranch:false`、`curOutlet` 锁定在自己分店，所以"本店"这层隔离是天然的，不用额外写代码），但**不能编辑**薪资发放。
- **厨师长 `headchef` / 员工 `staff`**：不变，只能看自己的薪资（`salaryView:"self"`）——顺手把 `headchef` 补上了 `payroll` 这个模块权限（原本 `can` 列表漏了，导致厨师长的"自助查看自己薪资"功能其实进不去页面，算是顺便修的一个小 bug）。

**代码里的关键函数**（`index.html`）：
- `canSeeSalary()`：`salaryView==="full"` → 决定是否看得到 OpEx 页面的人工成本明细 + 是否走"全部个人明细"的渲染分支。
- `canRunPayroll()`（新增）：`ROLES[curRole].canRunPayroll===true` → 决定能不能进「薪资发放 Payroll Run」编辑页、能不能在「人事薪资 Payroll」页做新增/编辑/删除员工的操作。目前只有 `hrmanager` 为 `true`。
- `pageAllowed('payrun')`：原本是 `can('payroll')&&canSeeSalary()`（老板能进），改成 `can('payroll')&&canRunPayroll()`（只有人事经理能进）。
- `canW('payroll')`：额外加了 `&&canRunPayroll()`，堵住"虽然进不去 Payrun 编辑页，但还能从 Payroll 查看页的行内编辑/删除按钮改数据"这个漏洞。
- `pgPayroll()` 的 `salaryScope()` 四级：`full`(老板/人事经理，全分店个人明细) / `branch`(店长，本店个人明细) / `total`(区域副经理，全部+各店小计) / `self`(厨师长/员工，只看自己)。
- 全文件里原本一批写死的 `['owner','area']`（订单确认/央厨订货/应付账款重开等跟薪资无关的管理权限判断）**已经批量加上 `hrmanager`**，确保"人事经理权限和老板一样"这句话在薪资以外的模块也成立。

## 新增「中央经理/中央员工」两个角色，锁定在中央厨房分店（2026-09-19）
业主参考明记那边已经有的「中央经理/中央员工」角色截图，要求牛室也加两个对应角色，权限只限中央厨房(`outlet:'ck'`)：
- **中央经理 `ckmanager`**（邀请码 `tcymgr888`）：`can` = `["dash","proc","waste","ck","inv","stock","ap","opex","report","hr","attend","schedule","leave","payroll"]`。采购进销页里含订货单/进货单/退货补货/报废损耗（`proc`+`waste`），**不含跨店调拨**（没给 `transfer`）。`allBranch:false`，`hrScope`/`salaryView` 都是 `"branch"`（能看中央厨房员工的薪资明细，不能编辑），`approveLeave:true`。
- **中央员工 `ckstaff`**（邀请码 `tcystaff888`）：`can` = `["transfer","ck","inv","stock","hr","attend","schedule","leave","payroll"]`。**没有 `dash`（看不到利润大盘）**，采购进销页**只有跨店调拨**这一张卡（因为只给了 `transfer`，没给 `proc`/`waste`）。`hrScope`/`salaryView` 都是 `"self"`，只能看自己的薪资/考勤。
- 两个角色的 `outlet` 由后台触发器自动锁定成 `'ck'`（`handle_new_user()` 里 `v_role in ('ckmanager','ckstaff')` 时把 `v_outlet` 设成 `'ck'`），业主在「设置→白名单」手动加人时也要记得把「所属分店」选成「中央厨房」。
- 这两个角色权限清单是照着业主截图**近似还原**明记那边"中央经理/中央员工"角色的样子（明记是他们自己独立的一套代码，我没有直接权限去看，只能靠业主给的截图和文字描述反推）——如果实际用起来发现某个模块该给没给、或不该给却给了，随时可以让我再调整 `ckmanager`/`ckstaff` 的 `can` 数组。

⚠️ **复制给明记时**：这一整套角色/权限设计（`ROLES` 常量、`erp_is_admin`/`erp_can_read_key`/`erp_can_write_key` 里的角色白名单）是牛室按业主这次的具体要求定制的，明记如果组织架构不一样（比如没有"人事经理"这个岗位、或者薪资可见范围要求不同），要重新问业主、按明记实际情况调整，不要照抄。

⚠️ **发现但先没动的关联 bug**：`index.html` 里 `function currentEmpId(){return 1;}` 是**写死返回 1**——意味着「员工自助只看自己」这个筛选（考勤/请假/排班/薪资自助）目前不管谁登录都固定抓的是员工编号 1 的记录，不是真的登录者本人。这次只是把薪资**从数据库层面**锁给老板/区域副经理，没有连带修这个 `currentEmpId()`——因为要修好它，需要先建立「登录账号 ↔ 具体哪位员工」的对应关系（目前完全没有这个关联字段），是另一块工程量。**这意味着目前员工角色的"自助查看自己薪资/考勤"功能实质上是失效/认错人的，需要单独排期重做**（先把登录邮箱和员工档案关联起来，再重写 `currentEmpId()`）。
⚠️ 复制给明记时，`erp_can_read_key`/`erp_can_write_key` 里对 `payroll`/`roleperms` 的判断逻辑通用，不用改；但记得整套 RLS 都要在明记自己独立的 Supabase 项目里重新跑一遍。

### 换账号做同样的事——安全吗？
- **共享代码（GitHub 仓库）**：安全。别给不信任的人 **write** 权限（能改代码=能改上线 App）；给只读即可。
- **共享数据（Supabase）**：网页里已内嵌 publishable key（设计上可公开），**真正的保护是 Supabase RLS + App 登录 + 牛室/明记分库**。**牛室与明记必须两个独立 Supabase 项目**（已做到）。**绝不要**把 service_role 密钥写进 HTML（目前只放了 publishable key，是对的）。

## 开发/部署工作流（现有约定）
- 单文件 ERP，无构建步骤；改 `index.html` → 用 Playwright(`/opt/pw-browsers/chromium`, file://) 无头测试 → 每次改动**bump `const BUILD`**（右上角版本角标可核对已载入最新版）。
- 部署：`git push beefhouse bh-fix5:main`（失败按 2/4/8/16s 退避重试；remote 已迁移到 yxchong3/BeefHouse_ERP_1.0，GitHub Pages live）。
- 提交信息用中文、清楚描述改动。
- **拖动排序统一风格**：全系统用 ☰ 拖动手柄排序(触屏+鼠标)，不用一步步 ↑↓。通用工具 `makeSortable`/`wireSortables`/`SORT_HANDLERS`(render 与 openForm 后自动接线)。做任何「可排序列表」都用它：容器加 `data-sort="<类型>"`(+ 上下文 `data-*`)、子行加 `data-sortid` 与一个 `.draghandle`，并在 `SORT_HANDLERS` 注册该类型的落点回调(收到新顺序 ids → 重排数据 → save → 重绘)。已用于：进货单/月末盘点品项行(data-sort="grid")、职位/国籍管理(data-sort="list")。
- 复制到明记需一并带上的文件：`index.html` + `CLAUDE.md` + `order-data.js` + `sw.js` + `manifest.webmanifest` + `icon-192.png` + `icon-512.png`（以及 `supabase/` 下的推送函数与 SQL，如明记要用推送）。

## 新增「运营开销记录」逐笔日志（2026-09-22）
「采购进销」作业中心新增一张卡片 **🧾运营开销记录**（页面 key `opexlog`），跟既有的「运营开销录入(opexm)」是两回事：opexm 是每月一个总数的录入表，`opexlog` 是**逐笔**记录（发票级别），方便留存明细/日后核对。
- 字段：日期、类别(下拉)、Invoice No.、金额、备注。类别下拉 7 项，跟 `pgOpex()` 里原本就有的 OpEx 科目对应（`opexLogCats()` 函数）：营销与广告(marketing)、维修与保养(maintenance)、Wi-Fi(wifi)、垃圾清理(rubbish)、POS 月租(possaas)、会计费(accounting)、维修(repair)。
- 数据存 `d().opexLog`（新数组，按 `flatMonthTabs` 分月查看，同报废损耗/招待赠送的既有模式）。写入权限沿用 `opex` 模块权限(`PROC_SUB.opexlog='opex'`)，即能碰运营开销的角色（老板/人事经理/区域副经理/店长/中央经理）都能用。
- ✅ **2026-09-24 更新：自动同步，不需要按按钮**（`applyOpexLogSync(month)`）。每次新增/编辑/删除一笔「运营开销记录」，都会自动把当月 `d().opexLog` 的 7 类金额加总，静默覆盖填进 `curOpex(month)` 对应栏位（编辑时如果改了日期跨月，旧月份也会一并重新计算）。因为 `pgOpex()`（运营开销总览）和 `pgOpexM()`（运营开销录入）读写的是**同一个 `curOpex(month)` 对象**，两个页面本来就是同一份数据，自动同步一次两边都会反映。
  - 一开始做了个"🔗同步运营开销记录"手动按钮（需要点击+确认），业主后来要求**不要按钮、直接自动同步**，已经改掉——现在完全没有手动按钮，`saveOpexLog()`/`delOpexLog()` 内部直接调用 `applyOpexLogSync()`。
  - 只同步 `OPEXLOG_SYNC_KEYS` 这 7 项（marketing/maintenance/wifi/rubbish/possaas/accounting/repair）；**租金(rent/commission)和水电煤气(electricity/water/gas)完全不受影响**，业主明确要求这两组维持纯手动、不跟运营开销记录挂钩。
  - 月末已锁定的月份跳过自动同步（`applyOpexLogSync` 内部检查 `monthLocked()`，锁定月不再改动已归档数据）。
  - 两个页面仍保留「已同步/不一致」的提示条（不一致通常代表该月已锁定、或改动前的历史数据还没被自动同步覆盖过）。
  - ⚠️ **这只对之后的新增/编辑/删除生效**：功能上线前如果已经手动同步过的月份数据不受影响；没做"一次性把所有历史月份重新同步一遍"，避免不小心覆盖掉业主手动调整过的旧月份数字。
- ✅ **2026-09-24 三次更新：营销/维修/杂费这 7 项在「运营开销录入」和「运营开销」编辑弹窗里都改成锁住(disabled)，不能手动 key in 了**——业主明确要求"这7样不需要自己另外key in"，完全靠「运营开销记录」逐笔登记自动带过来。具体改动：
  - `pgOpexM()` 单月录入页：`rows.map` 判断 `OPEXLOG_SYNC_KEYS.includes(k)`，命中就加 🔗 角标、`disabled`、灰底显示；`saveOpexM()` 保存时也直接跳过这些 key，不会读取（就算被 disabled，直接用 JS 读 `.value` 理论上还是读得到，所以用 `.filter()` 白名单排除，双重保险）。
  - `openM('opex')` 那个更底层的原始编辑弹窗（`Object.entries(curOpex(...))` 逐一生成 input，`saveOpex()` 保存）**一开始漏掉了、没跟着锁**——这个弹窗本来是可以绕过 opexm 页面直接改任何 key 的旧入口，这次一并补上同样的 disabled + 排除逻辑，两个编辑入口现在行为一致。
  - 租金(rent/commission)、水电煤气(electricity/water/gas)这 5 项完全不受影响，两个编辑入口都还是正常可以手动改。
