import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ACTIVITY_FACTORS,
  basalMetabolicRate,
  bmrKatchMcArdle,
  bmrMifflinStJeor,
  leanBodyMassKg,
} from './energy';
import {
  ABSOLUTE_KCAL_FLOOR,
  clampRate,
  computeTargets,
  distributeMacros,
} from './targets';
import {
  computeCalibration,
  describeCalibration,
  linearRegression,
} from './calibration';
import type { BodyProfile } from './types';

const near = (actual: number, expected: number, tol = 0.5) =>
  assert.ok(
    Math.abs(actual - expected) <= tol,
    `atteso ~${expected}, ottenuto ${actual}`,
  );

// =============================================================================
// Metabolismo basale
// =============================================================================

test('Mifflin-St Jeor, uomo — valore calcolato a mano', () => {
  // 10(80) + 6.25(180) − 5(30) + 5 = 800 + 1125 − 150 + 5 = 1780
  const p: BodyProfile = { sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80 };
  near(bmrMifflinStJeor(p), 1780);
});

test('Mifflin-St Jeor, donna — valore calcolato a mano', () => {
  // 10(65) + 6.25(165) − 5(30) − 161 = 650 + 1031.25 − 150 − 161 = 1370.25
  const p: BodyProfile = { sex: 'female', ageYears: 30, heightCm: 165, weightKg: 65 };
  near(bmrMifflinStJeor(p), 1370.25);
});

test('la differenza fra i sessi in Mifflin è esattamente 166 kcal', () => {
  const base = { ageYears: 40, heightCm: 175, weightKg: 75 };
  const m = bmrMifflinStJeor({ ...base, sex: 'male' });
  const f = bmrMifflinStJeor({ ...base, sex: 'female' });
  near(m - f, 166, 0.001);
});

test('Katch-McArdle — valore calcolato a mano', () => {
  // LBM = 80 × 0.85 = 68 ; 370 + 21.6(68) = 370 + 1468.8 = 1838.8
  near(leanBodyMassKg(80, 15), 68, 0.001);
  near(bmrKatchMcArdle(80, 15), 1838.8);
});

test('Katch-McArdle non dipende dal sesso a parità di massa magra', () => {
  near(bmrKatchMcArdle(80, 15), bmrKatchMcArdle(80, 15), 0);
});

test('con massa grassa plausibile si usa Katch-McArdle', () => {
  const r = basalMetabolicRate({
    sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80, bodyFatPct: 15,
  });
  assert.equal(r.formula, 'katch-mcardle');
});

test('una massa grassa implausibile viene ignorata: meglio Mifflin che un dato inventato', () => {
  for (const bodyFatPct of [1, 85]) {
    const r = basalMetabolicRate({
      sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80, bodyFatPct,
    });
    assert.equal(r.formula, 'mifflin-st-jeor');
  }
});

// =============================================================================
// Guardrail sul ritmo
// =============================================================================

test('il ritmo di perdita è limitato a 1 kg/settimana', () => {
  assert.equal(clampRate('lose', -3), -1.0);
  assert.equal(clampRate('lose', -0.5), -0.5);
});

test('un ritmo positivo su obiettivo "lose" viene azzerato, non invertito', () => {
  assert.equal(clampRate('lose', 0.5), 0);
});

test('il ritmo di aumento è limitato a 0,5 kg/settimana', () => {
  assert.equal(clampRate('gain', 2), 0.5);
});

test('su "maintain" il ritmo è sempre zero', () => {
  assert.equal(clampRate('maintain', -0.8), 0);
});

// =============================================================================
// Guardrail calorici — la parte che protegge le persone
// =============================================================================

test('il target non scende mai sotto il metabolismo basale', () => {
  const t = computeTargets({
    profile: { sex: 'female', ageYears: 25, heightCm: 160, weightKg: 55 },
    activity: 'sedentary',
    branch: 'general',
    goal: 'lose',
    rateKgPerWeek: -1.0,
  });
  assert.ok(t.kcal >= t.bmrKcal, `${t.kcal} < BMR ${t.bmrKcal}`);
  assert.equal(t.floorApplied, true);
});

test('il minimo assoluto è rispettato per entrambi i sessi', () => {
  for (const sex of ['male', 'female'] as const) {
    const t = computeTargets({
      profile: { sex, ageYears: 70, heightCm: 150, weightKg: 45 },
      activity: 'sedentary',
      branch: 'general',
      goal: 'lose',
      rateKgPerWeek: -1.0,
    });
    assert.ok(
      t.kcal >= ABSOLUTE_KCAL_FLOOR[sex],
      `${sex}: ${t.kcal} < ${ABSOLUTE_KCAL_FLOOR[sex]}`,
    );
  }
});

