import { KCAL_PER_KG_BODY_MASS } from './types';

/**
 * CALIBRAZIONE DEL BIAS — la feature-firma dell'app.
 *
 * ─── L'avvertenza che va letta prima di toccare questo file ───────────────
 *
 *   variazione peso = intake reale − TDEE reale
 *
 * Noi osserviamo l'intake LOGGATO (distorto) e la variazione di peso.
 * Una equazione, due incognite: l'errore di logging e l'errore sul TDEE
 * NON sono separabili.
 *
 * Conseguenze operative, non negoziabili:
 *
 *   • Si stima un solo fattore combinato. A scopo PREDITTIVO funziona
 *     perfettamente: è tutto ciò che serve per impostare il target.
 *   • Non dire MAI all'utente "il tuo TDEE è X" o "sottostimi del Y%" come
 *     affermazioni separate. Non sono identificabili, sarebbero false.
 *   • Il messaggio corretto è: "abbiamo imparato quanto correggerti".
 *
 * Separazione parziale possibile in futuro: regredendo i giorni a logging
 * prevalentemente barcode (bias ≈ 0) contro i giorni a logging fotografico.
 * Vedi la vista daily_totals, colonne precise_count / photo_count.
 * ──────────────────────────────────────────────────────────────────────────
 */

/** Giorni minimi di logging prima di tentare una calibrazione. */
export const MIN_WINDOW_DAYS = 14;
/** Pesate minime nella finestra. Sotto questa soglia il trend è rumore. */
export const MIN_WEIGHT_POINTS = 8;
/** Oltre questi limiti non è bias: è un dato sbagliato. */
export const FACTOR_MIN = 0.8;
export const FACTOR_MAX = 1.6;

export interface WeightPoint {
  /** Giorni trascorsi dall'inizio della finestra. */
  dayIndex: number;
  weightKg: number;
}

export interface CalibrationInput {
  weightPoints: WeightPoint[];
  /** Media delle kcal loggate nella finestra. */
  loggedMeanKcal: number;
  /** TDEE stimato dalle formule, prima di qualunque correzione. */
  estimatedTdeeKcal: number;
  windowDays: number;
}

export type CalibrationResult =
  | {
      ok: true;
      /** Fattore moltiplicativo combinato da applicare all'intake loggato. */
      factor: number;
      slopeKgPerDay: number;
      rSquared: number;
      weightPoints: number;
      clamped: boolean;
    }
  | {
      ok: false;
      reason:
        | 'not-enough-days'
        | 'not-enough-weight-points'
        | 'no-weight-variation'
        | 'implausible-logged-intake';
    };

/**
 * Regressione lineare ai minimi quadrati.
 * Restituisce pendenza, intercetta e R².
 */
export function linearRegression(
  points: ReadonlyArray<{ x: number; y: number }>,
): { slope: number; intercept: number; rSquared: number } {
  const n = points.length;
  const meanX = points.reduce((s, p) => s + p.x, 0) / n;
  const meanY = points.reduce((s, p) => s + p.y, 0) / n;

  let sxy = 0;
  let sxx = 0;
  for (const p of points) {
    sxy += (p.x - meanX) * (p.y - meanY);
    sxx += (p.x - meanX) ** 2;
  }

  const slope = sxx === 0 ? 0 : sxy / sxx;
  const intercept = meanY - slope * meanX;

  let ssRes = 0;
  let ssTot = 0;
  for (const p of points) {
    const predicted = slope * p.x + intercept;
    ssRes += (p.y - predicted) ** 2;
    ssTot += (p.y - meanY) ** 2;
  }

  const rSquared = ssTot === 0 ? 0 : 1 - ssRes / ssTot;
  return { slope, intercept, rSquared };
}

/**
 * Stima il fattore correttivo combinato.
 *
 *   intake reale ≈ factor × intake loggato
 *
 * Derivazione, tenendo il TDEE stimato come riferimento fisso:
 *
 *   factor × loggedMean − TDEE = slope × 7700
 *   factor = (TDEE + slope × 7700) / loggedMean
 *
 * Il TDEE è tenuto fisso non perché sia giusto, ma perché serve un punto di
 * ancoraggio per rendere il sistema risolvibile. Vedi l'avvertenza in testa.
 */
export function computeCalibration(
  input: CalibrationInput,
): CalibrationResult {
  if (input.windowDays < MIN_WINDOW_DAYS) {
    return { ok: false, reason: 'not-enough-days' };
  }
  if (input.weightPoints.length < MIN_WEIGHT_POINTS) {
    return { ok: false, reason: 'not-enough-weight-points' };
  }
  if (input.loggedMeanKcal < 500) {
    // Logging troppo lacunoso: correggere su questi dati peggiorerebbe le cose.
    return { ok: false, reason: 'implausible-logged-intake' };
  }

  const regression = linearRegression(
    input.weightPoints.map((p) => ({ x: p.dayIndex, y: p.weightKg })),
  );

  if (!Number.isFinite(regression.slope)) {
    return { ok: false, reason: 'no-weight-variation' };
  }

  const impliedBalance = regression.slope * KCAL_PER_KG_BODY_MASS;
  const raw = (input.estimatedTdeeKcal + impliedBalance) / input.loggedMeanKcal;

  const factor = Math.min(FACTOR_MAX, Math.max(FACTOR_MIN, raw));

  return {
    ok: true,
    factor: Math.round(factor * 1000) / 1000,
    slopeKgPerDay: regression.slope,
    rSquared: Math.round(regression.rSquared * 1000) / 1000,
    weightPoints: input.weightPoints.length,
    clamped: factor !== raw,
  };
}

/**
 * Testo da mostrare all'utente. Volutamente non scompone il fattore nelle
 * sue componenti, e non usa mai un linguaggio di colpa.
 */
export function describeCalibration(result: CalibrationResult): string {
  if (!result.ok) {
    switch (result.reason) {
      case 'not-enough-days':
        return 'Continua a registrare: servono almeno due settimane di dati.';
      case 'not-enough-weight-points':
        return 'Servono qualche pesata in più per capire come correggerci.';
      case 'no-weight-variation':
        return 'Non riusciamo ancora a leggere un andamento chiaro.';
      case 'implausible-logged-intake':
        return 'I dati registrati sono troppo pochi per una correzione affidabile.';
    }
  }

  if (Math.abs(result.factor - 1) < 0.05) {
    return 'Le nostre stime sono già in linea con i tuoi risultati.';
  }

  const pct = Math.round(Math.abs(result.factor - 1) * 100);
  return result.factor > 1
    ? `Abbiamo imparato a correggere le stime verso l'alto di circa il ${pct}%.`
    : `Abbiamo imparato a correggere le stime verso il basso di circa il ${pct}%.`;
}
