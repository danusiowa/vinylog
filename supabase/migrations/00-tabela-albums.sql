-- =====================================================================
-- VinyLog · migracja 00: tabela płyt (tylko dla nowej instalacji)
-- Uruchom w Supabase: SQL Editor → New query → wklej → Run
-- Kolejne migracje (01–04) dokładają właściciela, RLS, szczegóły wydania,
-- magazyn okładek i liczbę egzemplarzy.
-- =====================================================================

create table if not exists public.albums (
  id         uuid primary key default gen_random_uuid(),
  artist     text not null default '',
  title      text not null default '',
  image_url  text,
  source_url text,
  created_at timestamptz not null default now()
);
