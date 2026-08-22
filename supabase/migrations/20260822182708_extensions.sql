-- =============================================================================
-- 0000 — Estensioni
-- =============================================================================

-- Supabase questo schema ce l'ha già; la riga serve per far girare le
-- migration anche su un Postgres pulito (test locali, CI).
create schema if not exists extensions;

-- Ricerca alimenti per similarità ("parmigana" deve trovare "parmigiana").
create extension if not exists pg_trgm with schema extensions;

-- gen_random_uuid() è nativo da Postgres 13. pgcrypto resta per il resto.
create extension if not exists pgcrypto with schema extensions;

-- NOTA: gli operator class dell'estensione (gin_trgm_ops) vanno sempre
-- qualificati come extensions.gin_trgm_ops negli indici. Lo schema
-- `extensions` non è garantito nel search_path di tutti i ruoli, e un
-- indice che non risolve fa fallire l'intera migration.
