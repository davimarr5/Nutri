-- =============================================================================
-- 0002 — ZONA PROPRIETARIA
-- =============================================================================
-- Dati utente. Non deriva da Open Food Facts e non è soggetto a share-alike.
--
-- Il confine con lo schema `odbl` è tenuto pulito da una regola precisa:
-- i valori nutrizionali vengono COPIATI (snapshot) dentro meal_items al
-- momento del log, non referenziati. Due motivi, entrambi importanti:
--
--   1. IMMUTABILITÀ — OFF cambia. Una voce di diario di tre mesi fa non deve
--      cambiare di nascosto perché qualcuno ha corretto il prodotto su OFF.
--   2. LICENZA — il diario contiene valori copiati in un momento preciso,
--      non un database derivato da OFF. Il confine resta netto.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tipi
-- -----------------------------------------------------------------------------

create type public.user_branch as enum ('athlete', 'general');
create type public.user_goal as enum ('lose', 'maintain', 'gain');
create type public.biological_sex as enum ('male', 'female');

create type public.activity_level as enum (
  'sedentary',      -- 1.20  lavoro da seduto, nessun movimento strutturato
  'light',          -- 1.375 1-3 sessioni/settimana
  'moderate',       -- 1.55  3-5 sessioni/settimana
  'high',           -- 1.725 6-7 sessioni/settimana
  'athlete'         -- 1.90  doppie sessioni o lavoro fisico
);

create type public.meal_type as enum (
  'breakfast', 'lunch', 'dinner', 'snack'
);

create type public.log_method as enum (
  'photo',      -- scansione AI
  'barcode',    -- lettura codice a barre
  'label_ocr',  -- OCR etichetta (livello 3 catena barcode)
  'manual',     -- ricerca e inserimento a mano
  'saved'       -- pasto ricorrente, 1 tap
);

create type public.confidence_level as enum ('low', 'medium', 'high');

create type public.tableware_kind as enum ('plate', 'bowl', 'glass', 'cup', 'other');

create type public.consent_kind as enum (
  'health_data',      -- art. 9 GDPR — obbligatorio per usare l'app
  'photo_retention',  -- conservare le foto oltre l'elaborazione — default NO
  'analytics',        -- telemetria anonima
  'off_contribution'  -- ricontribuire i dati OCR a Open Food Facts
);

-- -----------------------------------------------------------------------------
-- Profilo
-- -----------------------------------------------------------------------------

create table public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,

  branch            public.user_branch not null default 'general',
  goal              public.user_goal not null default 'maintain',

  sex               public.biological_sex,
  birth_date        date,
  height_cm         numeric(5,1) check (height_cm between 80 and 250),
  activity_level    public.activity_level not null default 'light',
  body_fat_pct      numeric(4,1) check (body_fat_pct between 3 and 70),

  -- Ritmo desiderato in kg/settimana. Negativo = perdita.
  -- Limitato per costruzione: vedi guardrail §9 del brief.
  rate_kg_per_week  numeric(4,3) not null default 0
                    check (rate_kg_per_week between -1.0 and 0.5),

  -- Guardrail disturbi alimentari
  hide_calories     boolean not null default false,   -- modalità solo-macro

  locale            text not null default 'it-IT',
  timezone          text not null default 'Europe/Rome',

  onboarded_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on column public.profiles.hide_calories is
  'Modalità solo-macro: nasconde completamente le calorie in tutta l''app. Guardrail DCA, non una preferenza estetica.';

-- -----------------------------------------------------------------------------
-- Consensi (GDPR art. 9 — dati relativi alla salute)
-- -----------------------------------------------------------------------------

create table public.consents (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  kind            public.consent_kind not null,
  granted         boolean not null,
  policy_version  text not null,
  granted_at      timestamptz not null default now(),
  revoked_at      timestamptz,

  unique (user_id, kind, policy_version)
);

create index consents_user_idx on public.consents (user_id, kind);

comment on table public.consents is
  'Peso, obiettivi e diario alimentare per finalità di salute sono dati particolari ex art. 9 GDPR: serve consenso esplicito, granulare, revocabile e tracciabile nel tempo.';

-- -----------------------------------------------------------------------------
-- Peso
-- -----------------------------------------------------------------------------

create table public.weight_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  logged_on   date not null,
  weight_kg   numeric(5,2) not null check (weight_kg between 25 and 400),
  created_at  timestamptz not null default now(),

  unique (user_id, logged_on)
);

create index weight_logs_user_date_idx on public.weight_logs (user_id, logged_on desc);