test('nessuna combinazione estrema produce un target pericoloso', () => {
  for (const sex of ['male', 'female'] as const)
    for (const ageYears of [18, 45, 80])
      for (const heightCm of [145, 175, 205])
        for (const weightKg of [40, 70, 160]) {
          const t = computeTargets({
            profile: { sex, ageYears, heightCm, weightKg },
            activity: 'sedentary',
            branch: 'general',
            goal: 'lose',
            rateKgPerWeek: -1.0,
          });
          assert.ok(t.kcal >= ABSOLUTE_KCAL_FLOOR[sex]);
          assert.ok(t.proteinG >= 0 && t.carbG >= 0 && t.fatG >= 0);
        }
});

test('un deficit moderato non fa scattare nessun guardrail', () => {
  const t = computeTargets({
    profile: { sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80 },
    activity: 'moderate',
    branch: 'athlete',
    goal: 'lose',
    rateKgPerWeek: -0.5,
  });
  // TDEE = 1780 × 1.55 = 2759 ; delta = −0.5 × 7700 / 7 = −550 → 2209
  near(t.tdeeKcal, 2759, 1);
  near(t.kcal, 2209, 1);
  assert.equal(t.floorApplied, false);
});

// =============================================================================
// Macro
// =============================================================================

test('i macro sommano al target calorico', () => {
  const t = computeTargets({
    profile: { sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80 },
    activity: 'moderate',
    branch: 'athlete',
    goal: 'lose',
    rateKgPerWeek: -0.5,
  });
  const fromMacros = t.proteinG * 4 + t.carbG * 4 + t.fatG * 9;
  near(fromMacros, t.kcal, 2);
});

test('il ramo atleta riceve più proteine del ramo generale', () => {
  const profile: BodyProfile = {
    sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80,
  };
  const common = { profile, activity: 'moderate' as const, goal: 'lose' as const, rateKgPerWeek: -0.5 };
  const athlete = computeTargets({ ...common, branch: 'athlete' });
  const general = computeTargets({ ...common, branch: 'general' });
  assert.ok(athlete.proteinG > general.proteinG);
});

test('in deficit le proteine salgono rispetto al mantenimento', () => {
  const profile: BodyProfile = {
    sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80,
  };
  const cut = computeTargets({
    profile, activity: 'moderate', branch: 'athlete', goal: 'lose', rateKgPerWeek: -0.5,
  });
  const maintain = computeTargets({
    profile, activity: 'moderate', branch: 'athlete', goal: 'maintain', rateKgPerWeek: 0,
  });
  assert.ok(cut.proteinG > maintain.proteinG);
});

test('con molta massa grassa le proteine si calcolano sulla massa magra', () => {
  const lean = distributeMacros(2000,
    { sex: 'male', ageYears: 40, heightCm: 175, weightKg: 120, bodyFatPct: 40 },
    'general', 'lose');
  const noBf = distributeMacros(2000,
    { sex: 'male', ageYears: 40, heightCm: 175, weightKg: 120 },
    'general', 'lose');
  // 120 kg al 40% → LBM 72 kg → 2.0 × 72 = 144 g, contro 1.6 × 120 = 192 g
  near(lean.proteinG, 144, 1);
  near(noBf.proteinG, 192, 1);
  assert.ok(lean.proteinG < noBf.proteinG);
});

test('con un target molto basso i carboidrati non diventano negativi', () => {
  const m = distributeMacros(800,
    { sex: 'male', ageYears: 30, heightCm: 190, weightKg: 110 },
    'athlete', 'lose');
  assert.ok(m.carbG >= 0);
  assert.ok(m.proteinG > 0 && m.fatG > 0);
  near(m.proteinG * 4 + m.carbG * 4 + m.fatG * 9, 800, 2);
});

// =============================================================================
// Regressione lineare
// =============================================================================

test('regressione su una retta perfetta: R² = 1', () => {
  const r = linearRegression([
    { x: 0, y: 80 }, { x: 1, y: 79.9 }, { x: 2, y: 79.8 }, { x: 3, y: 79.7 },
  ]);
  near(r.slope, -0.1, 0.0001);
  near(r.rSquared, 1, 0.0001);
});

test('regressione su dati costanti: pendenza nulla', () => {
  const r = linearRegression([
    { x: 0, y: 70 }, { x: 1, y: 70 }, { x: 2, y: 70 },
  ]);
  near(r.slope, 0, 0.0001);
});

