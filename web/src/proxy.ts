import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Pages réservées aux utilisateurs connectés.
const PAGES_PROTEGEES = ["/planning"];

// Rafraîchit la session Supabase (cookies) à chaque requête, et renvoie vers
// /connexion un visiteur non connecté qui demande une page protégée.
// Ce n'est qu'un aiguillage : les vraies protections sont dans Supabase (RLS).
export async function proxy(request: NextRequest) {
  let reponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(aEcrire, entetes) {
          aEcrire.forEach(({ name, value }) => request.cookies.set(name, value));
          reponse = NextResponse.next({ request });
          aEcrire.forEach(({ name, value, options }) => reponse.cookies.set(name, value, options));
          Object.entries(entetes ?? {}).forEach(([cle, valeur]) => reponse.headers.set(cle, valeur));
        },
      },
    },
  );

  // getClaims vérifie la signature du jeton (ne pas se fier à getSession ici).
  const { data } = await supabase.auth.getClaims();
  const connecte = Boolean(data?.claims?.sub);
  const chemin = request.nextUrl.pathname;

  if (!connecte && PAGES_PROTEGEES.some((p) => chemin === p || chemin.startsWith(p + "/"))) {
    const url = request.nextUrl.clone();
    url.pathname = "/connexion";
    url.search = "";
    return NextResponse.redirect(url);
  }

  return reponse;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|manifest.webmanifest|icon.*|.*\\.(?:svg|png|jpg|ico)$).*)"],
};