-- -----------------------------------------------------------------------------
-- Diario
-- -----------------------------------------------------------------------------

create table public.meals (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,

  eaten_at        timestamptz not null default now(),
  eaten_on        date not null,               -- denormalizzato: il diario è per giorno locale
  meal_type       public.meal_type not null,
  method          public.log_method not null,

  -- Stima con intervallo. Mai un numero secco: §5 del brief.
  kcal            numeric(8,2) not null default 0,
  kcal_low        numeric(8,2),
  kcal_high       numeric(8,2),
  confidence      public.confidence_level not null default 'medium',

  protein_g       numeric(7,2) not null default 0,
  carb_g          numeric(7,2) not null default 0,
  fat_g           numeric(7,2) not null default 0,
  fiber_g         numeric(7,2),

  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint meals_interval_ordered
    check (kcal_low is null or kcal_high is null or kcal_low <= kcal_high)
);

create index meals_user_day_idx on public.meals (user_id, eaten_on desc);
create index meals_method_idx on public.meals (user_id, method);

comment on column public.meals.kcal_low is
  'Estremo inferiore dell''intervallo di confidenza. Esposto in UI come "430 ± 90 kcal". Nullo solo per il barcode, dove l''incertezza è trascurabile.';

create table public.meal_items (
  id              uuid primary key default gen_random_uuid(),
  meal_id         uuid not null references public.meals(id) on delete cascade,

  -- Denormalizzato di proposito. Permette una policy RLS diretta
  -- (user_id = auth.uid()) invece di una EXISTS su meals: le join dentro RLS
  -- sono la prima causa di degrado nelle app Supabase, e aggiungerlo dopo
  -- significa migrare dati in produzione. Mantenuto coerente dal trigger sotto.
  user_id         uuid not null references auth.users(id) on delete cascade,

  -- Riferimenti alla zona ODbL: solo per tracciabilità e ri-log.
  -- I valori usati per i calcoli sono quelli copiati sotto.
  food_id         uuid references odbl.foods(id) on delete set null,
  barcode         text references odbl.products(barcode) on delete set null,

  display_name    text not null,
  grams           numeric(8,2) not null check (grams >= 0),
  grams_low       numeric(8,2),
  grams_high      numeric(8,2),

  -- SNAPSHOT — vedi intestazione del file. Non sostituire con una join.
  kcal            numeric(8,2) not null,
  protein_g       numeric(7,2) not null,
  carb_g          numeric(7,2) not null,
  fat_g           numeric(7,2) not null,
  fiber_g         numeric(7,2),

  -- L'utente ha corretto la stima dell'AI? Segnale per il prior personale
  -- e per misurare l'errore reale del modello.
  user_corrected  boolean not null default false,
  position        smallint not null default 0,

  created_at      timestamptz not null default now()
);

create index meal_items_meal_idx on public.meal_items (meal_id, position);
create index meal_items_user_idx on public.meal_items (user_id);

-- Garantisce che meal_items.user_id non possa divergere da meals.user_id,
-- anche se il client lo omette o sbaglia.
create or replace function public.sync_meal_item_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select m.user_id into new.user_id
  from public.meals m
  where m.id = new.meal_id;

  if new.user_id is null then
    raise exception 'meal_id % inesistente', new.meal_id;
  end if;

  return new;
end;
$$;

create trigger meal_items_sync_user
  before insert or update of meal_id on public.meal_items
  for each row execute function public.sync_meal_item_user();

-- -----------------------------------------------------------------------------
-- Pasti ricorrenti — il motore di retention e di risparmio sui costi
-- -----------------------------------------------------------------------------

create table public.saved_meals (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  name          text not null,
  meal_type     public.meal_type,

  -- Snapshot completo degli item, così il ri-log è 1 tap e 0 chiamate AI
  items         jsonb not null,

  kcal          numeric(8,2) not null,
  protein_g     numeric(7,2) not null,
  carb_g        numeric(7,2) not null,
  fat_g         numeric(7,2) not null,

  use_count     integer not null default 0,
  last_used_at  timestamptz,
  created_at    timestamptz not null default now()
);

create index saved_meals_user_idx on public.saved_meals (user_id, use_count desc, last_used_at desc);

comment on table public.saved_meals is
  'Obiettivo: >70% dei log serviti da qui entro 3 settimane. È insieme la metrica di abitudine e il principale abbattimento dei costi AI.';

-- -----------------------------------------------------------------------------
-- Stoviglie apprese (§5, leva 2)
-- -----------------------------------------------------------------------------