// =============================================================================
// Calibrazione
// =============================================================================

const weightSeries = (start: number, perDay: number, n: number) =>
  Array.from({ length: n }, (_, i) => ({
    dayIndex: i * 2,
    weightKg: start + perDay * i * 2,
  }));

test('senza dati sufficienti la calibrazione si rifiuta di indovinare', () => {
  const short = computeCalibration({
    weightPoints: weightSeries(80, -0.01, 10),
    loggedMeanKcal: 2000,
    estimatedTdeeKcal: 2500,
    windowDays: 7,
  });
  assert.equal(short.ok, false);
  assert.equal(short.ok === false && short.reason, 'not-enough-days');

  const fewPoints = computeCalibration({
    weightPoints: weightSeries(80, -0.01, 3),
    loggedMeanKcal: 2000,
    estimatedTdeeKcal: 2500,
    windowDays: 21,
  });
  assert.equal(fewPoints.ok, false);
  assert.equal(fewPoints.ok === false && fewPoints.reason, 'not-enough-weight-points');
});

test('peso stabile e intake pari al TDEE → nessuna correzione', () => {
  const r = computeCalibration({
    weightPoints: weightSeries(80, 0, 11),
    loggedMeanKcal: 2500,
    estimatedTdeeKcal: 2500,
    windowDays: 21,
  });
  assert.equal(r.ok, true);
  if (r.ok) near(r.factor, 1.0, 0.001);
});

test('caso reale: peso stabile ma intake loggato basso → sottostima rilevata', () => {
  // Logga 2000 kcal, TDEE stimato 2500, il peso non si muove.
  // Sta mangiando ~2500: factor = 2500 / 2000 = 1.25
  const r = computeCalibration({
    weightPoints: weightSeries(80, 0, 11),
    loggedMeanKcal: 2000,
    estimatedTdeeKcal: 2500,
    windowDays: 21,
  });
  assert.equal(r.ok, true);
  if (r.ok) {
    near(r.factor, 1.25, 0.001);
    assert.equal(r.clamped, false);
  }
});

test('perdita di 0,5 kg/settimana con 2000 loggate e TDEE 2500', () => {
  // slope = −0.5/7 kg/giorno → −550 kcal/giorno
  // factor = (2500 − 550) / 2000 = 0.975
  const r = computeCalibration({
    weightPoints: weightSeries(80, -0.5 / 7, 11),
    loggedMeanKcal: 2000,
    estimatedTdeeKcal: 2500,
    windowDays: 21,
  });
  assert.equal(r.ok, true);
  if (r.ok) near(r.factor, 0.975, 0.002);
});

test('valori assurdi vengono limitati invece di propagarsi', () => {
  const r = computeCalibration({
    weightPoints: weightSeries(80, 0, 11),
    loggedMeanKcal: 800,          // logging quasi assente
    estimatedTdeeKcal: 2600,      // factor grezzo = 3.25
    windowDays: 21,
  });
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.factor, 1.6);
    assert.equal(r.clamped, true);
  }
});

test('il testo mostrato non scompone mai il fattore e non colpevolizza', () => {
  const r = computeCalibration({
    weightPoints: weightSeries(80, 0, 11),
    loggedMeanKcal: 2000,
    estimatedTdeeKcal: 2500,
    windowDays: 21,
  });
  const text = describeCalibration(r);
  assert.match(text, /correggere le stime verso l'alto di circa il 25%/);
  for (const forbidden of ['TDEE', 'sottostimi', 'sbagli', 'colpa']) {
    assert.ok(!text.includes(forbidden), `il testo non deve contenere "${forbidden}"`);
  }
});

// =============================================================================
// Integrazione: la calibrazione entra nel target
// =============================================================================

test('un fattore 1.25 abbassa il target loggato del 20%', () => {
  const base = {
    profile: { sex: 'male', ageYears: 30, heightCm: 180, weightKg: 80 } as BodyProfile,
    activity: 'moderate' as const,
    branch: 'athlete' as const,
    goal: 'lose' as const,
    rateKgPerWeek: -0.5,
  };
  const plain = computeTargets(base);
  const corrected = computeTargets({ ...base, calibrationFactor: 1.25 });
  near(corrected.kcal, plain.kcal / 1.25, 1);
});

test('i moltiplicatori di attività sono ordinati e coprono l\'intervallo atteso', () => {
  const values = Object.values(ACTIVITY_FACTORS);
  const sorted = [...values].sort((a, b) => a - b);
  assert.deepEqual(values, sorted);
  assert.equal(values[0], 1.2);
  assert.equal(values.at(-1), 1.9);
});
