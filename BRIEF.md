# Brief di prodotto — App nutrizione con riconoscimento fotografico

**Stato:** brainstorming consolidato, pre-sviluppo
**Data:** 22 agosto 2026
**Autore:** Walter
**Progetto:** indipendente da AtletAI (nessuna dipendenza di codice, dati o account)

---

## 1. In una frase

Un'app di tracciamento calorie e macro in cui fai la foto e basta, e che invece di fingere precisione impara in due settimane **di quanto sbaglia su di te** e si corregge.

**Claim di posizionamento:**
> Fai la foto e basta. Nelle prime due settimane impariamo quanto sbagliamo su di te, poi ci correggiamo.

**Nome: rinviato deliberatamente.** Codename di lavoro: **Nutri**.

Il nome non blocca lo sviluppo. Il bundle ID (`com.wmarra.nutri`) non deve somigliare al brand, e il nome visualizzato sullo store si cambia liberamente. Decisione da riprendere in **fase 6**, dopo aver usato l'app per qualche settimana.

### Ricerca già svolta — non rifarla

**Zone fonetiche sature, da evitare:**

- **N + vocale morbida** → Noom, Numi, Nommie, Numify. Introvabili l'una dall'altra nella ricerca dello store
- **Cal / Kal** → Cal AI, Kalio, Calory
- **Nome latino morbido che finisce in vocale** (Miora, Liora, Talio…) → è la zona dove pesca tutto il settore AI+salute dal 2024. Quasi tutto occupato
- Radici descrittive: `food`, `fit`, `nutri`, `macro`, `diet`

**Candidati verificati e scartati:**

| Nome | Motivo |
|---|---|
| Kalio | È già un AI calorie tracker con scanner fotografico. Collisione frontale |
| Miora | Marchio Reina Health su "software chatbot AI per salute e nutrizione" |
| Talio | Marchio Wire Labs Inc. su software per app mobile |
| Liora | "Ask Liora" (assistente AI sanitario) + Liora Nutrition and Health Corp |
| Orzo | App di ricette in arrivo su iOS |
| Tenzo | SaaS per ristoranti, settore adiacente |
| Nemi | Libero, ma indistinguibile da Numi / Nommie / Noom |

**Unico verificato libero nella categoria giusta:** *Tavo* (collisioni solo in energia, pet, abbigliamento — classi diverse). Tenuto come rete di sicurezza, non come scelta.

### Regola decisa

**Un nome solo.** Se l'assistente AI (§ 11, fase 7) si chiama X, l'app si chiama X — modello Alexa, l'assistente *è* il prodotto. Da soli non si costruiscono due brand.

---

## 2. Decisioni prese

| Ambito | Decisione |
|---|---|
| Rapporto con AtletAI | **Progetto separato.** Nessun accoppiamento. Eventuale cross-promo e deep link in futuro, mai dipendenza |
| Piattaforma | **iOS + Android insieme**, React Native / Expo |
| Target | **Entrambi**, con onboarding che biforca fra "mi alleno" e "voglio dimagrire" |
| Mercato | **Italia prima**, con i18n e schema multi-paese previsti dal primo giorno |
| Impegno | **Full-time o quasi** |
| Orizzonte MVP | ~12 settimane a una beta pubblicabile |

### Nota critica sulla piattaforma

Fare iOS e Android insieme è la scelta giusta per il prodotto ed è **il rischio numero uno del calendario**. Il motivo non è React Native — è che l'ancoraggio metrico (ARKit vs ARCore) è l'unico pezzo che non si scrive una volta sola, ed è anche il più fragile.

Mitigazione: isolare tutta la parte di cattura e ancoraggio dietro **un'unica interfaccia** con una implementazione per piattaforma e un **fallback comune "nessun ancoraggio"** che deve funzionare da solo. L'app deve essere completa e utilizzabile anche se l'AR non dà mai un risultato. L'AR è un miglioramento della qualità, mai un requisito di funzionamento.

---

## 3. Perché esiste — il contesto competitivo

