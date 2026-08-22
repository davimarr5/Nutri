export type Sex = 'male' | 'female';
export type Branch = 'athlete' | 'general';
export type Goal = 'lose' | 'maintain' | 'gain';

export type ActivityLevel =
  | 'sedentary'
  | 'light'
  | 'moderate'
  | 'high'
  | 'athlete';

export interface BodyProfile {
  sex: Sex;
  ageYears: number;
  heightCm: number;
  weightKg: number;
  /** Percentuale di massa grassa, se nota. Abilita Katch-McArdle. */
  bodyFatPct?: number;
}

export interface Macros {
  proteinG: number;
  carbG: number;
  fatG: number;
}

export interface EnergyTargets extends Macros {
  kcal: number;
  /** TDEE stimato prima dell'applicazione dell'obiettivo. */
  tdeeKcal: number;
  bmrKcal: number;
  /** Formula effettivamente usata per il metabolismo basale. */
  bmrFormula: 'mifflin-st-jeor' | 'katch-mcardle';
  /**
   * True se il target calorico è stato alzato da un guardrail di sicurezza
   * invece che dall'obiettivo scelto. La UI deve dirlo all'utente.
   */
  floorApplied: boolean;
  floorReason?: 'below-bmr' | 'below-absolute-minimum';
}

/** Costante energetica del tessuto corporeo, kcal per kg. */
export const KCAL_PER_KG_BODY_MASS = 7700;
