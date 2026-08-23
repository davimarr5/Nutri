-- =============================================================================
-- Permessi sullo schema odbl
-- =============================================================================
-- Difetto emerso al primo test reale dell'API: lo schema era esposto via
-- PostgREST ma ogni query rispondeva
--
--     42501 — permission denied for schema odbl
--
-- Motivo: abilitare la RLS e scrivere le policy non basta. Prima della RLS
-- Postgres verifica i privilegi GRANT, e su uno schema personalizzato non
-- ce n'è nessuno di default. Su `public` Supabase li concede in automatico,
-- ed è per questo che il problema non si vede finché non si crea uno schema
-- proprio.
--
-- Ordine dei controlli, da ricordare:
--     1. lo schema è esposto in Data API?   → altrimenti PGRST106
--     2. il ruolo ha USAGE e SELECT?         → altrimenti 42501
--     3. esiste una policy RLS che passa?    → altrimenti zero righe
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Lettura: solo utenti autenticati
-- -----------------------------------------------------------------------------
-- Coerente con le policy RLS di 20260822182849, tutte "to authenticated":
-- il database alimenti si consulta da loggati.
--
-- `anon` resta volutamente fuori. I dati sono ODbL e quindi liberi, ma non
-- c'è ragione di offrire un endpoint di scraping senza account: chi vuole il
-- dataset lo prende dalla fonte, o dal nostro dump ODbL.

grant usage on schema odbl to authenticated;
grant select on all tables in schema odbl to authenticated;

-- -----------------------------------------------------------------------------
-- Scrittura: solo service_role
-- -----------------------------------------------------------------------------
-- È la via della sincronizzazione Open Food Facts e dei contributi OCR, che
-- passano da edge function. La qualità del database condiviso non può
-- dipendere dai client.

grant usage on schema odbl to service_role;
grant all on all tables in schema odbl to service_role;
grant all on all sequences in schema odbl to service_role;

-- -----------------------------------------------------------------------------
-- Stessi privilegi per le tabelle future
-- -----------------------------------------------------------------------------
-- Senza questo, ogni nuova tabella in odbl ripresenta lo stesso 42501.

alter default privileges in schema odbl
  grant select on tables to authenticated;
alter default privileges in schema odbl
  grant all on tables to service_role;
alter default privileges in schema odbl
  grant all on sequences to service_role;