- L'identificazione del cibo da foto è **commodity**: 85-93% di precisione, la fa un prompt a Gemini Flash. Non è un vantaggio competitivo per nessuno
- La **stima della porzione** no: ~39% di affidabilità negli studi, 26-36% di errore medio sulle kcal, con sottostima sistematica che peggiora al crescere della porzione
- Cal AI ha fatto ~$50M ARR in 18 mesi ed è stata acquisita da MyFitnessPal a marzo 2026. Poi: rimozione temporanea dall'App Store per billing ingannevole e data breach su 3,2M utenti
- Yazio, Foodvisor, MyFitnessPal: nessuna espone l'incertezza, nessuna corregge il bias personale, nessuna è calibrata sul cibo italiano

**Conclusione:** la categoria ha soldi veri, il leader è stato assorbito da un incumbent e ha bruciato fiducia. Lo spazio non è "una foto più intelligente" — è **onestà, correzione personale e radicamento italiano**.

---

## 4. I quattro differenziatori

1. **Correzione del bias personale.** Dal trend di peso si ricava il fattore di errore individuale e lo si applica. Nessuno lo fa
2. **Incertezza esposta.** "430 ± 90 kcal · confidenza media" invece di "437 kcal". Vero, e disarma la critica principale alla categoria
3. **Stoviglie apprese in silenzio.** Un righello metrico passivo in ogni foto, costruito senza chiedere niente
4. **Cibo italiano.** CREA per gli alimenti, prodotti dei supermercati italiani, porzioni italiane. Nicchia difendibile da un dev solo

---

## 5. Il modello di precisione

### Il principio

Non serve rendere la foto precisa. Serve **toglierle il bias**.

Su 2.100 kcal/giorno con deficit target di 500:

- **Bias sistematico del 20%** = 420 kcal/giorno, ogni giorno, non si annulla mai → azzera il deficit, l'utente non dimagrisce e disinstalla
- **Rumore casuale ±30% a pasto** = ~137 kcal/giorno di incertezza sulla prima settimana, ~68 su un mese → irrilevante

Sono la stessa "imprecisione" nel linguaggio comune. Uno uccide il prodotto, l'altro no.

### Le cinque leve a zero attrito

| # | Leva | Come funziona |
|---|---|---|
| 1 | Ancoraggio metrico dai sensori | ARKit/ARCore danno piano del tavolo e altezza camera durante l'inquadratura; più focale EXIF e inclinazione giroscopio. Si ricava quanti cm è largo un pixel, senza che l'utente faccia nulla |
| 2 | Stoviglie apprese | Clustering dei piatti ricorrenti. Quando un piatto è visto ≥5 volte e almeno una foto aveva buon ancoraggio, il suo diametro reale è noto per sempre — e si applica **retroattivamente** allo storico |
| 3 | Prior personale | Dopo 3 settimane il modello non stima da zero: stima lo scostamento dall'abitudine dell'utente (la *sua* pasta è 115g, non 80g) |
| 4 | Multi-frame invisibile | 6-8 frame dal buffer nel secondo di inquadratura. Il micro-tremolio dà parallasse, quindi volume. Per l'utente è una foto sola |
| 5 | Uno swipe, non la bilancia | Slider pre-posizionato sulla stima: "più o meno?". In letteratura una minima descrizione porta l'errore dal 30% al 14% |

### Stack di errore atteso

| Configurazione | Errore per pasto |
|---|---|
| Foto singola, baseline | 30-35% |
| + ancoraggio metrico | ~22-25% |
| + stoviglie apprese | ~18-20% |
| + prior personale | ~15% |
| + swipe sulla porzione | ~12% |
| **+ correzione bias** | **bias settimanale ~3-5%** |

> I valori intermedi sono stime ragionate, non benchmark misurati. Primo e ultimo rigo sono ancorati alla letteratura. **Da validare con un set di test reale prima di usarli in comunicazione.**

### Ciò che la foto non può vedere

Olio nella padella (un cucchiaio = 120 kcal), zucchero nel caffè, cosa c'è sotto la superficie, densità del pane. Nessun modello le risolverà.

Ma sono **errori sistematici**: chi cucina con molto olio ci cucina sempre. Finiscono quindi dentro il bias personale e vengono assorbiti dalla correzione, senza mai doverli osservare. È questo che rende onesto il percorso "foto e basta".

### Avvertenza di identificabilità (importante in fase di implementazione)

`variazione peso = intake reale − TDEE reale`. Osservi l'intake *loggato* (distorto) e la variazione di peso. **Una equazione, due incognite**: non puoi separare l'errore sul TDEE dal bias di logging.

