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
-- ⚠️ 这个函数必须是 language plpgsql（不能用 language sql）：sql 函数会被规划器内联展开，
-- 而它内部又查询 erp_users 本身，会被判定成「策略里查自己的表」触发
-- "infinite recursion detected in policy for relation erp_users"（错误代码 42P17）。
-- plpgsql 函数不会被内联，规划器把它当黑盒调用，才不会触发这个死循环检测。
create or replace function public.erp_is_admin()
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  return exists (
    select 1 from public.erp_users u
    where u.email = auth.jwt()->>'email'
      and u.role in ('owner','area')
      and u.active
  );
end;
$$;

-- 同样的道理：「白名单是否为空」这个判断也不能直接裸写在策略里（会被内联、一样触发递归），
-- 必须包进一个 plpgsql 函数。
create or replace function public.erp_users_is_empty()
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  return not exists (select 1 from public.erp_users);
end;
$$;

drop policy if exists "erp_users authed write" on public.erp_users;         -- 移除旧的「任何登录用户皆可写」策略
drop policy if exists "erp_users admin or bootstrap write" on public.erp_users;
create policy "erp_users admin or bootstrap write"
  on public.erp_users for all
  to authenticated
  using ( public.erp_is_admin() or public.erp_users_is_empty() )
  with check ( public.erp_is_admin() or public.erp_users_is_empty() );

-- ========== 第 3 部分：注册邀请码 → 自动分配角色 ==========
-- 目的：注册时前端会把「邀请码」打包成 invite_code 传给 Supabase Auth。
-- 这段触发器在新用户注册（auth.users 新增一行）时自动读取 invite_code，
-- 按下表分配角色写入 erp_users；邀请码不在名单内 → 直接拒绝注册（报错、不会建立账号）。
-- 例外 1：白名单 erp_users 还是空表时（系统首次启用），第一个注册的人
-- 不看邀请码，直接设为『老板』（配合前端的首次引导）。
-- 例外 2：yxchong3@gmail.com（老板本人）永远免邀请码，直接设为『老板』。
--
-- 邀请码对照表（如需改邀请码，改下面 case 里的字符串即可）：
--   tcymgmt888 → area     (区域副经理)
--   bfmgr888   → manager  (店面经理)
--   chef888    → headchef (厨师长)
--   bfstaff888 → staff    (员工)
--
-- ⚠️ 2026-09-19 发现：牛室这个正式项目里，`auth.users` 上早就绑了一个触发器
-- `on_auth_user_created`（对应函数 `handle_new_user`），跟这里写的完全是两套
-- 独立逻辑——而且它认的邀请码是 'bmr888'/'BHMGR888'/'BHSTAFF123' 这种跟本备忘
-- 完全对不上的旧词，任何对不上的邀请码它都默默给 staff（不会拒绝）。
-- 所以这里**直接复用 `handle_new_user` 这个既有的函数名**覆盖掉旧逻辑，
-- 不再另外建一个 `on_auth_user_created_invite` 新触发器——避免同一张表上
-- 挂两个触发器、两套邀请码规则并存导致以后又搞不清楚是谁在生效。
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := coalesce(new.raw_user_meta_data->>'invite_code','');
  v_role text;
  v_email text := lower(new.email);
  v_code_exempt_emails text[] := array['yxchong3@gmail.com']; -- 免邀请码白名单（如老板本人账号）
begin
  if v_email = any(v_code_exempt_emails) then
    v_role := 'owner';
  else
    v_role := case v_code
      when 'tcymgmt888' then 'area'
      when 'bfmgr888'   then 'manager'
      when 'chef888'    then 'headchef'
      when 'bfstaff888' then 'staff'
      else null
    end;

    if v_role is null then
      if public.erp_users_is_empty() then
        v_role := 'owner';  -- 白名单为空 → 首位注册者自动成为老板，不检查邀请码
      else
        raise exception '邀请码无效或未填写，请向管理员索取正确的邀请码后再注册';
      end if;
    end if;
  end if;

  insert into public.erp_users (email, name, role, outlet, active, created_at)
  values (lower(new.email), split_part(new.email,'@',1), v_role, 'b1', true, now())
  on conflict (email) do update set role = excluded.role, active = true;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ========== 第 4 部分：erp_store 按分店隔离 + 薪资单独上锁 ==========
