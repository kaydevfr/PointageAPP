// Edge Function `pointer` : pointage par bouton (agents sans NFC).
//
// POST /functions/v1/pointer
//   Authorization: Bearer <jeton de session de l'agent>
//   { pointageId | creneauId, location?, deviceTime?, appareilId? }
// → { action, message, pointage }   (jamais d'alerte ni de statut de confiance)
//
// L'heure enregistrée est celle du serveur (now() dans traiter_pointage).

import { createClient } from "@supabase/supabase-js";
import { enTetesCors, reponseJson } from "../_shared/http.ts";
import { analyserRequete, extraireIp, statutHttp } from "./logique.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: enTetesCors(req) });
  }
  if (req.method !== "POST") {
    return reponseJson(req, { action: "erreur", message: "Méthode non autorisée." }, 405);
  }

  // 1. Qui pointe ? Uniquement d'après le jeton de session, jamais d'après le corps.
  const jeton = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jeton) {
    return reponseJson(req, { action: "erreur", message: "Session expirée. Reconnectez-vous." }, 401);
  }
  const clientAgent = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: utilisateur, error: erreurAuth } = await clientAgent.auth.getUser(jeton);
  if (erreurAuth || !utilisateur?.user) {
    return reponseJson(req, { action: "erreur", message: "Session expirée. Reconnectez-vous." }, 401);
  }

  // 2. Lecture tolérante de la requête.
  let corps: unknown = null;
  try {
    corps = await req.json();
  } catch {
    corps = null;
  }
  const analyse = analyserRequete(corps, {
    ip: extraireIp(req.headers),
    userAgent: req.headers.get("user-agent"),
  });
  if (!analyse.ok) {
    return reponseJson(req, { action: "erreur", message: analyse.message }, analyse.statut);
  }

  // 3. Fiche salarié reliée au compte.
  const { data: profil, error: erreurProfil } = await admin
    .from("profiles")
    .select("id")
    .eq("user_id", utilisateur.user.id)
    .maybeSingle();
  if (erreurProfil) {
    console.error("pointer: lecture du profil", erreurProfil);
    return reponseJson(req, { action: "erreur", message: "Le pointage n'a pas pu être enregistré. Réessayez." }, 500);
  }
  if (!profil) {
    return reponseJson(req, {
      action: "refuse",
      code: "PROFIL_INACTIF",
      message: "Votre compte n'est pas actif. Contactez votre responsable.",
    }, 403);
  }

  // 4. Toute la logique (choix, anti-rebond, alertes, statut) est dans la base.
  const { data: resultat, error: erreurRpc } = await admin.rpc("traiter_pointage", {
    p_profile_id: profil.id,
    p_site_id: null,
    p_methode: "bouton",
    p_pointage_id: analyse.pointageId,
    p_creneau_id: analyse.creneauId,
    p_preuves: analyse.preuves,
  });
  if (erreurRpc) {
    console.error("pointer: traiter_pointage", erreurRpc);
    return reponseJson(req, { action: "erreur", message: "Le pointage n'a pas pu être enregistré. Réessayez." }, 500);
  }

  return reponseJson(req, resultat, statutHttp(resultat?.action));
});
