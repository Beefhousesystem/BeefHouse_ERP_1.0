-- ============================================================
-- 牛室炙烤牛排 · Supabase 建表脚本
-- 用法：Supabase 控制台 → SQL Editor → New query → 粘贴全部 → Run
-- 已经跑过第 1 版的，只需再跑「第 2 部分」即可（重复运行安全）。
-- 2026-09 更新：erp_users 写入策略收紧为「仅老板/区域副经理」，重新跑一次本脚本即可生效。
-- ============================================================

-- ========== 第 1 部分：业务数据表 erp_store ==========
create table if not exists public.erp_store (
  key         text primary key,
  value       jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
alter table public.erp_store enable row level security;

-- 收紧：仅「已登录」用户可读写业务数据（未登录看不到任何东西）
-- ⚠️ 已知限制：erp_store 是「整店一行 jsonb」的结构（各模块含薪资都在同一份 value 里），
-- RLS 目前只能按「登录与否」把关，做不到「按角色/分店」的行级隔离——
-- 分角色的数据可见性（如员工看不到薪资）目前完全靠 App 前端判断。若要在数据库层也拦住，
-- 需要把薪资等敏感数据拆到独立的表/字段再配 RLS，是较大改动，先记录在此，未来需要再做。
drop policy if exists "erp_store anon full access" on public.erp_store;      -- 移除旧的匿名策略
drop policy if exists "erp_store authed full access" on public.erp_store;
create policy "erp_store authed full access"
  on public.erp_store for all
  to authenticated
  using (true) with check (true);

-- ========== 第 2 部分：白名单 / 用户目录 erp_users ==========
-- 只有列在此表且 active=true 的邮箱能进入系统；岗位/分店由管理员分配。
create table if not exists public.erp_users (
  email       text primary key,
  name        text,
  role        text not null default 'staff',   -- owner / area / manager / headchef / staff
  outlet      text default 'b1',               -- 所属分店 id：ck / b1
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table public.erp_users enable row level security;

-- 已登录用户可读白名单（读取角色不敏感，App 要靠它判断当前人是谁）。
drop policy if exists "erp_users authed read" on public.erp_users;
create policy "erp_users authed read"
  on public.erp_users for select
  to authenticated using (true);

-- 写入收紧：只有「老板/区域副经理」才能改白名单（新增/停用员工、改角色）。
-- 例外：首次使用、白名单还是空表时放行——让第一个注册的人能被设为老板（配合 App 的自动引导）。
create or replace function public.erp_is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.erp_users u
    where u.email = auth.jwt()->>'email'
      and u.role in ('owner','area')
      and u.active
  );
$$;

drop policy if exists "erp_users authed write" on public.erp_users;         -- 移除旧的「任何登录用户皆可写」策略
drop policy if exists "erp_users admin or bootstrap write" on public.erp_users;
create policy "erp_users admin or bootstrap write"
  on public.erp_users for all
  to authenticated
  using ( public.erp_is_admin() or not exists (select 1 from public.erp_users) )
  with check ( public.erp_is_admin() or not exists (select 1 from public.erp_users) );

-- ========== 第 3 部分：注册邀请码 → 自动分配角色 ==========
-- 目的：注册时前端会把「邀请码」打包成 invite_code 传给 Supabase Auth。
-- 这段触发器在新用户注册（auth.users 新增一行）时自动读取 invite_code，
-- 按下表分配角色写入 erp_users；邀请码不在名单内 → 直接拒绝注册（报错、不会建立账号）。
-- 唯一例外：白名单 erp_users 还是空表时（系统首次启用），第一个注册的人
-- 不看邀请码，直接设为『老板』（配合前端的首次引导）。
--
-- 邀请码对照表（如需改邀请码，改下面 case 里的字符串即可）：
--   tcymgmt888 → area     (区域副经理)
--   bfmgr888   → manager  (店面经理)
--   chef888    → headchef (厨师长)
--   bfstaff888 → staff    (员工)
create or replace function public.handle_new_user_invite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := coalesce(new.raw_user_meta_data->>'invite_code','');
  v_role text;
begin
  v_role := case v_code
    when 'tcymgmt888' then 'area'
    when 'bfmgr888'   then 'manager'
    when 'chef888'    then 'headchef'
    when 'bfstaff888' then 'staff'
    else null
  end;

  if v_role is null then
    if not exists (select 1 from public.erp_users) then
      v_role := 'owner';  -- 白名单为空 → 首位注册者自动成为老板，不检查邀请码
    else
      raise exception '邀请码无效或未填写，请向管理员索取正确的邀请码后再注册';
    end if;
  end if;

  insert into public.erp_users (email, name, role, outlet, active)
  values (lower(new.email), split_part(new.email,'@',1), v_role, 'b1', true)
  on conflict (email) do update set role = excluded.role, active = true;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_invite on auth.users;
create trigger on_auth_user_created_invite
  after insert on auth.users
  for each row execute function public.handle_new_user_invite();

-- ============================================================
-- 首次使用：
-- 1) 上面跑完后，去 Authentication → Providers → Email 确认已开启；
--    并在 Authentication → Providers → Email 里把「Confirm email」关掉，
--    这样员工注册后可立即登录（不用等确认邮件）。
-- 2) 打开网站 → 用你的邮箱点「注册账号」。因为白名单此刻为空，
--    第一位注册者会被自动设为『老板』。之后就能在
--    设置 → 白名单/用户管理 里添加其他员工并分配岗位/分店。
--    （也可以不靠自动引导，直接在这里手动插入第一位老板：）
-- insert into public.erp_users (email,name,role,outlet,active)
--   values ('you@example.com','老板','owner','b1',true)
--   on conflict (email) do update set role=excluded.role, active=true;
-- ============================================================
