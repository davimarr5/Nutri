-- =============================================================================
-- Irrobustimento delle funzioni
-- =============================================================================
-- Nasce da sei warning del Supabase security advisor emersi subito dopo
-- l'applicazione dello schema. Tutti reali, tutti chiusi qui.
--
-- Dopo questa migration l'advisor di sicurezza è pulito: 0 lint.
-- Conviene rilanciarlo dopo ogni cambiamento DDL.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. search_path immutabile sulle funzioni trigger
-- -----------------------------------------------------------------------------
-- `handle_new_user` e `sync_meal_item_user` avevano già `set search_path = ''`.
-- Le due `touch_updated_at` no: sfuggite perché sembrano innocue.
--
-- Non lo sono. Con un search_path manipolabile dal ruolo chiamante, un
-- simbolo non qualificato può risolversi a un oggetto di uno schema
-- controllato dall'attaccante.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

create or replace function odbl.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

-- -----------------------------------------------------------------------------
-- 2. Le funzioni trigger non devono essere richiamabili via API
-- -----------------------------------------------------------------------------
-- PostgREST espone ogni funzione dello schema `public` su /rest/v1/rpc/<nome>.
-- Due funzioni SECURITY DEFINER erano quindi invocabili direttamente, anche
-- da `anon`: sono trigger, non endpoint.
--
-- Postgres verifica il privilegio EXECUTE alla CREAZIONE del trigger, non a
-- ogni scatto. Revocarlo non rompe i trigger già esistenti.

revoke execute on function public.handle_new_user()     from public, anon, authenticated;
revoke execute on function public.sync_meal_item_user() from public, anon, authenticated;

-- `export_my_data` resta invocabile dagli autenticati: è la funzione di
-- portabilità GDPR (art. 20) ed è SECURITY INVOKER, quindi la RLS la filtra
-- ai soli dati del chiamante. Ad `anon` però non serve.
revoke execute on function public.export_my_data() from anon;