create table public.tableware (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,

  label              text,                    -- "piatto piano bianco"
  kind               public.tableware_kind not null default 'plate',

  diameter_mm        numeric(6,1),
  depth_mm           numeric(6,1),
  volume_ml          numeric(7,1),

  -- Vettore di feature visive per il clustering. Non è un embedding semantico:
  -- serve solo a riconoscere "è di nuovo lo stesso piatto".
  features           jsonb,

  observation_count  integer not null default 1,
  confidence         numeric(3,2) not null default 0 check (confidence between 0 and 1),

  -- Diventa un righello attendibile solo dopo >=5 osservazioni di cui almeno
  -- una con ancoraggio metrico reale.
  calibrated_at      timestamptz,

  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index tableware_user_idx on public.tableware (user_id, kind);
create index tableware_calibrated_idx on public.tableware (user_id)
  where calibrated_at is not null;

-- -----------------------------------------------------------------------------
-- Prior personali sulle porzioni (§5, leva 3)
-- -----------------------------------------------------------------------------

create table public.food_priors (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,

  -- Chiave normalizzata: barcode, oppure food_id, oppure nome normalizzato
  food_key           text not null,
  display_name       text not null,

  median_grams       numeric(8,2) not null,
  p25_grams          numeric(8,2),
  p75_grams          numeric(8,2),
  observation_count  integer not null default 1,
  last_seen_at       timestamptz not null default now(),

  unique (user_id, food_key)
);

create index food_priors_user_idx on public.food_priors (user_id, last_seen_at desc);

comment on table public.food_priors is
  'Dopo ~3 settimane il modello non stima da zero: stima lo scostamento dall''abitudine dell''utente. È il taglio più grosso alla varianza.';

-- -----------------------------------------------------------------------------
-- Calibrazione del bias (§5 — la feature-firma)
-- -----------------------------------------------------------------------------

create table public.calibrations (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,

  computed_on        date not null,
  window_days        integer not null,

  -- Fattore MOLTIPLICATIVO combinato applicato all'intake loggato.
  -- ATTENZIONE: non è "quanto sottostimi". Confonde inseparabilmente
  -- l'errore di logging e l'errore sul TDEE — vedi §5 del brief.
  -- Non mostrarlo mai scomposto all'utente: non è identificabile.
  factor             numeric(4,3) not null check (factor between 0.70 and 1.80),

  logged_mean_kcal   numeric(8,2) not null,
  weight_slope_kg_d  numeric(8,6) not null,
  weight_points      integer not null,
  r_squared          numeric(4,3),

  applied            boolean not null default false,
  created_at         timestamptz not null default now(),

  unique (user_id, computed_on)
);

create index calibrations_user_idx on public.calibrations (user_id, computed_on desc);

-- -----------------------------------------------------------------------------
-- Telemetria scansioni — costi e validazione dello stack di errore
-- -----------------------------------------------------------------------------
-- Serve a due cose concrete:
--   • tenere sotto controllo il costo per utente attivo
--   • misurare davvero i numeri stimati nella tabella §5 del brief,
--     invece di continuare a citarli come stime
--
-- NON contiene la foto. Vedi policy §9: le immagini si cancellano dopo
-- l'elaborazione salvo consenso esplicito.

create table public.scan_events (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  meal_id            uuid references public.meals(id) on delete set null,

  model              text not null,
  input_tokens       integer,
  output_tokens      integer,
  cost_eur           numeric(8,6),
  latency_ms         integer,

  -- Qualità dell'ancoraggio metrico su questa scansione
  anchor_source      text check (anchor_source in
                       ('ar_plane','tableware','reference_object','exif_only','none')),
  frames_used        smallint,

  -- Segnale d'oro: di quanto l'utente ha corretto la stima.
  -- 1.0 = nessuna correzione. 1.25 = l'AI aveva sottostimato del 20%.
  user_adjusted      boolean not null default false,
  adjustment_ratio   numeric(6,3),

  created_at         timestamptz not null default now()
);

create index scan_events_user_idx on public.scan_events (user_id, created_at desc);
create index scan_events_anchor_idx on public.scan_events (anchor_source, created_at desc);

comment on column public.scan_events.adjustment_ratio is
  'Aggregato su molti utenti, è la misura diretta del bias del modello per fonte di ancoraggio. È il dato che valida (o smentisce) lo stack di errore del brief.';

-- -----------------------------------------------------------------------------
-- updated_at
-- -----------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger meals_touch before update on public.meals
  for each row execute function public.touch_updated_at();
create trigger tableware_touch before update on public.tableware
  for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Profilo creato automaticamente alla registrazione
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
