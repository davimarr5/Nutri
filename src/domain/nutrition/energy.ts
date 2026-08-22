import type { ActivityLevel, BodyProfile } from './types';

/**
 * Moltiplicatori di attività.
 *
 * Sono un punto di partenza, non una verità: la letteratura riporta errori
 * del 15-20% sul singolo individuo. Vengono sostituiti dalla calibrazione
 * adattiva (calibration.ts) appena ci sono abbastanza dati reali.
 */
export const ACTIVITY_FACTORS: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  high: 1.725,
  athlete: 1.9,
};

/**
 * Massa magra. Richiede la percentuale di massa grassa.
 */
export function leanBodyMassKg(weightKg: number, bodyFatPct: number): number {
  return weightKg * (1 - bodyFatPct / 100);
}

/**
 * Mifflin-St Jeor — lo standard per la popolazione generale.
 * Più accurata di Harris-Benedict, che sovrastima soprattutto nei soggetti
 * in sovrappeso.
 */
export function bmrMifflinStJeor(p: BodyProfile): number {
  const base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.ageYears;
  return p.sex === 'male' ? base + 5 : base - 161;
}

/**
 * Katch-McArdle — basata sulla massa magra, quindi indifferente al sesso.
 * Più accurata di Mifflin nei soggetti allenati, dove la composizione
 * corporea si discosta dalla media su cui Mifflin è tarata.
 */
export function bmrKatchMcArdle(weightKg: number, bodyFatPct: number): number {
  return 370 + 21.6 * leanBodyMassKg(weightKg, bodyFatPct);
}

export interface BmrResult {
  kcal: number;
  formula: 'mifflin-st-jeor' | 'katch-mcardle';
}

/**
 * Sceglie la formula migliore in base ai dati disponibili.
 *
 * La percentuale di massa grassa auto-riferita è spesso molto imprecisa:
 * fuori da un intervallo plausibile viene ignorata e si torna a Mifflin,
 * che sbaglia meno di una Katch-McArdle alimentata con un dato inventato.
 */
export function basalMetabolicRate(p: BodyProfile): BmrResult {
  const bf = p.bodyFatPct;
  const usable = bf !== undefined && bf >= 3 && bf <= 60;

  return usable
    ? { kcal: bmrKatchMcArdle(p.weightKg, bf), formula: 'katch-mcardle' }
    : { kcal: bmrMifflinStJeor(p), formula: 'mifflin-st-jeor' };
}

/**
 * Dispendio energetico totale stimato.
 *
 * `calibrationFactor` è il correttivo combinato prodotto da calibration.ts.
 * Vedi lì l'avvertenza sull'identificabilità: non è "quanto sbaglia il TDEE"
 * né "quanto sottostima l'utente", ma la composizione inseparabile dei due.
 */
export function totalDailyEnergyExpenditure(
  p: BodyProfile,
  activity: ActivityLevel,
): number {
  return basalMetabolicRate(p).kcal * ACTIVITY_FACTORS[activity];
}
