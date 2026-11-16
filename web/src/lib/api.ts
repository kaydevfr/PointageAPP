import { FunctionsHttpError } from "@supabase/supabase-js";
import { supabaseNavigateur } from "./supabase/client";
import { appareilId, obtenirPosition } from "./appareil";
import {
  MESSAGE_RESEAU,
  corpsPointer,
  messageErreur,
  normaliserEmail,
  nettoyerCode,
  type Carte,
} from "./pointage";

// Appels à Supabase. Le front ne fait qu'appeler : aucune décision ici.

export type Resultat = { ok: boolean; message: string };

export type Profil = {
  autorise: boolean;
  message?: string;
  id?: string;
  prenom?: string | null;
  nom?: string | null;
  role?: string;
  langue?: string;
  pointage_bouton?: boolean;
};

const MESSAGE_EMAIL_INCONNU = "Cette adresse email n'est pas reconnue. Contactez votre responsable.";
const MESSAGE_COMPTE_INACTIF = "Votre compte n'est pas actif. Contactez votre responsable.";

export async function envoyerCode(email: string): Promise<Resultat> {
  const { error } = await supabaseNavigateur().auth.signInWithOtp({
    email: normaliserEmail(email),
    options: { shouldCreateUser: true },
  });
  if (!error) return { ok: true, message: "Un code vous a été envoyé par email." };
  if (error.status === 429) return { ok: false, message: "Trop de demandes. Patientez une minute avant de réessayer." };
  if (error.name === "AuthRetryableFetchError") return { ok: false, message: MESSAGE_RESEAU };
  // Email inconnu ou archivé : refusé par le hook côté serveur.
  return { ok: false, message: MESSAGE_EMAIL_INCONNU };
}

export async function validerCode(email: string, code: string): Promise<Resultat> {
  const supabase = supabaseNavigateur();
  const { error } = await supabase.auth.verifyOtp({
    email: normaliserEmail(email),
    token: nettoyerCode(code),
    type: "email",
  });
  if (error) {
    if (error.name === "AuthRetryableFetchError") return { ok: false, message: MESSAGE_RESEAU };
    return { ok: false, message: "Code incorrect ou expiré." };
  }
  const profil = await monProfil();
  if (!profil.autorise) {
    await supabase.auth.signOut();
    return { ok: false, message: profil.message ?? MESSAGE_COMPTE_INACTIF };
  }
  return { ok: true, message: "" };
}

// Relie le compte à la fiche salarié et dit si l'accès est autorisé.
export async function monProfil(): Promise<Profil> {
  const { data, error } = await supabaseNavigateur().rpc("mon_profil");
  if (error || !data) return { autorise: false, message: MESSAGE_COMPTE_INACTIF };
  return data as Profil;
}

export async function monPlanning(): Promise<Carte[]> {
  const { data, error } = await supabaseNavigateur().rpc("mon_planning");
  if (error) throw new Error(MESSAGE_RESEAU);
  return (data ?? []) as Carte[];
}

export async function pointer(carte: Carte): Promise<Resultat> {
  const position = await obtenirPosition();
  const corps = corpsPointer(carte, position, appareilId(), new Date());
  try {
    const { data, error } = await supabaseNavigateur().functions.invoke("pointer", { body: corps });
    if (!error) return { ok: true, message: (data as { message?: string })?.message ?? "Pointage enregistré ✓" };
    if (error instanceof FunctionsHttpError) {
      try {
        return { ok: false, message: messageErreur(await error.context.json()) };
      } catch {
        return { ok: false, message: messageErreur(null) };
      }
    }
    return { ok: false, message: MESSAGE_RESEAU };
  } catch {
    return { ok: false, message: MESSAGE_RESEAU };
  }
}

export async function deconnexion(): Promise<void> {
  await supabaseNavigateur().auth.signOut();
}
