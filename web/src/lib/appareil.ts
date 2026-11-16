import type { Position } from "./pointage";

// Petit utilitaire navigateur : jamais d'exception, toujours une valeur sûre.

const CLE_APPAREIL = "pointage_appareil_id";
const CLE_EXPLICATION = "pointage_explication_vue";

type Stockage = Pick<Storage, "getItem" | "setItem">;

function stockage(): Stockage | null {
  try {
    return typeof window === "undefined" ? null : window.localStorage;
  } catch {
    return null;
  }
}

// Identifiant aléatoire de ce téléphone : sert à repérer un téléphone utilisé
// par plusieurs comptes (SHARED_DEVICE). Approximation : Safari peut l'effacer.
export function appareilId(s: Stockage | null = stockage(), genere = () => crypto.randomUUID()): string | null {
  if (!s) return null;
  try {
    let id = s.getItem(CLE_APPAREIL);
    if (!id) {
      id = genere();
      s.setItem(CLE_APPAREIL, id);
    }
    return id;
  } catch {
    return null;
  }
}

export function explicationVue(s: Stockage | null = stockage()): boolean {
  try {
    return s?.getItem(CLE_EXPLICATION) === "1";
  } catch {
    return false;
  }
}

export function marquerExplicationVue(s: Stockage | null = stockage()): void {
  try {
    s?.setItem(CLE_EXPLICATION, "1");
  } catch {
    // tant pis : l'explication sera simplement remontrée
  }
}

// Position au moment du pointage : haute précision, sans cache, 10 s maximum.
// Refus, délai dépassé ou indisponible → null, et on pointe quand même.
export function obtenirPosition(
  geo: Geolocation | undefined = typeof navigator === "undefined" ? undefined : navigator.geolocation,
  delaiMs = 10_000,
): Promise<Position | null> {
  return new Promise((resolve) => {
    if (!geo) return resolve(null);
    let fini = false;
    const terminer = (p: Position | null) => {
      if (fini) return;
      fini = true;
      clearTimeout(filet);
      resolve(p);
    };
    // Filet si le navigateur n'appelle jamais aucun rappel.
    const filet = setTimeout(() => terminer(null), delaiMs + 1_000);
    try {
      geo.getCurrentPosition(
        (p) => terminer({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy }),
        () => terminer(null),
        { enableHighAccuracy: true, maximumAge: 0, timeout: delaiMs },
      );
    } catch {
      terminer(null);
    }
  });
}
