-- ============================================================
-- 牛室 ERP · 换成明记版之后的数据库规则（2026-11-27，BUILD 1127a 起）
-- 用法：Supabase（牛室项目 cogxtzduusuzjumsdkxy）→ SQL Editor → New query → 粘贴全部 → Run。
-- 可重复运行。只动权限规则、注册方式和邀请码表；**不改、不删任何业务数据**（erp_store 里的内容一行都不碰）。
-- ⚠️ 只能在牛室的项目跑，绝不能在明记的项目（kmcdokwiyetlmsrdlgqw）跑。
--
-- 做了什么：
--  1. 拿掉旧的注册触发器 on_auth_user_created / handle_new_user（旧邀请码写在里面）。
--     改成明记的方式：管理员先在「设置 → 白名单」加邮箱，对方注册就能进；也可以用邀请码自己注册。
--  2. 新建邀请码私有表 erp_invite_codes（网页读不到整张表），第一次跑会自动生成一组新码，
--     结果在最下面那个查询里显示。码不要存回 GitHub（仓库是公开的）。
--  3. 白名单 erp_users：自己能读自己；执行董事/人事经理/运营经理能管理。
--     系统最高权限账号（yxchong3@gmail.com）只有本人能改；执行董事账号只有执行董事能动。
--  4. erp_store 每个 key 按岗位/分店上锁（照明记的规则，岗位代号用牛室的）：
--       erpv2:b1、erpv2:ck …（分店整包）    执行董事 owner / 人事经理 hrmanager：全部
--                                           运营经理 area：所有分店，不含中央厨房 ck
--                                           店面经理 manager / 店长 storemgr / 厨师长 headchef / 员工 staff：只有自己那间
--                                           中央经理 ckmanager / 中央员工 ckstaff：只有 ck
--       erpv2:payroll:*（薪资记录）         owner/hrmanager 读写；店面经理只读本店；其他人读不到
--       erpv2:orders、erpv2:ckorder         所有白名单账号可读写
--       erpv2:roleperms                     所有人可读；owner/hrmanager/area 能写
--       erpv2:req:<发起店>:<被申请店>:<编号>  跨店调拨申请：双方店能读写；谁能批准由触发器 erp_req_guard 把关
--       其他 key（例如 erpv2:payroll:bak:*）只有 owner/hrmanager
--  5. 推送订阅表 erp_push_subs、收据储存桶 receipts：只有白名单里启用中的账号能用。
-- 所有函数都用 language plpgsql（牛室踩过的坑：language sql 会在规则里无限递归，报 42P17）。
-- ============================================================

-- ========== 0. 跑之前先看一眼（不改东西）：岗位/分店空白的账号会读不到数据，先在白名单补好 ==========
-- select email, role, outlet, active from public.erp_users order by role, email;

-- ========== 1. 拿掉旧的注册触发器（旧邀请码在里面） ==========
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists on_auth_user_created_invite on auth.users;
drop function if exists public.handle_new_user() cascade;

-- ========== 2. 邀请码私有表 + 查询函数 ==========
create table if not exists public.erp_invite_codes (
  code   text primary key,          -- 一律小写
  role   text not null,
  outlet text not null
);
alter table public.erp_invite_codes enable row level security;
revoke all on public.erp_invite_codes from anon, authenticated;

create or replace function public.invite_role(code text)
returns text language plpgsql stable security definer set search_path = public as $$
declare r text;
begin
  select c.role into r from public.erp_invite_codes c where c.code = lower(coalesce(invite_role.code,''));
  return r;
end; $$;

create or replace function public.invite_outlet(code text)
returns text language plpgsql stable security definer set search_path = public as $$
declare o text;
begin
  select c.outlet into o from public.erp_invite_codes c where c.code = lower(coalesce(invite_outlet.code,''));
  return o;
end; $$;

create or replace function public.invite_info(code text)
returns json language plpgsql stable security definer set search_path = public as $$
declare r json;
begin
  select json_build_object('role', c.role, 'outlet', c.outlet) into r
    from public.erp_invite_codes c where c.code = lower(coalesce(invite_info.code,''));
  return r;
end; $$;
grant execute on function public.invite_info(text) to anon, authenticated;

