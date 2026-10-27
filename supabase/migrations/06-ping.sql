-- =====================================================================
-- VinyLog · migracja 06: „ping” dla automatycznego budzika
-- Darmowy Supabase usypia projekt po 7 dniach bez ruchu. Workflow GitHub
-- (.github/workflows/supabase-ping.yml) co 3 dni wywołuje tę funkcję,
-- więc baza dostaje zapytanie i projekt się nie usypia.
-- Funkcja nic nie czyta z tabel i nic nie zmienia.
-- =====================================================================

create or replace function public.ping()
returns timestamptz
language sql stable
set search_path = ''
as $$ select now() $$;

revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;