Conseguenze operative:

- Applica un **unico fattore correttivo combinato**. Funziona perfettamente a scopo predittivo
- **Non dire mai all'utente** "il tuo TDEE è X" o "sottostimi del Y%" come affermazioni separate: non sono identificabili e sarebbero false
- Separazione parziale possibile in fase 2: regredendo giorni a logging prevalentemente barcode (bias ≈ 0) contro giorni a logging prevalentemente foto (bias alto)

---

## 6. Architettura tecnica

### Stack

| Livello | Scelta |
|---|---|
| App | React Native + Expo (dev build, non Expo Go — servono moduli nativi camera/AR) |
| Backend | Supabase, **regione UE (Francoforte)** — obbligatorio, vedi §9 |
| AI visione | Gemini Flash con structured output JSON |
| Barcode | Open Food Facts + cache proprietaria + OCR etichetta |
| Alimenti base | CREA (tabelle composizione alimenti) |
| Pagamenti | RevenueCat (gestisce Apple + Google con un'integrazione sola) |
| Errori | Sentry |

### Pipeline di scansione

```
Foto (+ 6-8 frame buffer + metadati sensori)
  │
  ├─ 1. Gemini Flash → JSON strutturato
  │       alimenti[], volume stimato, confidenza per item
  │
  ├─ 2. Ancoraggio metrico
  │       AR plane/depth → stoviglia riconosciuta → oggetto noto → fallback S/M/L
  │
  ├─ 3. Volume → grammi
  │       tabella densità per categoria alimento
  │
  ├─ 4. Grammi → macro
  │       ⚠️ DATABASE DETERMINISTICO (CREA / OFF). MAI dall'LLM
  │
  ├─ 5. Prior personale + correzione bias utente
  │
  └─ 6. Output: stima + intervallo di confidenza + swipe di correzione
          └─ correzione utente → salvata come pasto ricorrente → prossima volta 1 tap, 0 chiamate AI
```

**Regola non negoziabile — punto 4.** L'LLM identifica l'alimento e stima la quantità. I valori nutrizionali vengono *sempre* da una tabella. Se lasci allucinare i macro, l'errore è invisibile, non riproducibile e irreparabile.

### Catena barcode (fallback a cascata)

| Livello | Fonte | Note |
|---|---|---|
| 1 | Cache proprietaria | Prodotti già risolti. Più veloce e più pertinente del DB globale |
| 2 | Open Food Facts | Gratis, API aperta, miglior copertura italiana fra i free. **Ma solo ~67% delle voci ha macro completi**, e in Italia la crescita è passata da ~112k prodotti aggiunti nel 2021 a ~12,5k nel 2025 |
| 3 | **OCR etichetta** | Barcode assente o incompleto → l'utente fotografa la tabella nutrizionale → Gemini la legge → salvi in cache → opzionale: contribuisci a OFF. Costo €0,003, 5 secondi, e trasforma il fallimento peggiore dell'app in acquisizione dati |
| 4 | API a pagamento | FatSecret Premier (>90% successo barcode, contratto commerciale) o Nutritionix (~$1.850/mese, fuori scala). **Non partire da qui**: misura il tasso di miss reale sul mercato italiano e valuta dopo |

Il livello 3 è il pezzo che quasi nessuno fa. Un vicolo cieco sul barcode è uno dei momenti in cui la gente disinstalla.

### Licenza ODbL — vincolo di schema

Open Food Facts è ODbL: **attribuzione** obbligatoria + **share-alike sul database derivato**. L'app in sé è "produced work" e le basta l'attribuzione; è il *database* derivato che va condiviso.

Progetta da subito con tabelle separate. Rifarlo dopo è un incubo:

**Zona ODbL (pubblicabile)**
- `off_products` — mirror OFF + correzioni proprie
- `food_items` — alimenti base da CREA
- `food_density` — densità per categoria

**Zona proprietaria (mai mescolata con la precedente)**
- `profiles` — dati utente, obiettivi, percorso scelto
- `meals`, `meal_items` — diario
- `photos` — riferimenti, vedi policy §9
- `tableware` — stoviglie apprese, per utente
- `user_food_priors` — porzioni abituali
- `weight_logs`
- `calibration` — fattore di bias personale, storico
- `saved_meals` — pasti ricorrenti

---

## 7. Flussi e schermate MVP

### Onboarding (biforcato)

1. Obiettivo → **dimagrire / mantenere / aumentare**
2. Biforcazione → **"mi alleno regolarmente" / "non mi alleno"**
   - Ramo atleta: tipo di sport, frequenza, focus sui macro (proteine in evidenza)
   - Ramo generale: linguaggio più semplice, kcal in evidenza, macro secondari
3. Dati: sesso, età, altezza, peso, % massa grassa (facoltativa)
4. Consenso esplicito dati sanitari (§9)
5. Primo pasto guidato — **entro 90 secondi dall'apertura**

> Il rischio del doppio target è un prodotto che non parla forte a nessuno. Mitigazione: la biforcazione cambia **linguaggio, gerarchia visiva e default**, non le funzionalità. Un solo prodotto, due voci.

### Schermate

| Schermata | Contenuto |
|---|---|
| **Diario** (home) | Giorno corrente, kcal rimanenti con intervallo, barre macro, lista pasti, FAB scansione |
| **Scansione** | Camera con cattura multi-frame e ancoraggio AR silenzioso |
| **Revisione scansione** | Alimenti riconosciuti, editabili, swipe porzione, confidenza esposta, salva come ricorrente |
| **Ricerca / barcode** | Scanner barcode, ricerca testuale, fallback OCR etichetta |
| **Pasti salvati** | I ricorrenti, log in 1 tap |
| **Progressi** | Trend peso, media mobile, aderenza, stato calibrazione |
| **Impostazioni** | Obiettivi, privacy e foto, modalità solo-macro, esportazione dati |

---

## 8. Calcoli nutrizionali

- **Metabolismo basale:** Mifflin-St Jeor di default; **Katch-McArdle** se l'utente fornisce la % di massa grassa (più accurato per il ramo atleta)
- **Fabbisogno:** BMR × fattore attività, con eventuale addendo per allenamento registrato manualmente
- **Adattivo:** dopo 14-21 giorni di dati, il fattore correttivo combinato (§5) sostituisce il moltiplicatore statico
- **Macro di default:** proteine 1,6-2,2 g/kg nel ramo atleta, 1,2-1,6 g/kg nel ramo generale; grassi ≥0,8 g/kg; carboidrati a saldo
- **Floor di sicurezza:** mai un target sotto il BMR stimato, e mai sotto 1.500 kcal (uomo) / 1.200 kcal (donna) — vedi §9

---

## 9. Legale, privacy, tutele

### GDPR — non è un dettaglio burocratico

Peso, obiettivi corporei e diario alimentare, trattati per finalità di salute, sono **dati particolari ex art. 9 GDPR**. Serve:

- **Consenso esplicito**, separato dai termini di servizio, granulare e revocabile
- **Supabase in regione UE** (Francoforte). Da impostare alla creazione del progetto: non si cambia dopo
- Informativa chiara sul fatto che le immagini transitano da Google (Gemini) — è un sub-responsabile e va dichiarato
- Esportazione e cancellazione dati funzionanti dal giorno uno, non "da aggiungere poi"

### Policy sulle foto — decisione di prodotto, non solo legale

**Le foto vengono cancellate subito dopo l'elaborazione, di default.** Conservate solo se l'utente sceglie attivamente di tenerle.

Motivazioni: abbatte la superficie di rischio (Cal AI: breach su 3,2M utenti), riduce i costi di storage, semplifica il GDPR, ed è un **claim di marketing sincero** in una categoria che ha appena perso credibilità sul punto.

### Guardrail sui disturbi alimentari

La categoria ha un problema documentato e la foto lo amplifica. Non è solo etica: è rischio di rimozione dagli store e di danno reputazionale.

- Floor calorico invalicabile (sopra)
- Nessuno streak punitivo, nessun linguaggio di colpa, nessun "hai sforato"
- **Modalità solo-macro**: nasconde completamente le calorie
- La pesata per la calibrazione è **facoltativa e senza pressione**: proposta come "vuoi che l'app impari a correggersi?", mai come obbligo quotidiano
- Nessun commento sul BMI, nessun confronto sociale
- Target estremi → messaggio che rimanda a un professionista
- Valutare rating 18+ o gate all'età in onboarding

### Altro

- Nessun consiglio dietetico personalizzato generato dall'AI: è terreno di esercizio abusivo di professione sanitaria. L'app misura, non prescrive
- Attribuzione Open Food Facts visibile in app (§6)

---

## 10. Monetizzazione

**Struttura, contro-intuitiva ma migliore del solito "3 scansioni gratis":**

- **Gratis illimitato:** logging manuale, barcode, pasti salvati, diario, progressi
- **A pagamento:** scansione foto AI oltre N a settimana, correzione bias, stoviglie apprese, storico esteso

L'app resta *realmente utile* a chi non paga — che è ciò che genera retention e passaparola — e si paga per la comodità, non per l'accesso.

**Prezzo:** ~€24,99/anno o €3,99/mese, allineato al prezzo di categoria ($29/anno di Cal AI). Il mercato italiano è sensibile al prezzo: non provare a stare sopra. Trial reale, senza carta anticipata se possibile — è esattamente il punto su cui Cal AI è stata rimossa dall'App Store.

### Economia unitaria

| Voce | Valore |
|---|---|
| Costo per scansione (Gemini Flash, ~1.500 token in / 500 out) | ~€0,003 |
| 3 pasti/giorno, 30 giorni | ~€0,27/mese |
| Con cache pasti ricorrenti (80% dei log a regime) | **< €0,10/mese** |
| Ricavo netto a €24,99/anno, tolto il 30% store | ~€1,45/mese |

Il margine regge ampiamente. **Il vero costo non è l'AI, è l'acquisizione utenti.** Cal AI ha vinto con TikTok, non con la tecnologia.

---

## 11. Roadmap

Full-time, ~12 settimane a beta pubblicabile.

| Fase | Settimane | Contenuto | Perché in questo ordine |
|---|---|---|---|
| **0 — Fondamenta** | 1 | Auth, schema DB con separazione ODbL, profilo, TDEE, diario manuale | Senza questo non esiste il prodotto. Zero AI |
| **1 — Barcode** | 2-3 | OFF + cache + OCR etichetta | È il **percorso ad alta precisione** (1-3% di errore). Va prima della foto |
| **2 — Foto** | 4-5 | Gemini structured output, revisione, swipe porzione, S/M/L | Il gancio. Già a questo livello sei alla pari con metà del mercato |
| **3 — Ricorrenti** | 6-7 | Pasti salvati, prior personale | Insieme cost-saver e principale driver di retention |
| **4 — Ancoraggio** | 8-10 | AR metrico iOS+Android, stoviglie apprese | La parte difficile e rischiosa. Isolata e opzionale per costruzione |
| **5 — Calibrazione** | 11 | Correzione bias, progressi, intervalli di confidenza | La feature-firma |
| **6 — Lancio** | 12 | Paywall RevenueCat, store listing, **scelta del nome**, beta chiusa | |
| **7 — Assistente** | post-lancio | Assistente AI con nome e personalità: dagli ingredienti che hai in casa propone cosa cucinare, tenendo conto di cosa hai già mangiato oggi e di quanto ti manca | Vedi sotto |

### Fase 7 — perché vale, e a quali condizioni

Tutte le app di calorie hanno lo stesso difetto fatale: **sono solo input**. L'utente dà, l'app prende, non restituisce niente. È la causa principale dell'abbandono.

Un assistente che dice *"hai questo in frigo e ti mancano 40g di proteine — ecco cosa cucinare"* ribalta il rapporto e usa dati che possiede **solo** questa app: cosa hai già mangiato oggi e quanto ti resta. È un motivo per aprire l'app *quando non stai loggando*, cioè la risposta al problema di retention dell'intera categoria.

Tre vincoli non negoziabili:

- **Mai nell'MVP.** È un moltiplicatore su un prodotto che funziona, non un modo per farlo funzionare
- **Costo da contingentare.** La chat è a turni illimitati: costa molto più della scansione, che è bounded. Serve un tetto per utente
- **Propone, non prescrive.** Suggerire ricette è lecito; il consiglio dietetico personalizzato è terreno di professione sanitaria regolamentata (§9)

**Misura presto:** il tasso di miss reale del barcode sul mercato italiano va misurato in fase 1. È il dato che decide se in futuro serve un'API a pagamento.

### Kill list — da non costruire

Feed social · gamification a badge · integrazione smartwatch · micronutrienti completi · idratazione · condivisione pasti · widget · tema scuro personalizzabile · community

> Nota: l'assistente per le ricette era inizialmente in questa lista. È stato **promosso a fase 7** (post-lancio) per le ragioni sopra. Resta fuori dall'MVP.

---

## 12. Metriche di successo

| Metrica | Target | Perché conta |
|---|---|---|
| Tempo per loggare un pasto | < 15 secondi | È l'unica ragione per cui le app di calorie vengono abbandonate |
| Retention D7 / D30 | > 40% / > 20% | Sopra la media di categoria |
| % log serviti dalla cache | > 70% a 3 settimane | Insieme proxy di costo e di abitudine |
| Tasso di miss barcode (Italia) | < 15% | Decide l'eventuale acquisto di un'API |
| Utenti con bias calibrato a 21 giorni | > 30% | Verifica che il differenziatore principale sia adottato |

---

## 13. Registro rischi

| # | Rischio | Gravità | Mitigazione |
|---|---|---|---|
| 1 | **Camera/AR cross-platform** — il pezzo che non si scrive una volta sola | Alta | Interfaccia unica, implementazione per piattaforma, fallback senza ancoraggio che deve bastare da solo. Fase 4, mai nel percorso critico |
| 2 | **Copertura barcode italiana** sconosciuta | Alta | Misurare in fase 1. OCR etichetta come rete di sicurezza sempre presente |
| 3 | **Adozione bassa della pesata** → niente calibrazione | Media | Il valore dell'app non deve dipenderne. La correzione è un bonus, non il prodotto |
| 4 | **Acquisizione utenti** — il muro vero | Alta | Da affrontare come progetto a sé, non come coda dello sviluppo |
| 5 | **Doppio target che diluisce** | Media | La biforcazione cambia linguaggio e default, non funzionalità |
| 6 | **Rischio DCA / rimozione store** | Media | Guardrail §9 progettati dentro, non aggiunti dopo |
| 7 | Dipendenza da Gemini (prezzo, disponibilità) | Bassa | Astrazione del provider di visione dietro un'interfaccia |

---

## 14. Prossime decisioni aperte

1. **Nome** — scelta e verifica disponibilità su store, dominio, marchio
2. **Set di test di precisione** — 50-100 pasti reali fotografati e pesati, per validare lo stack di §5 prima di comunicarlo
3. **Numero N** di scansioni AI gratuite a settimana
4. **Identità visiva** — direzione grafica, tono di voce per i due rami
5. Se attivare la contribuzione automatica dei dati OCR a Open Food Facts

---

## Fonti

- [Can We Use AI To Accurately Track Calories with A Picture? — Biolayne](https://biolayne.com/reps/issue-44/can-we-use-ai-to-accurately-track-calories-with-a-picture/)
- [The accuracy of portion size estimation using food images — PMC](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9291996/)
- [Cal AI Revenue 2026 — Latka](https://getlatka.com/companies/calai.app)
- [MyFitnessPal has acquired Cal AI — TechCrunch](https://techcrunch.com/2026/03/02/myfitnesspal-has-acquired-cal-ai-the-viral-calorie-app-built-by-teens/)
- [Dati, API e SDK — Open Food Facts](https://it.openfoodfacts.org/data)
- [Terms of use, contribution and re-use — Open Food Facts](https://world.openfoodfacts.org/terms-of-use)
- [Evoluzione del numero di prodotti in Italia — Open Food Facts](https://it.openfoodfacts.org/product-count)
- [Open Nutrition Datasets Compared — Nutrola](https://nutrola.app/en/blog/open-nutrition-datasets-compared-usda-openfoodfacts-nutrola)
- [fatsecret Platform API](https://platform.fatsecret.com/platform-api)
- [Top 8 Nutrition APIs in 2026 — YMove](https://ymove.app/nutrition-api/top-nutrition-apis)
- [Tabelle di composizione degli alimenti — CREA](https://www.crea.gov.it/en/web/alimenti-e-nutrizione/tabelle-di-composizione-degli-alimenti)
- [Gemini API Pricing 2026 — Morph](https://www.morphllm.com/gemini-api-pricing)
