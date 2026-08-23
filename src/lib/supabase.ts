import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;

/**
 * Publishable key (sb_publishable_...), il rimpiazzo della vecchia anon key.
 * È progettata per stare nel bundle dell'app: la protezione dei dati è tutta
 * nelle policy RLS, non nella segretezza della chiave.
 *
 * La secret key (sb_secret_...) non deve MAI comparire qui: bypassa la RLS.
 */
const publishableKey = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!url || !publishableKey) {
  throw new Error(
    'Variabili Supabase mancanti. Copia .env.example in .env e compilalo.',
  );
}

export const supabase = createClient(url, publishableKey, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    // Obbligatorio su React Native: non esiste una URL da cui leggere
    // il frammento di sessione dopo il redirect OAuth.
    detectSessionInUrl: false,
  },
});

/**
 * Lo schema `odbl` non è esposto da PostgREST per impostazione predefinita.
 * Va aggiunto in Dashboard → Settings → Data API → Exposed schemas,
 * altrimenti ogni query verso alimenti e prodotti risponde 404.
 *
 * Client dedicato, così il confine di licenza resta visibile anche nel codice.
 */
export const odbl = supabase.schema('odbl');
