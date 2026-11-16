"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { deconnexion, monPlanning, monProfil, pointer, type Profil } from "@/lib/api";
import { explicationVue, marquerExplicationVue, obtenirPosition } from "@/lib/appareil";
import { cleCarte, horaires, libelleBouton, tonMessage, type Carte, type Ton } from "@/lib/pointage";

const STYLE_TON: Record<Ton, string> = {
  succes: "bg-green-50 text-green-800 border-green-200",
  attention: "bg-amber-50 text-amber-800 border-amber-200",
  neutre: "bg-slate-50 text-slate-600 border-slate-200",
  info: "bg-blue-50 text-blue-800 border-blue-200",
};

const PASTILLE: Record<Carte["etat"], { texte: string; classe: string }> = {
  a_faire: { texte: "À faire", classe: "bg-slate-100 text-slate-700" },
  en_cours: { texte: "En cours", classe: "bg-blue-100 text-blue-800" },
  termine: { texte: "Terminé", classe: "bg-green-100 text-green-800" },
  manque: { texte: "Manqué", classe: "bg-slate-200 text-slate-600" },
};

export default function PagePlanning() {
  const router = useRouter();
  const [profil, setProfil] = useState<Profil | null>(null);
  const [cartes, setCartes] = useState<Carte[] | null>(null);
  const [erreur, setErreur] = useState("");
  const [enCours, setEnCours] = useState<string | null>(null);
  const [toast, setToast] = useState<{ ok: boolean; message: string } | null>(null);
  const [explication, setExplication] = useState<Carte | null>(null);

  const charger = useCallback(async () => {
    try {
      setCartes(await monPlanning());
      setErreur("");
    } catch (e) {
      setErreur(e instanceof Error ? e.message : "Pas de connexion, réessayez.");
    }
  }, []);

  useEffect(() => {
    (async () => {
      const p = await monProfil();
      if (!p.autorise) {
        await deconnexion();
        router.replace("/connexion");
        return;
      }
      setProfil(p);
      await charger();
    })();
  }, [charger, router]);

  // Rechargement quand l'agent revient sur l'application.
  useEffect(() => {
    const auRetour = () => document.visibilityState === "visible" && charger();
    document.addEventListener("visibilitychange", auRetour);
    return () => document.removeEventListener("visibilitychange", auRetour);
  }, [charger]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 4000);
    return () => clearTimeout(t);
  }, [toast]);

  async function envoyer(carte: Carte) {
    setEnCours(cleCarte(carte));
    const r = await pointer(carte);
    setToast(r);
    await charger();
    setEnCours(null);
  }

  function auClic(carte: Carte) {
    // Écran d'explication (CNIL) avant la toute première demande de position.
    if (!explicationVue()) {
      setExplication(carte);
      return;
    }
    void envoyer(carte);
  }

  async function compris() {
    const carte = explication;
    marquerExplicationVue();
    setExplication(null);
    if (carte) {
      setEnCours(cleCarte(carte));
      await obtenirPosition(); // le navigateur demande l'autorisation ici
      await envoyer(carte);
    }
  }

  async function seDeconnecter() {
    await deconnexion();
    router.replace("/connexion");
  }

  return (
    <main className="mx-auto w-full max-w-lg flex-1 px-4 pb-24 pt-6">
      <header className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold">Mon planning du jour</h1>
          {profil?.prenom && <p className="text-sm text-slate-500">Bonjour {profil.prenom}</p>}
        </div>
        <div className="flex gap-2">
          <button onClick={() => charger()} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
            Actualiser
          </button>
          <button onClick={seDeconnecter} className="rounded-lg px-3 py-2 text-sm text-slate-500">
            Déconnexion
          </button>
        </div>
      </header>

      {erreur && (
        <p role="alert" className="mt-4 rounded-lg bg-slate-100 px-4 py-3 text-sm text-slate-700">
          {erreur}
        </p>
      )}

      {cartes === null && !erreur && <p className="mt-10 text-center text-slate-500">Chargement…</p>}

      {cartes?.length === 0 && <p className="mt-10 text-center text-slate-500">Aucun créneau aujourd&apos;hui.</p>}

      <ul className="mt-6 flex flex-col gap-4">
        {cartes?.map((carte) => {
          const cle = cleCarte(carte) || carte.site_id;
          const libelle = libelleBouton(carte.bouton);
          const pastille = PASTILLE[carte.etat];
          return (
            <li key={cle} className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h2 className="font-semibold">{carte.site_nom}</h2>
                  {carte.site_adresse && <p className="text-sm text-slate-500">{carte.site_adresse}</p>}
                  <p className="mt-1 text-sm font-medium">{horaires(carte)}</p>
                </div>
                <span className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-medium ${pastille.classe}`}>
                  {pastille.texte}
                </span>
              </div>

              {carte.message && (
                <p className={`mt-3 rounded-lg border px-3 py-2 text-sm ${STYLE_TON[tonMessage(carte.affichage)]}`}>
                  {carte.message}
                </p>
              )}

              {libelle && (
                <button
                  onClick={() => auClic(carte)}
                  disabled={enCours !== null}
                  className="mt-3 w-full rounded-lg bg-blue-700 px-4 py-3 font-medium text-white disabled:opacity-60"
                >
                  {enCours === cleCarte(carte) ? "Envoi…" : libelle}
                </button>
              )}
            </li>
          );
        })}
      </ul>

      {toast && (
        <div
          role="status"
          className={`fixed inset-x-4 bottom-6 mx-auto max-w-lg rounded-xl px-4 py-3 text-center font-medium shadow-lg ${
            toast.ok ? "bg-green-700 text-white" : "bg-slate-800 text-white"
          }`}
        >
          {toast.message}
        </div>
      )}

      {explication && (
        <div className="fixed inset-0 z-10 flex items-end justify-center bg-black/40 p-4 sm:items-center">
          <div role="dialog" aria-modal="true" className="w-full max-w-md rounded-2xl bg-white p-6">
            <h2 className="text-lg font-semibold">Votre position</h2>
            <p className="mt-3 text-sm text-slate-700">
              Pour valider votre pointage, l&apos;application vérifie votre position{" "}
              <strong>uniquement au moment où vous pointez</strong>. Elle ne vous suit jamais.
            </p>
            <p className="mt-2 text-sm text-slate-700">
              Si vous refusez, votre pointage est quand même enregistré.
            </p>
            <button onClick={compris} className="mt-5 w-full rounded-lg bg-blue-700 px-4 py-3 font-medium text-white">
              J&apos;ai compris
            </button>
          </div>
        </div>
      )}
    </main>
  );
}