-- 背景：erp_store 原本是「只要登录就能读写全部 key」，等于任何一个员工账号
-- 都能在浏览器里直接读到所有分店的全部业务数据。这里改成：
--   · 一般业务数据（erpv2:<outletId>）：只有本人所属分店 + 老板/区域副经理(全分店角色)能读写。
--   · erpv2:roleperms（权限配置）：任何登录用户可读，只有老板/区域副经理能写。
--   · erpv2:payroll:<outletId>（薪资，2026-09-19 起单独拆分出来）：只有老板/区域副经理能读写，
--     其余角色（含本店店长/厨师长/员工）一律不给，从数据库层面彻底挡住直接翻薪资源数据。
-- ⚠️ 同上面 erp_is_admin 的教训：这里查 erp_users 的函数不会造成递归（erp_store 和 erp_users
-- 是两张不同的表），但仍统一用 language plpgsql 写，保持风格一致、也更保险。
create or replace function public.erp_can_read_key(k text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_email text := auth.jwt()->>'email';
  v_role text;
  v_outlet text;
begin
  select role, outlet into v_role, v_outlet
  from public.erp_users
  where email = v_email and active;

  if v_role is null then
    return false; -- 未登录/不在白名单，一律不给
  end if;

  if k = 'erpv2:roleperms' then
    return true; -- 权限配置：任何已登录白名单用户都可读（App 要用它判断能看哪些页面）
  end if;

  if k like 'erpv2:payroll:%' then
    return v_role in ('owner','area'); -- 薪资：只有全权角色能读，员工/店长/厨师长一律不给
  end if;

  if v_role in ('owner','area') then
    return true; -- 全分店角色，其余业务数据都能看
  end if;

  return k = 'erpv2:' || v_outlet; -- 其他角色只能碰自己所属分店那一份
end;
$$;

create or replace function public.erp_can_write_key(k text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if k = 'erpv2:roleperms' then
    return public.erp_is_admin(); -- 权限配置只有老板/区域副经理能改
  end if;
  if k like 'erpv2:payroll:%' then
    return public.erp_is_admin(); -- 薪资写入同样只给老板/区域副经理
  end if;
  return public.erp_can_read_key(k); -- 其余业务数据：能读的分店范围内也能写(配合本店日常操作)
end;
$$;

drop policy if exists "erp_store authed full access" on public.erp_store;    -- 移除旧的「登录即全开」策略
drop policy if exists "erp_store select scoped" on public.erp_store;
drop policy if exists "erp_store insert scoped" on public.erp_store;
drop policy if exists "erp_store update scoped" on public.erp_store;
create policy "erp_store select scoped"
  on public.erp_store for select
  to authenticated
  using ( public.erp_can_read_key(key) );
create policy "erp_store insert scoped"
  on public.erp_store for insert
  to authenticated
  with check ( public.erp_can_write_key(key) );
create policy "erp_store update scoped"
  on public.erp_store for update
  to authenticated
  using ( public.erp_can_read_key(key) )
  with check ( public.erp_can_write_key(key) );
-- 没有 delete 策略：App 从不删 erp_store 的行，所以直接不开放删除权限（更安全的默认值）。

-- 一次性迁移：把已经存在、还塞在主档案里的 payrollRuns 挪到新的受保护 key，
-- 再从主档案里删掉。可重复执行（第二次跑不会有 payrollRuns 可挪，自动跳过）。
insert into public.erp_store (key, value, updated_at)
select 'erpv2:payroll:' || substring(key from 7),
       coalesce(value->'payrollRuns', '{}'::jsonb),
       now()
from public.erp_store
where key like 'erpv2:%'
  and key <> 'erpv2:roleperms'
  and key not like 'erpv2:payroll:%'
  and value ? 'payrollRuns'
on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;

update public.erp_store
set value = value - 'payrollRuns'
where key like 'erpv2:%'
  and key <> 'erpv2:roleperms'
  and key not like 'erpv2:payroll:%'
  and value ? 'payrollRuns';

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
