// Actions JavaScript WeWeb pour la connexion par code reçu par email.
// Trois actions séparées : copier chacune dans son propre bloc « Custom JavaScript ».

// ─────────────────────────────────────────────────────────────────────
// A. « Envoyer le code »  — workflow du bouton « Recevoir mon code »
//    Variable lue : variables['email'] (à adapter au nom réel de la variable)
// ─────────────────────────────────────────────────────────────────────
const supabase = wwLib.wwPlugins.supabase.instance;
const email = (variables["email"] || "").trim().toLowerCase();
if (!email) return { ok: false, message: "Saisissez votre adresse email." };

const { error } = await supabase.auth.signInWithOtp({
  email,
  options: { shouldCreateUser: true },
});
if (error) {
  // Email inconnu ou archivé : refusé par le hook côté serveur.
  return { ok: false, message: "Cette adresse email n'est pas reconnue. Contactez votre responsable." };
}
return { ok: true, message: "Un code vous a été envoyé par email." };


// ─────────────────────────────────────────────────────────────────────
// B. « Valider le code »  — workflow du bouton « Valider »
//    Variables lues : variables['email'], variables['code']
// ─────────────────────────────────────────────────────────────────────
const supabase = wwLib.wwPlugins.supabase.instance;
const { error } = await supabase.auth.verifyOtp({
  email: (variables["email"] || "").trim().toLowerCase(),
  token: (variables["code"] || "").trim(),
  type: "email",
});
if (error) return { ok: false, message: "Code incorrect ou expiré." };

// Relie le compte à la fiche salarié et dit si l'accès est autorisé.
const { data: profil, error: erreurProfil } = await supabase.rpc("mon_profil");
if (erreurProfil || !profil?.autorise) {
  await supabase.auth.signOut();
  return { ok: false, message: profil?.message || "Votre compte n'est pas actif. Contactez votre responsable." };
}
return { ok: true, profil };


// ─────────────────────────────────────────────────────────────────────
// C. « Charger mon planning »  — workflow « On page load » de la page Planning
//    Renvoie la liste des cartes du jour (à stocker dans la variable 'planning').
// ─────────────────────────────────────────────────────────────────────
const supabase = wwLib.wwPlugins.supabase.instance;
const { data, error } = await supabase.rpc("mon_planning");
if (error) return [];
return data;
