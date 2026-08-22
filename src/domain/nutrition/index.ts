/**
 * Logica nutrizionale — pura, senza dipendenze, testata.
 *
 * Nessuna funzione di questo modulo tocca la rete, il database o React.
 * È voluto: sono i calcoli in cui un errore è invisibile all'utente e
 * potenzialmente dannoso, quindi devono restare verificabili in isolamento.
 *
 * Test:  npx tsx --test src/domain/nutrition/nutrition.test.ts
 */

export * from './types';
export * from './energy';
export * from './targets';
export * from './calibration';
