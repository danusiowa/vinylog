-- =====================================================================
-- VinyLog · migracja 01: user_id + RLS (każdy widzi tylko swoje płyty)
-- Uruchom w Supabase: SQL Editor → New query → wklej → Run
-- Krok 2 przypisuje istniejące płyty do konta właścicielki.
-- W nowej instalacji podmień e-mail na własny (przy pustej tabeli nic się nie zmienia).
-- =====================================================================

begin;

-- 1. Kolumna właściciela. Domyślnie auth.uid(), więc frontend
--    NIE musi wysyłać user_id przy dodawaniu płyty.
alter table public.albums
  add column if not exists user_id uuid
  references auth.users (id) on delete cascade
  default auth.uid();

-- 2. Istniejące płyty przypisujemy do konta właścicielki.
update public.albums
set user_id = (select id from auth.users where email = 'danusiowa@gmail.com')
where user_id is null;

-- Zabezpieczenie: jeśli e-mail był błędny, przerywamy całą migrację.
do $$
begin
  if exists (select 1 from public.albums where user_id is null) then
    raise exception 'Część płyt nie ma właściciela. Sprawdź, czy konto z kroku 2 istnieje w Authentication → Users.';
  end if;
end $$;

alter table public.albums alter column user_id set not null;

-- 3. „Po wypłacie” — ta sama tabela, inny status.
--    owned  = Moja kolekcja
--    wanted = Po wypłacie
alter table public.albums
  add column if not exists status text not null default 'owned'
  check (status in ('owned', 'wanted'));

-- 4. Kod kreskowy (EAN/UPC) ze skanera — przydaje się też do wykrywania duplikatów.
alter table public.albums
  add column if not exists barcode text;

-- 5. Indeksy pod zapytania „moje płyty” i „czy już to mam”.
create index if not exists albums_user_status_idx on public.albums (user_id, status, created_at desc);
create index if not exists albums_user_barcode_idx on public.albums (user_id, barcode) where barcode is not null;

-- 6. RLS: włączamy i usuwamy WSZYSTKIE stare polityki na albums.
alter table public.albums enable row level security;

do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'albums'
  loop
    execute format('drop policy %I on public.albums', p.policyname);
  end loop;
end $$;

-- 7. Nowe polityki: tylko zalogowani i tylko własne wiersze.
create policy "albums_select_own" on public.albums
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "albums_insert_own" on public.albums
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "albums_update_own" on public.albums
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "albums_delete_own" on public.albums
  for delete to authenticated
  using ((select auth.uid()) = user_id);

commit;

-- Kontrola (uruchom osobno po migracji):
-- select policyname, cmd, roles from pg_policies where tablename = 'albums';
-- select status, count(*) from public.albums group by status;
