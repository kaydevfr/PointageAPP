import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";

// Client Supabase du navigateur. Seule la clé publique `anon` est utilisée :
// toute la sécurité repose sur la RLS et les fonctions côté Supabase.
let client: SupabaseClient | undefined;

export function supabaseNavigateur(): SupabaseClient {
  client ??= createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
  return client;
}
