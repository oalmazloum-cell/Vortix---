-- ============================================================
-- فورتكس للمحاسبة — قاعدة بيانات المزامنة على Supabase
-- انسخ هذا الملف كاملاً في: Supabase > SQL Editor > New query > Run
-- ============================================================

create table if not exists public.vortex_records (
  shop_id    uuid   not null references auth.users(id) on delete cascade,
  tbl        text   not null,
  row_id     text   not null,
  data       jsonb  not null,
  updated_at bigint not null default 0,
  synced_at  timestamptz not null default clock_timestamp(),
  primary key (shop_id, tbl, row_id)
);

create index if not exists vortex_records_pull_idx on public.vortex_records (shop_id, synced_at);

-- يحدّث مؤشر المزامنة عند كل رفع (هو ما تعتمد عليه الأجهزة للسحب).
create or replace function public.vortex_touch() returns trigger
language plpgsql as $$
begin
  new.synced_at := clock_timestamp();
  return new;
end $$;

drop trigger if exists vortex_touch on public.vortex_records;
create trigger vortex_touch before insert or update on public.vortex_records
for each row execute function public.vortex_touch();

-- سجل العمليات لا يُعدَّل ولا يُحذف حتى على السحابة.
create or replace function public.vortex_protect_audit() returns trigger
language plpgsql as $$
begin
  if old.tbl = 'audit_log' then
    if tg_op = 'DELETE' then
      raise exception 'audit log is append-only';
    end if;
    return old; -- تجاهل أي محاولة تعديل
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists vortex_protect_audit on public.vortex_records;
create trigger vortex_protect_audit before update or delete on public.vortex_records
for each row execute function public.vortex_protect_audit();

-- أمان الصفوف: كل محل يرى بياناته فقط.
alter table public.vortex_records enable row level security;

drop policy if exists "shop owns rows" on public.vortex_records;
create policy "shop owns rows" on public.vortex_records
  for all using (auth.uid() = shop_id) with check (auth.uid() = shop_id);
