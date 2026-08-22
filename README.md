# Nutri *(codename)*

App di tracciamento calorie e macro con riconoscimento fotografico.

Posizionamento, decisioni di prodotto e roadmap stanno in **[BRIEF.md](./BRIEF.md)**.
Leggilo prima di toccare il codice: diverse scelte qui sotto sembrano arbitrarie
e non lo sono.

**Stato:** fase 0 — fondamenta.
App Expo inizializzata, schema e logica nutrizionale pronti, **migration non
ancora applicate**.

---

## Ambiente

| | |
|---|---|
| Expo SDK | 57.0.15 · React Native 0.86.2 · React 19.2.3 |
| Router | expo-router, rotte tipizzate, `src/app/` |
| EAS | `@davimarr/nutri` · `cf67d1bf-6289-417e-aecc-e735381a8312` |
| Supabase | progetto **Nutri** · `iuiskyzvuevquisjhblm` · **eu-west-1 (Irlanda)** |
| Alias TS | `@/*` → `./src/*` |

La regione Supabase è dentro l'UE: requisito soddisfatto per i dati sanitari
ex art. 9 GDPR (§9 del brief). **Non è modificabile dopo la creazione.**

---

## Struttura

```
src/
  app/                  rotte expo-router
  components/           UI
  domain/nutrition/     logica pura, 30 test verdi — nessuna dipendenza
    types.ts            tipi condivisi
    energy.ts           Mifflin-St Jeor, Katch-McArdle, fattori attività
    targets.ts          target calorici, guardrail, ripartizione macro
    calibration.ts      correttivo combinato dal trend di peso
  lib/supabase.ts       client Supabase

supabase/migrations/
  0000_extensions.sql   pg_trgm, pgcrypto
  0001_odbl_schema.sql  zona ODbL — alimenti, prodotti, densità, porzioni
  0002_app_schema.sql   zona proprietaria — profilo, diario, calibrazione
  0003_rls.sql          Row Level Security, export GDPR, vista totali
```

---

## Cosa manca per far girare tutto

### 1. Dipendenze runtime

```bash
npx expo install @supabase/supabase-js @react-native-async-storage/async-storage react-native-url-polyfill
npm install
```

`src/lib/supabase.ts` importa già questi tre pacchetti e senza di essi non
compila.

### 2. Variabili d'ambiente

```bash
cp .env.example .env
```

`GEMINI_API_KEY` **non** va prefissata con `EXPO_PUBLIC_`: quel prefisso la
includerebbe nel bundle, dove chiunque può estrarla. Le chiamate a Gemini
passano da edge function.

### 3. Migration

```bash
npx supabase link --project-ref iuiskyzvuevquisjhblm
npx supabase db push
```

### 4. Esporre lo schema `odbl`

Dashboard → Settings → API → **Exposed schemas** → aggiungi `odbl`.

Senza questo passaggio ogni query verso alimenti e prodotti risponde 404.

### 5. Collegare GitHub

Il repo locale non ha ancora un remote:

```bash
git remote add origin https://github.com/<utente>/<repo>.git
git push -u origin master
```

---

## Test

```bash
npm test
```

---

## Le tre regole da non violare

Il resto del codice si può rifare. Queste no: sbagliarle produce danni che si
scoprono tardi e si riparano solo con una migrazione.

### 1. I macro non escono mai da un LLM

L'LLM identifica l'alimento e stima la quantità. I valori nutrizionali vengono
**sempre** da `odbl.foods` o `odbl.products`.

Un macro allucinato non è distinguibile da uno corretto — non a runtime, non in
review. È l'unico errore di questo progetto davvero irreparabile.

### 2. Il confine ODbL non si attraversa

`odbl` contiene dati sotto Open Database License: attribuzione obbligatoria e
share-alike sul database derivato. `public` contiene dati utente e non è
soggetto a nulla di ciò.

Due schemi Postgres distinti rendono la conformità un comando solo:

```bash
pg_dump --schema=odbl > odbl-derivative.sql
```

Per questo `meal_items` **copia** i valori nutrizionali invece di referenziarli.
Due motivi validi ciascuno da solo: una voce di diario di tre mesi fa non deve
cambiare perché qualcuno ha corretto il prodotto su OFF, e il diario non deve
diventare un database derivato da OFF.

### 3. I guardrail non sono configurabili

`ABSOLUTE_KCAL_FLOOR`, `MAX_LOSS_RATE_KG_WEEK`, il floor sul metabolismo basale
e `hide_calories` non devono diventare impostazioni utente, feature flag o
parametri remoti.

Sono la differenza fra un'app che misura e un'app che fa danni, e sono anche ciò
che tiene il progetto dentro le policy degli store.

---

## Sul fattore di calibrazione

`computeCalibration()` restituisce **un solo numero combinato**, e non è un
limite dell'implementazione: è matematica.

```
variazione peso = intake reale − TDEE reale
```

Osserviamo l'intake *loggato* (distorto) e la variazione di peso. Una equazione,
due incognite: l'errore di logging e l'errore sul TDEE **non sono separabili**.

A scopo predittivo il fattore combinato funziona perfettamente — è tutto ciò che
serve per impostare un target che porti al risultato voluto. Ma non mostrare mai
all'utente "il tuo TDEE è X" o "sottostimi del Y%" come affermazioni separate:
sarebbero numeri inventati.

Una separazione parziale sarà possibile più avanti, regredendo i giorni a
logging prevalentemente barcode (bias ≈ 0) contro quelli a logging fotografico.
La vista `daily_totals` espone già `precise_count` e `photo_count` a questo
scopo.

---

## Attribuzione

Questo progetto usa dati di [Open Food Facts](https://openfoodfacts.org)
(ODbL v1.0) e le [Tabelle di composizione degli alimenti CREA](https://www.alimentinutrizione.it).
L'attribuzione deve restare visibile in app: è un obbligo di licenza, non una
cortesia.