-- 第一次跑（表是空的）才生成：每个岗位一个 10 位随机码。以后要换码：delete from public.erp_invite_codes; 再跑一次这份。
-- 人事经理、执行董事不发邀请码：由执行董事在「设置 → 白名单」直接加。
insert into public.erp_invite_codes(code, role, outlet)
select substr(md5(random()::text || clock_timestamp()::text || x.role), 1, 10), x.role, x.outlet
  from (values ('area','all'), ('manager','b1'), ('storemgr','b1'), ('headchef','b1'), ('staff','b1'),
               ('ckmanager','ck'), ('ckstaff','ck')) as x(role, outlet)
 where not exists (select 1 from public.erp_invite_codes);

-- ========== 3. 「现在登录的是谁」 ==========
create or replace function public.my_email()
returns text language plpgsql stable as $$
begin
  return lower(coalesce(auth.jwt()->>'email',''));
end; $$;

create or replace function public.is_whitelisted()
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return exists(select 1 from public.erp_users where lower(email) = public.my_email() and active = true);
end; $$;

create or replace function public.is_admin()
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return exists(select 1 from public.erp_users
                 where lower(email) = public.my_email() and active = true and role in ('owner','hrmanager','area'));
end; $$;

create or replace function public.erp_is_owner()
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return exists(select 1 from public.erp_users where lower(email) = public.my_email() and active = true and role = 'owner');
end; $$;

create or replace function public.erp_users_is_empty()
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  return not exists(select 1 from public.erp_users);
end; $$;

-- ========== 4. 白名单 erp_users 的规则（先清掉表上所有旧规则，避免旧的宽松规则还留着） ==========
alter table public.erp_users enable row level security;
do $$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'erp_users' loop
    execute format('drop policy if exists %I on public.erp_users', p.policyname);
  end loop;
end $$;

create policy "erp_users select self or admin"
  on public.erp_users for select to authenticated
  using (public.is_admin() or lower(email) = public.my_email());

-- 新增：管理员加人 / 第一位注册者变执行董事 / 创办人邮箱 / 凭邀请码自己加
create policy "erp_users insert self via invite or admin"
  on public.erp_users for insert to authenticated
  with check (
    (public.is_admin()
      and (role <> 'owner' or public.erp_is_owner())
      and (lower(email) <> 'yxchong3@gmail.com' or public.my_email() = 'yxchong3@gmail.com'))
    or (
      lower(email) = public.my_email()
      and (
        (role = 'owner' and public.erp_users_is_empty())
        or (role = 'owner' and lower(email) = 'yxchong3@gmail.com')
        or (role = public.invite_role(auth.jwt()->'user_metadata'->>'invite_code')
            and outlet = public.invite_outlet(auth.jwt()->'user_metadata'->>'invite_code'))
      )
    )
  );

-- 改 / 删：管理员才能；执行董事账号只有执行董事能动；创办人账号只有本人能动
create policy "erp_users update admin only"
  on public.erp_users for update to authenticated
  using (public.is_admin()
         and (role <> 'owner' or public.erp_is_owner())
         and (lower(email) <> 'yxchong3@gmail.com' or public.my_email() = 'yxchong3@gmail.com'))
  with check (public.is_admin()
         and (role <> 'owner' or public.erp_is_owner())
         and (lower(email) <> 'yxchong3@gmail.com' or public.my_email() = 'yxchong3@gmail.com'));

create policy "erp_users delete admin only"
  on public.erp_users for delete to authenticated
  using (public.is_admin()
         and (role <> 'owner' or public.erp_is_owner())
         and lower(email) <> 'yxchong3@gmail.com');

-- ========== 5. erp_store：每个 key 按岗位/分店上锁 ==========
create or replace function public.erp_key_ok(k text, writing boolean)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  r   text;
  o   text;
  eo  text;   -- 这个人所属的店（中央角色固定是 ck）
  src text;
  dst text;
begin
  if k is null then return false; end if;
  select u.role, u.outlet into r, o from public.erp_users u
   where lower(u.email) = public.my_email() and u.active = true;
  if r is null then return false; end if;
  if r in ('owner','hrmanager') then return true; end if;
  eo := case when r in ('ckmanager','ckstaff') then 'ck' else o end;

  if k like 'erpv2:payroll:%' then
    if writing then return false; end if;
    return r = 'manager' and k = 'erpv2:payroll:' || o;   -- 备份 key（erpv2:payroll:bak:…）不会等于这个
  end if;

  if k in ('erpv2:orders','erpv2:ckorder') then return true; end if;

  if k = 'erpv2:roleperms' then return (not writing) or r = 'area'; end if;

  if k ~ '^erpv2:(b[0-9]+|ck)$' then
    if r = 'area' then return k <> 'erpv2:ck'; end if;
    return eo is not null and k = 'erpv2:' || eo;
  end if;

  if k ~ '^erpv2:req:[a-z0-9]+:[a-z0-9]+:[A-Za-z0-9_-]+$' then
    if r = 'area' then return true; end if;
    src := split_part(k, ':', 3);
    dst := split_part(k, ':', 4);
    return eo is not null and (src = eo or dst = eo);
  end if;

  return false;
