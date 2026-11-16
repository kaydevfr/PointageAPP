// Action JavaScript WeWeb : « Pointer » (bouton d'une carte du planning)
// À placer dans le workflow « On click » du bouton, DANS la liste répétée
// des cartes : context.item.data est la carte (une ligne de mon_planning).
//
// Renvoie { ok: boolean, message: string } pour l'afficher à l'agent.
// Aucune règle métier ici : le serveur décide (arrivée, départ, ignoré).

const carte = context.item.data;
const supabase = wwLib.wwPlugins.supabase.instance;

// 1. Identifiant aléatoire de ce téléphone (repère un téléphone partagé).
let appareilId = null;
try {
  appareilId = localStorage.getItem("pointage_appareil_id");
  if (!appareilId) {
    appareilId = crypto.randomUUID();
    localStorage.setItem("pointage_appareil_id", appareilId);
  }
} catch (_) {
  appareilId = null;
}

// 2. Position (10 s maximum). null si refus ou échec : on pointe quand même.
const position = await new Promise((resolve) => {
  if (!("geolocation" in navigator)) return resolve(null);
  const filet = setTimeout(() => resolve(null), 11000);
  navigator.geolocation.getCurrentPosition(
    (p) => {
      clearTimeout(filet);
      resolve({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy });
    },
    () => {
      clearTimeout(filet);
      resolve(null);
    },
    { enableHighAccuracy: true, maximumAge: 0, timeout: 10000 },
  );
});

// 3. Envoi. Le pointage existe déjà (pointage_id) ou sera créé (creneau_id).
const corps = {
  location: position,
  deviceTime: new Date().toISOString(),
  appareilId,
};
if (carte.pointage_id) corps.pointageId = carte.pointage_id;
else corps.creneauId = carte.creneau_id;

try {
  const { data, error } = await supabase.functions.invoke("pointer", { body: corps });
  if (!error) return { ok: true, message: data.message };

  // Réponse d'erreur du serveur (403, 429, 400…) : on affiche son message.
  try {
    const detail = await error.context.json();
    return { ok: false, message: detail.message || "Le pointage n'a pas pu être enregistré. Réessayez." };
  } catch (_) {
    return { ok: false, message: "Pas de connexion, réessayez." };
  }
} catch (_) {
  return { ok: false, message: "Pas de connexion, réessayez." };
}
