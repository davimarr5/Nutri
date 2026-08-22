-- =============================================================================
-- 0001 — ZONA ODbL
-- =============================================================================
-- Tutto ciò che sta in questo schema deriva da Open Food Facts (ODbL) o da
-- fonti pubbliche (CREA). Vincoli della licenza:
--
--   • ATTRIBUZIONE: obbligatoria e visibile in app
--   • SHARE-ALIKE: il database derivato va reso disponibile con la stessa
--     licenza. Riguarda il DATABASE, non l'app (che è "produced work").
--
-- Tenere questi dati in uno schema Postgres separato rende la conformità
-- un'operazione sola:
--
--     pg_dump --schema=odbl > odbl-derivative.sql
--
-- REGOLA: nessuna tabella di questo schema può contenere dati utente.
--         Nessuna tabella utente può contenere una foreign key che di fatto
--         incorpori questi dati (vedi snapshot dei macro in 0002).
-- =============================================================================

create schema if not exists odbl;

comment on schema odbl is
  'Dati derivati da Open Food Facts (ODbL) e CREA. Share-alike: pubblicabile con pg_dump --schema=odbl. Non inserire mai dati utente qui.';

-- -----------------------------------------------------------------------------
-- Provenienza
-- -----------------------------------------------------------------------------

create type odbl.data_source as enum (
  'off',        -- Open Food Facts
  'crea',       -- Tabelle di composizione degli alimenti CREA
  'ocr',        -- Letto da etichetta via OCR (livello 3 della catena barcode)
  'manual'      -- Inserito o corretto a mano
);

-- -----------------------------------------------------------------------------
-- Alimenti generici (base CREA) — "pasta di semola cruda", "petto di pollo"
-- -----------------------------------------------------------------------------

create table odbl.foods (
  id              uuid primary key default gen_random_uuid(),
  source          odbl.data_source not null,
  source_ref      text,                       -- codice CREA
  name_it         text not null,
  name_en         text,
  category        text not null,              -- fk logica verso odbl.densities
  synonyms        text[] not null default '{}',

  -- Valori per 100 g di parte edibile
  kcal            numeric(7,2) not null,
  protein_g       numeric(7,2) not null,
  carb_g          numeric(7,2) not null,
  sugar_g         numeric(7,2),
  fat_g           numeric(7,2) not null,
  sat_fat_g       numeric(7,2),
  fiber_g         numeric(7,2),
  salt_g          numeric(7,2),

  -- Fattore di conversione crudo → cotto (la pasta pesa ~2,3x da cotta)
  cooked_factor   numeric(5,2),

  completeness    numeric(3,2) not null default 0 check (completeness between 0 and 1),
  verified        boolean not null default false,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint foods_kcal_plausible check (kcal >= 0 and kcal <= 950)
);

create index foods_category_idx on odbl.foods (category);
create index foods_name_it_trgm_idx
  on odbl.foods using gin (name_it extensions.gin_trgm_ops);
create unique index foods_source_ref_idx on odbl.foods (source, source_ref)
  where source_ref is not null;

-- -----------------------------------------------------------------------------
-- Prodotti confezionati (mirror OFF + cache propria + OCR)
-- -----------------------------------------------------------------------------

create table odbl.products (
  barcode         text primary key,
  name            text not null,
  brand           text,
  countries       text[] not null default '{}',

  package_g       numeric(9,2),               -- peso netto confezione
  serving_g       numeric(9,2),               -- porzione dichiarata

  -- Valori per 100 g
  kcal            numeric(7,2),
  protein_g       numeric(7,2),
  carb_g          numeric(7,2),
  sugar_g         numeric(7,2),
  fat_g           numeric(7,2),
  sat_fat_g       numeric(7,2),
  fiber_g         numeric(7,2),
  salt_g          numeric(7,2),

  source          odbl.data_source not null,
  off_synced_at   timestamptz,
  completeness    numeric(3,2) not null default 0 check (completeness between 0 and 1),

  -- Se true, il record è stato corretto da noi e va ricontribuito a OFF
  contributed     boolean not null default false,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint products_barcode_format check (barcode ~ '^[0-9]{6,14}$')
);

create index products_countries_idx on odbl.products using gin (countries);
create index products_name_trgm_idx
  on odbl.products using gin (name extensions.gin_trgm_ops);
-- Prodotti da ricontribuire a Open Food Facts
create index products_to_contribute_idx on odbl.products (updated_at)
  where source = 'ocr' and contributed = false;

