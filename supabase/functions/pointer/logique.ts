// Logique pure de l'Edge Function `pointer` (testée par logique.test.ts).
// Principe : on ne bloque jamais un agent honnête. Une preuve absente ou
// malformée est simplement omise ; c'est la base qui en tire l'alerte.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const APPAREIL_ID = /^[A-Za-z0-9_-]{8,64}$/;

export type Preuves = {
  lat?: number;
  lng?: number;
  precision_m?: number;
  device_at?: string;
  appareil_id?: string;
  user_agent?: string;
  ip?: string;
};

export type Analyse =
  | { ok: true; pointageId: string | null; creneauId: string | null; preuves: Preuves }
  | { ok: false; statut: number; message: string };

function estNombre(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

// Corps attendu :
// { pointageId | creneauId, location?: { lat, lng, accuracy } | null,
//   deviceTime?: string ISO, appareilId?: string, passkeyAssertion?: (phase 2) }
export function analyserRequete(
  corps: unknown,
  meta: { ip: string | null; userAgent: string | null },
): Analyse {
  if (corps === null || typeof corps !== "object" || Array.isArray(corps)) {
    return { ok: false, statut: 400, message: "Requête invalide." };
  }
  const c = corps as Record<string, unknown>;

  const pointageId = typeof c.pointageId === "string" && UUID.test(c.pointageId) ? c.pointageId : null;
  const creneauId = typeof c.creneauId === "string" && UUID.test(c.creneauId) ? c.creneauId : null;
  if ((pointageId === null) === (creneauId === null)) {
    // Ni l'un ni l'autre, ou les deux : la carte du planning est mal branchée.
    return { ok: false, statut: 400, message: "Créneau introuvable. Actualisez la page." };
  }

  const preuves: Preuves = {};

  const loc = c.location as Record<string, unknown> | null | undefined;
  if (loc && typeof loc === "object" && estNombre(loc.lat) && estNombre(loc.lng)) {
    preuves.lat = loc.lat;
    preuves.lng = loc.lng;
    if (estNombre(loc.accuracy) && loc.accuracy >= 0) preuves.precision_m = loc.accuracy;
  }

  // Heure du téléphone : simple indice, jamais utilisée comme heure de pointage.
  if (typeof c.deviceTime === "string" && c.deviceTime.length <= 40) {
    preuves.device_at = c.deviceTime;
  }

  if (typeof c.appareilId === "string" && APPAREIL_ID.test(c.appareilId)) {
    preuves.appareil_id = c.appareilId;
  }

  if (meta.userAgent) preuves.user_agent = meta.userAgent.slice(0, 500);
  if (meta.ip) preuves.ip = meta.ip;

  // passkeyAssertion : vérifiée en phase 2. D'ici là, aucune preuve de
  // l'appareil n'est transmise, et la base lève NO_DEVICE_PROOF.

  return { ok: true, pointageId, creneauId, preuves };
}

// Adresse IP du client derrière le proxy Supabase.
export function extraireIp(entetes: Headers): string | null {
  const transmise = entetes.get("x-forwarded-for");
  if (transmise) return transmise.split(",")[0].trim() || null;
  return entetes.get("x-real-ip");
}

// Code HTTP selon la réponse de traiter_pointage.
export function statutHttp(action: unknown): number {
  switch (action) {
    case "refuse":
      return 403;
    case "limite":
      return 429;
    case "erreur":
      return 400;
    default:
      return 200;
  }
}
