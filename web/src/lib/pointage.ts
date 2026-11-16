// Logique d'interface (pure, testée). AUCUNE règle métier ici : le serveur
// décide de tout (heure, arrivée/départ, bouton à afficher, messages).

// Une carte telle que renvoyée par la RPC `mon_planning`.
export type Carte = {
  creneau_id: string | null;
  pointage_id: string | null;
  site_id: string;
  site_nom: string;
  site_adresse: string | null;
  prevu_debut: string | null;
  prevu_fin: string | null;
  heure_debut: string | null;
  heure_fin: string | null;
  arrivee_at: string | null;
  depart_at: string | null;
  arrivee_hhmm: string | null;
  depart_hhmm: string | null;
  hors_planning: boolean;
  etat: "a_faire" | "en_cours" | "termine" | "manque";
  affichage: "a_pointer" | "arrivee_pointee" | "penser_depart" | "termine" | "manque";
  message: string | null;
  bouton: "arrivee" | "depart" | null;
};

export type Position = { lat: number; lng: number; accuracy: number };

export type CorpsPointer = {
  pointageId?: string;
  creneauId?: string;
  location: Position | null;
  deviceTime: string;
  appareilId: string | null;
};

// Identifiant stable d'une carte (pour désactiver son bouton pendant l'envoi).
export function cleCarte(c: Pick<Carte, "pointage_id" | "creneau_id">): string {
  return c.pointage_id ?? c.creneau_id ?? "";
}

// Corps envoyé à l'Edge Function `pointer`. L'heure du téléphone n'est
// qu'un indice : le serveur enregistre toujours sa propre heure.
export function corpsPointer(
  carte: Pick<Carte, "pointage_id" | "creneau_id">,
  position: Position | null,
  appareilId: string | null,
  maintenant: Date,
): CorpsPointer {
  const corps: CorpsPointer = {
    location: position,
    deviceTime: maintenant.toISOString(),
    appareilId,
  };
  if (carte.pointage_id) corps.pointageId = carte.pointage_id;
  else if (carte.creneau_id) corps.creneauId = carte.creneau_id;
  return corps;
}

export function libelleBouton(bouton: Carte["bouton"]): string | null {
  if (bouton === "arrivee") return "Pointer l'arrivée";
  if (bouton === "depart") return "Pointer le départ";
  return null;
}

export function horaires(c: Pick<Carte, "heure_debut" | "heure_fin" | "hors_planning">): string {
  if (c.hors_planning || !c.heure_debut) return "Hors planning";
  return `${c.heure_debut} – ${c.heure_fin ?? ""}`.trim();
}

// Ton visuel du message, selon l'état calculé par le serveur.
export type Ton = "succes" | "attention" | "neutre" | "info";
export function tonMessage(affichage: Carte["affichage"]): Ton {
  switch (affichage) {
    case "termine":
      return "succes";
    case "penser_depart":
      return "attention";
    case "manque":
      return "neutre";
    default:
      return "info";
  }
}

export const MESSAGE_RESEAU = "Pas de connexion, réessayez.";
export const MESSAGE_ECHEC = "Le pointage n'a pas pu être enregistré. Réessayez.";

// Message à montrer après une erreur de l'Edge Function. On affiche le
// message du serveur s'il en donne un (403, 429, 400), jamais un détail technique.
export function messageErreur(detail: unknown): string {
  if (detail && typeof detail === "object" && "message" in detail) {
    const m = (detail as { message: unknown }).message;
    if (typeof m === "string" && m.trim()) return m;
  }
  return MESSAGE_ECHEC;
}

// ── Connexion ──────────────────────────────────────────────────────────

export function normaliserEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function emailPlausible(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normaliserEmail(email));
}

// Supabase envoie un code de 6 chiffres (réglable jusqu'à 8).
export function nettoyerCode(code: string): string {
  return code.replace(/\D/g, "").slice(0, 8);
}

export function codePlausible(code: string): boolean {
  return /^\d{6,8}$/.test(nettoyerCode(code));
}
