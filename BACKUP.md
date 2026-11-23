# 牛室 ERP · 自动备份说明

每天自动把 Supabase 里的 **`erp_store`（全部业务/薪资/会计数据）** 和 **`erp_users`（白名单）** 导出，**加密**后存成 GitHub 的 Artifact，保留 **90 天**。
工作流：`.github/workflows/supabase-backup.yml`　脚本：`scripts/backup-supabase.sh`

> ⚠️ 本仓库是公开的，所以备份一定是加密的；**密钥和口令只放 GitHub Secrets，绝不写进仓库或贴进聊天**。

## 一次性设置（只做一遍）
1. Supabase → 牛室项目 → **Project Settings → API Keys** → 复制 **secret key**（`sb_secret_…`；旧版叫 `service_role`）。
2. GitHub → 本仓库 **Settings → Secrets and variables → Actions → New repository secret**，加两个：
   - `SUPABASE_SERVICE_KEY` = 上面复制的 secret key
   - `BACKUP_PASSPHRASE` = 你自己定的一串长口令（建议 20 位以上）。**丢了就解不开备份**，请同时存进密码管理器。
3. GitHub → **Actions → Supabase backup → Run workflow** 手动跑一次，等绿色勾。
4. 点进这次运行，页面最下面 **Artifacts** 里下载 `supabase-backup-…`，按下面「怎么打开备份」试一次解密，确认能用。

## 怎么打开备份
下载后解压得到 `beefhouse-日期.json.gpg`，在电脑终端执行（会问口令）：
```bash
gpg -d beefhouse-20261123-202300.json.gpg > backup.json
```
`backup.json` 里是 `{ exported_at, tables: { erp_store:[…], erp_users:[…] } }`。

## 怎么恢复（出事时）
1. 先别慌、别乱改；把最新那份备份解密出来。
2. 把 `tables.erp_store` 的每一行（`key` + `value`）写回 Supabase 的 `erp_store` 表，`erp_users` 同理。
3. 恢复动作会覆盖现在的数据，**请让我（Claude）帮你写恢复脚本并先小范围试**，不要自己随手贴 SQL。

## 要注意
- **这不包含**：Storage 里的文件（收据图片等）、登录账号的密码（`auth.users`）。数据库结构在仓库的 `supabase-schema.sql`。
- Artifact 只留 90 天：建议**每个月下载一份最新的**，放到你自己的 Google Drive / 硬盘。
- 如果某天备份那次运行变红，GitHub 会寄邮件。常见原因：密钥换了没更新 Secrets、Supabase 暂停了。
- 备份用的是 Supabase 的 secret 密钥，权限很大。万一怀疑外泄，去 Supabase 重新产生一把，再更新 GitHub Secrets。
