-- =============================================================================
-- 0003 — Row Level Security
-- =============================================================================
-- Principio: nessuna tabella con dati utente esce da qui senza RLS attiva.
-- Un dato sanitario esposto per una policy dimenticata è esattamente lo
-- scenario che ha colpito Cal AI (3,2M utenti). Vedi §9 del brief.
--
-- Nota sulle performance: tutte le policy usano (select auth.uid()) invece di
-- auth.uid() nudo. Il wrapping in subquery permette a Postgres di valutare la
-- funzione una volta sola invece che riga per riga.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Zona ODbL — lettura pubblica agli autenticati, scrittura solo service_role
-- -----------------------------------------------------------------------------
-- Questi dati sono, per licenza, aperti: non c'è niente da proteggere in
-- lettura. La scrittura passa da edge function con service_role, perché la
-- qualità del database condiviso non può dipendere dai client.

alter table odbl.foods              enable row level security;
alter table odbl.products           enable row level security;
alter table odbl.densities          enable row level security;
alter table odbl.reference_portions enable row level security;
alter table odbl.attributions       enable row level security;

create policy "odbl leggibile dagli autenticati"
  on odbl.foods for select to authenticated using (true);
create policy "odbl leggibile dagli autenticati"
  on odbl.products for select to authenticated using (true);
create policy "odbl leggibile dagli autenticati"
  on odbl.densities for select to authenticated using (true);
create policy "odbl leggibile dagli autenticati"
  on odbl.reference_portions for select to authenticated using (true);
create policy "odbl leggibile dagli autenticati"
  on odbl.attributions for select to authenticated using (true);

-- -----------------------------------------------------------------------------
-- Zona proprietaria
-- -----------------------------------------------------------------------------

alter table public.profiles      enable row level security;
alter table public.consents      enable row level security;
alter table public.weight_logs   enable row level security;
alter table public.meals         enable row level security;
alter table public.meal_items    enable row level security;
alter table public.saved_meals   enable row level security;
alter table public.tableware     enable row level security;
alter table public.food_priors   enable row level security;
alter table public.calibrations  enable row level security;
alter table public.scan_events   enable row level security;

-- profiles: l'utente vede e modifica solo il proprio.
-- Nessuna INSERT policy: il profilo lo crea il trigger on_auth_user_created.
-- Nessuna DELETE policy: si cancella con l'account (on delete cascade).
create policy "profilo proprio: lettura"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "profilo proprio: modifica"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Tabelle con user_id: stesso schema di policy per tutte.
do $$
declare
  t text;
begin
  foreach t in array array[
    'consents', 'weight_logs', 'meals', 'meal_items', 'saved_meals',
    'tableware', 'food_priors', 'calibrations', 'scan_events'
  ]
  loop
    execute format($f$
      create policy "dati propri: lettura" on public.%I
        for select to authenticated
        using (user_id = (select auth.uid()));

      create policy "dati propri: inserimento" on public.%I
        for insert to authenticated
        with check (user_id = (select auth.uid()));

      create policy "dati propri: modifica" on public.%I
        for update to authenticated
        using (user_id = (select auth.uid()))
        with check (user_id = (select auth.uid()));

      create policy "dati propri: cancellazione" on public.%I
        for delete to authenticated
        using (user_id = (select auth.uid()));
    $f$, t, t, t, t);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Esportazione dati (GDPR art. 20 — portabilità)
-- -----------------------------------------------------------------------------
-- Deve funzionare dal primo giorno, non "da aggiungere poi": §9 del brief.

create or replace function public.export_my_data()
returns jsonb
language sql
security invoker          -- volutamente: la RLS deve applicarsi
stable
set search_path = public
as $$
  select jsonb_build_object(
    'exported_at',  now(),
    'profile',      (select to_jsonb(p) from profiles p where p.id = auth.uid()),
    'consents',     (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from consents c),
    'weight_logs',  (select coalesce(jsonb_agg(to_jsonb(w)), '[]'::jsonb) from weight_logs w),
    'meals',        (select coalesce(jsonb_agg(
                       to_jsonb(m) || jsonb_build_object(
                         'items', (select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb)
                                   from meal_items i where i.meal_id = m.id)
                       )), '[]'::jsonb) from meals m),
    'saved_meals',  (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) from saved_meals s),
    'tableware',    (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from tableware t),
    'food_priors',  (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) from food_priors f),
    'calibrations', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from calibrations c)
  );
$$;

comment on function public.export_my_data is
  'GDPR art. 20. security invoker di proposito: la RLS filtra ai dati del chiamante.';

-- -----------------------------------------------------------------------------
-- Totali giornalieri
-- -----------------------------------------------------------------------------
-- security_invoker = true: la vista eredita la RLS di chi la interroga.
-- Senza questo flag una vista bypassa la RLS delle tabelle sottostanti.

create view public.daily_totals
with (security_invoker = true)
as
select
  user_id,
  eaten_on,
  sum(kcal)                        as kcal,
  -- coalesce obbligatorio: kcal_low/high sono nulli per i log da barcode,
  -- dove l'incertezza è trascurabile. Sommarli senza fallback restringerebbe
  -- l'intervallo giornaliero ogni volta che l'utente usa il barcode, cioè
  -- esattamente quando dovrebbe essere più stretto ma centrato.
  sum(coalesce(kcal_low,  kcal))   as kcal_low,
  sum(coalesce(kcal_high, kcal))   as kcal_high,
  sum(protein_g)                   as protein_g,
  sum(carb_g)                      as carb_g,
  sum(fat_g)                       as fat_g,
  sum(fiber_g)                     as fiber_g,
  count(*)                         as meal_count,
  count(*) filter (where method in ('barcode','manual'))   as precise_count,
  count(*) filter (where method = 'photo')                 as photo_count
from public.meals
group by user_id, eaten_on;

comment on view public.daily_totals is
  'precise_count / photo_count servono alla separazione parziale del bias descritta in §5: giorni a logging prevalentemente barcode hanno bias vicino a zero.';
