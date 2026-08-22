import { ACTIVITY_FACTORS, basalMetabolicRate, leanBodyMassKg } from './energy';
import {
  KCAL_PER_KG_BODY_MASS,
  type ActivityLevel,
  type BodyProfile,
  type Branch,
  type EnergyTargets,
  type Goal,
} from './types';

/**
 * GUARDRAIL DISTURBI ALIMENTARI — §9 del brief.
 *
 * Questi limiti non sono configurabili e non sono aggirabili dalla UI.
 * Non è una scelta di prodotto: è la differenza fra un'app che misura e
 * un'app che fa danni. Serve anche a non farsi rimuovere dagli store.
 */
export const ABSOLUTE_KCAL_FLOOR: Record<'male' | 'female', number> = {
  male: 1500,
  female: 1200,
};

/** Ritmo massimo di perdita consentito, kg/settimana. */
export const MAX_LOSS_RATE_KG_WEEK = 1.0;
/** Ritmo massimo di aumento consentito, kg/settimana. */
export const MAX_GAIN_RATE_KG_WEEK = 0.5;

const KCAL_PER_G = { protein: 4, carb: 4, fat: 9 } as const;

/**
 * Proteine in g per kg di peso corporeo, quando la massa grassa NON è nota.
 * Valori dentro gli intervalli ISSN. Più alte in deficit, dove il rischio è
 * la perdita di massa magra.
 */
const PROTEIN_PER_KG_BW: Record<Branch, Record<Goal, number>> = {
  athlete: { lose: 2.2, maintain: 1.8, gain: 1.8 },
  general: { lose: 1.6, maintain: 1.4, gain: 1.4 },
};

/**
 * Proteine in g per kg di MASSA MAGRA, quando la massa grassa è nota.
 * Più corretto: nei soggetti con molta massa grassa, calcolare sul peso
 * totale porta a target proteici inutilmente alti e difficili da rispettare.
 */
const PROTEIN_PER_KG_LBM: Record<Branch, Record<Goal, number>> = {
  athlete: { lose: 2.6, maintain: 2.2, gain: 2.2 },
  general: { lose: 2.0, maintain: 1.8, gain: 1.8 },
};

/** Minimo di grassi per kg di peso corporeo — soglia di salute ormonale. */
const MIN_FAT_PER_KG_BW = 0.8;

export interface TargetInput {
  profile: BodyProfile;
  activity: ActivityLevel;
  branch: Branch;
  goal: Goal;
  /**
   * Ritmo desiderato in kg/settimana. Negativo per perdere.
   * Viene comunque limitato dai guardrail.
   */
  rateKgPerWeek: number;
  /**
   * Correttivo combinato da calibration.ts. 1 = nessuna correzione.
   * Divide il target: se l'utente logga sistematicamente il 20% in meno
   * (factor 1.2), il target loggato deve essere più basso di conseguenza.
   */
  calibrationFactor?: number;
}

export function clampRate(goal: Goal, rateKgPerWeek: number): number {
  if (goal === 'maintain') return 0;
  if (goal === 'lose') {
    return Math.max(-MAX_LOSS_RATE_KG_WEEK, Math.min(0, rateKgPerWeek));
  }
  return Math.min(MAX_GAIN_RATE_KG_WEEK, Math.max(0, rateKgPerWeek));
}

/**
 * Ripartizione dei macro a partire da un target calorico.
 *
 * Ordine di priorità: proteine, poi grassi al minimo di salute, carboidrati
 * a saldo. Se il target è così basso che proteine + grassi lo saturano,
 * entrambi vengono ridotti in proporzione invece di produrre carboidrati
 * negativi.
 */
export function distributeMacros(
  kcal: number,
  profile: BodyProfile,
  branch: Branch,
  goal: Goal,
) {
  const bf = profile.bodyFatPct;
  const useLbm = bf !== undefined && bf >= 3 && bf <= 60;

  const proteinG = useLbm
    ? PROTEIN_PER_KG_LBM[branch][goal] * leanBodyMassKg(profile.weightKg, bf)
    : PROTEIN_PER_KG_BW[branch][goal] * profile.weightKg;

  const fatG = MIN_FAT_PER_KG_BW * profile.weightKg;

  let p = proteinG;
  let f = fatG;

  const floorKcal = p * KCAL_PER_G.protein + f * KCAL_PER_G.fat;

  if (floorKcal > kcal) {
    // Target molto basso: comprimi proteine e grassi in proporzione
    // invece di restituire carboidrati negativi.
    const scale = kcal / floorKcal;
    p *= scale;
    f *= scale;
  }

  const remainingKcal =
    kcal - (p * KCAL_PER_G.protein + f * KCAL_PER_G.fat);
  const carbG = Math.max(0, remainingKcal / KCAL_PER_G.carb);

  return {
    proteinG: round(p),
    fatG: round(f),
    carbG: round(carbG),
  };
}

/**
 * Calcola i target giornalieri completi, guardrail inclusi.
 */
export function computeTargets(input: TargetInput): EnergyTargets {
  const { profile, activity, branch, goal } = input;

  const bmr = basalMetabolicRate(profile);
  const tdee = bmr.kcal * ACTIVITY_FACTORS[activity];

  const rate = clampRate(goal, input.rateKgPerWeek);
  const dailyDelta = (rate * KCAL_PER_KG_BODY_MASS) / 7;

  let kcal = tdee + dailyDelta;

  // --- Guardrail, in ordine di severità ---------------------------------
  let floorApplied = false;
  let floorReason: EnergyTargets['floorReason'];

  if (kcal < bmr.kcal) {
    kcal = bmr.kcal;
    floorApplied = true;
    floorReason = 'below-bmr';
  }

  const absolute = ABSOLUTE_KCAL_FLOOR[profile.sex];
  if (kcal < absolute) {
    kcal = absolute;
    floorApplied = true;
    floorReason = 'below-absolute-minimum';
  }

  // --- Correttivo di calibrazione ---------------------------------------
  // Applicato DOPO i guardrail e volutamente non soggetto ad essi:
  // corregge quanto l'utente deve *loggare*, non quanto deve mangiare.
  const factor = input.calibrationFactor ?? 1;
  const loggedKcal = kcal / factor;

  const macros = distributeMacros(loggedKcal, profile, branch, goal);

  return {
    kcal: round(loggedKcal),
    tdeeKcal: round(tdee),
    bmrKcal: round(bmr.kcal),
    bmrFormula: bmr.formula,
    floorApplied,
    floorReason,
    ...macros,
  };
}

function round(n: number): number {
  return Math.round(n * 10) / 10;
}
