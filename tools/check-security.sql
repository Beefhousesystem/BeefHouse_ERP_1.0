-- 牛室 ERP · 安全检查（只读，不会改任何东西；可以随时跑）
-- 用法：Supabase（牛室项目 cogxtzduusuzjumsdkxy）→ SQL Editor → 贴上 → Run。
-- 结果是一张表，每一行一项检查：「通过」那栏全部是 ✅ 就是安全的；有 ❌ 就截图给 Claude。
with
checks as (
  -- 1. 四张表都开了行级安全（RLS）
  select 1 as 序号, '四张表都开了行级安全' as 检查项,
         (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relname in ('erp_store','erp_users','erp_push_subs','erp_invite_codes') and c.relrowsecurity)::text as 实际,
         '4' as 应该是
  union all
  -- 2. erp_store 只有一条规则：按岗位/分店锁 key
  select 2, 'erp_store 只有「erp_store key-locked」这一条规则',
         coalesce((select string_agg(policyname, ' / ' order by policyname) from pg_policies where schemaname='public' and tablename='erp_store'),'（没有）'),
         'erp_store key-locked'
  union all
  -- 3. erp_users 规则是新版的 4 条
  select 3, 'erp_users 是新版的 4 条规则',
         (select count(*) from pg_policies where schemaname='public' and tablename='erp_users'
           and policyname in ('erp_users select self or admin','erp_users insert self via invite or admin','erp_users update admin only','erp_users delete admin only'))::text
         || ' / 共 ' || (select count(*) from pg_policies where schemaname='public' and tablename='erp_users')::text,
         '4 / 共 4'
  union all
  -- 4. 推送订阅表只给白名单
  select 4, '推送订阅表只给白名单',
         coalesce((select string_agg(policyname, ' / ' order by policyname) from pg_policies where schemaname='public' and tablename='erp_push_subs'),'（没有）'),
         'erp_push_subs whitelisted only'
  union all
  -- 5. 邀请码表：没登录/已登录的人都不能直接读
  select 5, '邀请码表网页读不到（anon / authenticated 都没有读取权）',
         (has_table_privilege('anon','public.erp_invite_codes','select') or has_table_privilege('authenticated','public.erp_invite_codes','select'))::text,
         'false'
  union all
  -- 6. 旧的注册触发器已经拿掉（auth.users 上不应该还有触发器）
  select 6, '旧的注册触发器已拿掉',
         coalesce((select string_agg(tgname, ' / ') from pg_trigger where tgrelid='auth.users'::regclass and not tgisinternal),'（没有）'),
         '（没有）'
  union all
  -- 7. 分店上锁 / 调拨申请把关的函数和触发器都在
  select 7, '上锁用的函数 + 调拨申请触发器都在',
         (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname in ('erp_key_ok','is_whitelisted','is_admin','erp_is_owner','erp_req_guard','invite_info'))::text
         || ' 个函数 + ' || (select count(*) from pg_trigger where tgname='erp_req_guard')::text || ' 个触发器',
         '6 个函数 + 1 个触发器'
  union all
  -- 8. 白名单里没有不认识的岗位代号（例如明记的 hrmgr / outletmgr）
  select 8, '白名单岗位代号都是牛室的',
         coalesce((select string_agg(distinct role, ' / ') from public.erp_users
           where role not in ('owner','hrmanager','area','manager','storemgr','headchef','staff','ckmanager','ckstaff')),'（没有不认识的）'),
         '（没有不认识的）'
  union all
  -- 9. 每个账号都有分店（空的会读不到数据）
  select 9, '每个账号都填了分店',
         (select count(*) from public.erp_users where outlet is null or outlet='')::text || ' 个没填',
         '0 个没填'
  union all
  -- 10. 创办人账号在，而且是启用中的执行董事
  select 10, '创办人账号是启用中的执行董事',
         coalesce((select role || ' / ' || case when active then '启用' else '停用' end from public.erp_users where lower(email)='yxchong3@gmail.com'),'（找不到）'),
         'owner / 启用'
  union all
  -- 11. 数据库函数都没有用 language sql 查自己（牛室踩过的无限递归坑）
  select 11, '上锁函数都是 plpgsql',
         (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
           where n.nspname='public' and p.proname in ('erp_key_ok','is_whitelisted','is_admin','erp_is_owner','erp_users_is_empty','erp_req_guard') and l.lanname<>'plpgsql')::text
         || ' 个不是',
         '0 个不是'
)
select 序号, 检查项, 实际, 应该是, case when 实际 = 应该是 then '✅' else '❌' end as 通过
from checks order by 序号;
