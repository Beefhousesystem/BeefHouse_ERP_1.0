# 📲 手机后台推送 + 安装成 App（设置指南）

目标：**关掉网页/App 后**，老板与区域副经理的手机也能收到「新订单」通知 + 提示音。

---

## A. 把网站装成 App（免费，马上可用）

打开 `https://yxchong3.github.io/BeefHouse_ERP_1.0/`：

- **安卓 (Chrome)**：右上菜单 (⋮) → 「安装应用 / 添加到主屏幕」。或点网站右上角的 **📲** 按钮。
- **iPhone (Safari)**：下方「分享」→「加入主画面 / Add to Home Screen」。

装好后从主画面打开，就像一个 App（有自己的图标、全屏）。

> ⚠️ iPhone 必须**先加到主画面**，之后才能收到后台推送（需 iOS 16.4 以上）。安卓不强制，但装成 App 更稳。

---

## B. 开启后台推送（一次性设置，需在 Supabase 操作）

已内建推送前端；只差在 Supabase 部署一个发送函数。步骤：

### 1) 建订阅表
Supabase → **SQL Editor** → 新建查询 → 粘贴仓库里的 `push-schema.sql` 全部内容 → **Run**。

### 2) 部署发送函数
Supabase → **Edge Functions** → **Create a function**：
- 名称填：`send-order-push`（必须一模一样）
- 把仓库 `supabase/functions/send-order-push/index.ts` 的内容整段贴进去
- **部署时关闭 JWT 验证**：函数设置里把「Verify JWT」关掉（Off）。
  （用 CLI 的话：`supabase functions deploy send-order-push --no-verify-jwt`）

### 3) 设置密钥（VAPID）
Supabase → **Project Settings → Edge Functions → Secrets**（或 Functions 页的 Secrets），新增三个：

| 名称 | 值 |
|---|---|
| `VAPID_PUBLIC`  | `<网页里的 VAPID_PUBLIC，见 index.html>` |
| `VAPID_PRIVATE` | `<私钥只放 Supabase Secrets，绝不写进仓库>` |
| `VAPID_SUBJECT` | `mailto:你的邮箱@example.com` |

> `SUPABASE_URL` 与 `SUPABASE_SERVICE_ROLE_KEY` 是系统自带的，不用你填。

### 4) 完成
- 老板/区域副经理在手机上打开 App → 点 **🔔** 面板里的「开启通知」允许权限（会自动订阅）。
- 之后任何人下单，手机**即使关掉 App** 也会收到通知 + 系统提示音。

---

## C. 想上架成真正的 App Store / Play Store 应用？

以上是「网页 App（PWA）」，免费、够用。若要正式上架应用商店：
- 需要用 **Capacitor / TWA** 把网站打包成原生 App，注册开发者账号（Google Play 一次性约 USD 25，Apple 每年约 USD 99），并走商店审核。
- 这是另一个较大的工程，需要时我可以帮你规划。

---

_内建的 VAPID 公钥已写进网页；上面的私钥只放在 Supabase 密钥里，不会出现在前端。_
