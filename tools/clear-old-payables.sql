-- 牛室 ERP · 清掉「旧版应付账款名单」（2026-11-27，业主批准：旧数据完全清除）
-- 为什么：新版「应付账款」页面只读 订货单 Invoice + 进货单，不再读这份旧名单；
--         「需要注意」的到期提醒却还在读它，所以你在应付账款页面删了订单，提醒还是在。
-- 做了什么：① 先把旧名单原样备份到 erp_store 的 erpv2:payables-bak:<店>（只有执行董事/人事经理读得到，网页不读它）
--           ② 把每间店（b1、ck…）的旧名单清成空。订货单、进货单、Invoice、其他数据一行都不动。
-- 可以重复跑（第二次没东西可清，会显示 0 行）。只在牛室项目跑，不要在明记的项目跑。
-- 看结果：下面会列出「清掉了哪间店的几条」。
with old as (
  select key, value->'payables' as p
    from public.erp_store
   where key ~ '^erpv2:(b[0-9]+|ck)$'
     and jsonb_typeof(value->'payables') = 'array'
     and jsonb_array_length(value->'payables') > 0
),
bak as (
  insert into public.erp_store(key, value)
  select 'erpv2:payables-bak:' || substr(key, 7),
         jsonb_build_object('at', now(), 'payables', p)
    from old
  on conflict (key) do update set value = excluded.value, updated_at = now()
  returning key
),
upd as (
  update public.erp_store s
     set value = jsonb_set(s.value, '{payables}', '[]'::jsonb), updated_at = now()
    from old
   where s.key = old.key
  returning s.key
)
select old.key as "店", jsonb_array_length(old.p) as "清掉的旧应付条数",
       (select count(*) from bak) as "已备份", (select count(*) from upd) as "已清空"
  from old;
