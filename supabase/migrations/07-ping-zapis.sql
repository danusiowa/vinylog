-- =====================================================================
-- VinyLog · migracja 07: mocniejszy „ping”
-- Ping z migracji 06 tylko odczytywał godzinę i Supabase nie uznał tego
-- za aktywność (projekt i tak został uśpiony 2026-11). Teraz ping zapisuje
-- znacznik czasu w małej tabeli, więc baza ma prawdziwy zapis.
-- Tabela ma jeden wiersz; nikt poza funkcją nie ma do niej dostępu.
-- =====================================================================

create table if not exists public.heartbeat (
  id      smallint primary key default 1 check (id = 1),
  pinged  timestamptz not null default now(),
  count   bigint not null default 0
);
alter table public.heartbeat enable row level security;   -- bez polityk: z zewnątrz nic nie widać

create or replace function public.ping()
returns timestamptz
language sql
security definer
set search_path = ''
as $$
  insert into public.heartbeat (id, pinged, count) values (1, now(), 1)
  on conflict (id) do update set pinged = now(), count = public.heartbeat.count + 1
  returning pinged;
$$;

revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;
