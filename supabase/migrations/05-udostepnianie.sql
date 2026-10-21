-- =====================================================================
-- VinyLog · migracja 05: udostępnianie półek innym osobom z VinyLog
-- Uruchom w Supabase: SQL Editor → New query → wklej → Run
--
-- Właścicielka wybiera osobę (po e-mailu konta) i listy: Moja kolekcja, Po wypłacie.
-- Osoba widzi te listy tylko do oglądania. Zmieniać płyty może dalej tylko właścicielka
-- (polityki update/delete z migracji 01 zostają bez zmian).
--
-- UWAGA: aplikacja musi pobierać własne płyty z filtrem user_id (wersja z 21.10.2026),
-- inaczej po tej migracji udostępnione płyty innych wpadłyby do własnej kolekcji.
-- =====================================================================

begin;

-- 1. Kto komu co udostępnia.
create table if not exists public.shares (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  viewer_id  uuid not null references auth.users (id) on delete cascade,
  owned      boolean not null default true,    -- Moja kolekcja
  wanted     boolean not null default false,   -- Po wypłacie
  created_at timestamptz not null default now(),
  unique (owner_id, viewer_id),
  check (owner_id <> viewer_id),
  check (owned or wanted)
);
create index if not exists shares_viewer_idx on public.shares (viewer_id);

alter table public.shares enable row level security;
-- Uprawnienia do tabeli (projekt nie nadaje ich automatycznie; bez tego zapytania o płyty kończą się błędem).
grant select, insert, update, delete on table public.shares to authenticated;

drop policy if exists "shares_owner_all" on public.shares;
drop policy if exists "shares_viewer_select" on public.shares;
drop policy if exists "shares_viewer_delete" on public.shares;

-- Właścicielka zarządza swoimi udostępnieniami.
create policy "shares_owner_all" on public.shares
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);

-- Osoba, której udostępniono, widzi to udostępnienie i może z niego zrezygnować.
create policy "shares_viewer_select" on public.shares
  for select to authenticated
  using ((select auth.uid()) = viewer_id);
create policy "shares_viewer_delete" on public.shares
  for delete to authenticated
  using ((select auth.uid()) = viewer_id);

-- 2. Płyty: dodatkowo do oglądania dla osób z udostępnieniem, tylko z wybranych list.
drop policy if exists "albums_select_shared" on public.albums;
create policy "albums_select_shared" on public.albums
  for select to authenticated
  using (exists (
    select 1 from public.shares s
    where s.owner_id = albums.user_id
      and s.viewer_id = (select auth.uid())
      and ((albums.status = 'owned' and s.owned) or (albums.status = 'wanted' and s.wanted))
  ));

-- 3. Udostępnienie po e-mailu. Adresy kont są w auth.users, do których przeglądarka
--    nie ma dostępu, więc szukamy ich w funkcji z uprawnieniami serwera.
--    Wynik: 'ok', 'removed' (obie listy odznaczone), 'not_found', 'self'.
create or replace function public.share_shelf(p_email text, p_owned boolean, p_wanted boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  them uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select id into them from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  if them is null then return 'not_found'; end if;
  if them = me then return 'self'; end if;
  if not coalesce(p_owned, false) and not coalesce(p_wanted, false) then
    delete from public.shares where owner_id = me and viewer_id = them;
    return 'removed';
  end if;
  insert into public.shares (owner_id, viewer_id, owned, wanted)
  values (me, them, coalesce(p_owned, false), coalesce(p_wanted, false))
  on conflict (owner_id, viewer_id) do update set owned = excluded.owned, wanted = excluded.wanted;
  return 'ok';
end $$;

-- 4. Listy z e-mailami (e-mail jest jedyną „nazwą” osoby w VinyLog).
create or replace function public.my_shares()
returns table (viewer_id uuid, email text, owned boolean, wanted boolean)
language sql stable security definer set search_path = ''
as $$
  select s.viewer_id, u.email::text, s.owned, s.wanted
  from public.shares s join auth.users u on u.id = s.viewer_id
  where s.owner_id = auth.uid()
  order by s.created_at;
$$;

create or replace function public.shared_with_me()
returns table (owner_id uuid, email text, owned boolean, wanted boolean)
language sql stable security definer set search_path = ''
as $$
  select s.owner_id, u.email::text, s.owned, s.wanted
  from public.shares s join auth.users u on u.id = s.owner_id
  where s.viewer_id = auth.uid()
  order by u.email;
$$;

revoke all on function public.share_shelf(text, boolean, boolean) from public, anon;
revoke all on function public.my_shares() from public, anon;
revoke all on function public.shared_with_me() from public, anon;
grant execute on function public.share_shelf(text, boolean, boolean) to authenticated;
grant execute on function public.my_shares() to authenticated;
grant execute on function public.shared_with_me() to authenticated;

commit;

-- Kontrola (uruchom osobno):
-- select policyname, cmd from pg_policies where tablename in ('albums', 'shares');
-- select * from public.shares;