comment on column odbl.products.completeness is
  'Circa il 33% delle voci OFF non ha macro completi. Sotto 0.8 innescare il fallback OCR etichetta.';

-- -----------------------------------------------------------------------------
-- Densità: volume stimato dalla foto → grammi
-- -----------------------------------------------------------------------------

create table odbl.densities (
  category        text primary key,
  density_g_ml    numeric(5,3) not null check (density_g_ml > 0),
  notes           text
);

comment on table odbl.densities is
  'Passaggio 3 della pipeline di scansione. La densità è la maggiore fonte di errore residuo dopo l''ancoraggio metrico.';

insert into odbl.densities (category, density_g_ml, notes) values
  ('liquidi',            1.000, 'acqua, brodo, latte scremato'),
  ('latticini_liquidi',  1.030, 'latte intero, yogurt da bere'),
  ('oli_grassi',         0.918, 'olio di oliva, semi'),
  ('pasta_cotta',        0.650, 'scolata, non condita'),
  ('riso_cotto',         0.800, ''),
  ('cereali_secchi',     0.550, 'a volume sfuso'),
  ('legumi_cotti',       0.750, ''),
  ('carne_pesce',        1.050, 'porzione compatta'),
  ('formaggi_duri',      1.100, ''),
  ('formaggi_freschi',   1.030, ''),
  ('verdure_crude',      0.400, 'a foglia, molto variabile per volume sfuso'),
  ('verdure_cotte',      0.850, ''),
  ('frutta',             0.900, ''),
  ('pane',               0.300, 'alveolatura molto variabile'),
  ('dolci_da_forno',     0.450, ''),
  ('salse',              1.050, ''),
  ('zuppe',              1.000, ''),
  ('default',            0.850, 'fallback quando la categoria non è determinabile');

-- -----------------------------------------------------------------------------
-- Porzioni di riferimento italiane
-- -----------------------------------------------------------------------------
-- Prior iniziale, prima che il prior personale dell'utente abbia dati a
-- sufficienza (§5 del brief, leva 3). Non sono valori "corretti": sono il
-- punto di partenza da cui il sistema si allontana imparando l'utente.

create table odbl.reference_portions (
  id              uuid primary key default gen_random_uuid(),
  category        text not null,
  label           text not null,
  grams           numeric(7,2) not null,
  size            text not null check (size in ('S','M','L')),
  locale          text not null default 'it-IT'
);

create index reference_portions_lookup_idx
  on odbl.reference_portions (locale, category, size);

insert into odbl.reference_portions (category, label, grams, size) values
  ('pasta_cotta',   'Pasta, piccola',        170, 'S'),
  ('pasta_cotta',   'Pasta, media',          230, 'M'),
  ('pasta_cotta',   'Pasta, abbondante',     320, 'L'),
  ('riso_cotto',    'Riso, piccola',         150, 'S'),
  ('riso_cotto',    'Riso, media',           210, 'M'),
  ('riso_cotto',    'Riso, abbondante',      290, 'L'),
  ('carne_pesce',   'Secondo, piccolo',      100, 'S'),
  ('carne_pesce',   'Secondo, medio',        150, 'M'),
  ('carne_pesce',   'Secondo, grande',       220, 'L'),
  ('pane',          'Pane, fetta',            35, 'S'),
  ('pane',          'Pane, porzione',         60, 'M'),
  ('pane',          'Pane, abbondante',      100, 'L'),
  ('verdure_cotte', 'Contorno, piccolo',     100, 'S'),
  ('verdure_cotte', 'Contorno, medio',       170, 'M'),
  ('verdure_cotte', 'Contorno, grande',      250, 'L');

-- -----------------------------------------------------------------------------
-- Attribuzione: obbligo di licenza, non decorazione
-- -----------------------------------------------------------------------------

create table odbl.attributions (
  source          odbl.data_source primary key,
  display_name    text not null,
  license         text not null,
  url             text not null
);

insert into odbl.attributions (source, display_name, license, url) values
  ('off',  'Open Food Facts', 'ODbL v1.0',
   'https://openfoodfacts.org'),
  ('crea', 'CREA — Tabelle di composizione degli alimenti', 'Uso consentito con citazione',
   'https://www.alimentinutrizione.it');

-- -----------------------------------------------------------------------------
-- updated_at automatico
-- -----------------------------------------------------------------------------

create or replace function odbl.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger foods_touch
  before update on odbl.foods
  for each row execute function odbl.touch_updated_at();

create trigger products_touch
  before update on odbl.products
  for each row execute function odbl.touch_updated_at();