end; $$;

-- 跨店调拨申请的把关：新申请只能由发起店建立且是待批准；只有被申请店能批准/拒绝；处理完不能再改
create or replace function public.erp_req_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  k text; r text; o text; eo text; req text; cnt text; olds text; news text;
begin
  k := case when tg_op = 'DELETE' then old.key else new.key end;
  if k is null or k not like 'erpv2:req:%' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  select u.role, u.outlet into r, o from public.erp_users u
   where lower(u.email) = public.my_email() and u.active = true;
  if r is null then raise exception '不在白名单'; end if;
  if r in ('owner','hrmanager','area') then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  eo  := case when r in ('ckmanager','ckstaff') then 'ck' else o end;
  req := split_part(k, ':', 3);
  cnt := split_part(k, ':', 4);
  if tg_op = 'INSERT' then
    if exists(select 1 from public.erp_store s where s.key = new.key) then return new; end if;
    if eo is distinct from req then raise exception '只有发起申请的店面才能新增调拨申请'; end if;
    if coalesce(new.value->>'status','') <> 'pending' then raise exception '新的调拨申请必须是待批准状态'; end if;
    return new;
  elsif tg_op = 'UPDATE' then
    olds := coalesce(old.value->>'status','');
    news := coalesce(new.value->>'status','');
    if olds = 'pending' and news in ('approved','rejected') then
      if eo is distinct from cnt then raise exception '只有被申请的店面才能批准或拒绝'; end if;
    elsif olds = 'pending' and news = 'pending' then
      if eo is distinct from req then raise exception '只有发起申请的店面才能修改申请'; end if;
    else
      raise exception '已处理的调拨申请不能再修改';
    end if;
    return new;
  else
    if eo is distinct from req or coalesce(old.value->>'status','') not in ('pending','rejected') then
      raise exception '只有发起店能撤回待批准/移除被拒绝的申请';
    end if;
    return old;
  end if;
end; $$;
drop trigger if exists erp_req_guard on public.erp_store;
create trigger erp_req_guard before insert or update or delete on public.erp_store
  for each row execute function public.erp_req_guard();

alter table public.erp_store enable row level security;
do $$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'erp_store' loop
    execute format('drop policy if exists %I on public.erp_store', p.policyname);
  end loop;
end $$;
create policy "erp_store key-locked"
  on public.erp_store for all to authenticated
  using (public.is_whitelisted() and public.erp_key_ok(key, false))
  with check (public.is_whitelisted() and public.erp_key_ok(key, true));

-- 旧规则用的函数（erp_can_read_key / erp_can_write_key / erp_is_admin）现在没人用了，留着不影响；不删是为了避免还有别的地方引用它们而报错。

-- ========== 6. 推送订阅表、收据储存桶：只给白名单 ==========
do $$
declare p record;
begin
  if to_regclass('public.erp_push_subs') is not null then
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'erp_push_subs' loop
      execute format('drop policy if exists %I on public.erp_push_subs', p.policyname);
    end loop;
    execute $p$create policy "erp_push_subs whitelisted only" on public.erp_push_subs for all to authenticated
      using (public.is_whitelisted()) with check (public.is_whitelisted())$p$;
  end if;
end $$;

do $$
begin
  if exists(select 1 from storage.buckets where id = 'receipts') then
    execute 'drop policy if exists "receipts authed all" on storage.objects';
    execute 'drop policy if exists "receipts whitelisted only" on storage.objects';
    execute $p$create policy "receipts whitelisted only" on storage.objects for all to authenticated
      using (bucket_id = 'receipts' and public.is_whitelisted())
      with check (bucket_id = 'receipts' and public.is_whitelisted())$p$;
  end if;
end $$;

-- ========== 7. 结果：新的邀请码（只在这里看，不要存进 GitHub） ==========
select role as "岗位", outlet as "分店", code as "邀请码" from public.erp_invite_codes order by role;
