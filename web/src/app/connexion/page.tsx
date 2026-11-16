"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { envoyerCode, validerCode } from "@/lib/api";
import { codePlausible, emailPlausible, nettoyerCode } from "@/lib/pointage";

export default function PageConnexion() {
  const router = useRouter();
  const [etape, setEtape] = useState<"email" | "code">("email");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [message, setMessage] = useState("");
  const [envoi, setEnvoi] = useState(false);

  async function demanderCode(e: FormEvent) {
    e.preventDefault();
    if (!emailPlausible(email)) {
      setMessage("Saisissez une adresse email valide.");
      return;
    }
    setEnvoi(true);
    setMessage("");
    const r = await envoyerCode(email);
    setEnvoi(false);
    setMessage(r.ok ? "" : r.message);
    if (r.ok) setEtape("code");
  }

  async function verifier(e: FormEvent) {
    e.preventDefault();
    if (!codePlausible(code)) {
      setMessage("Le code contient 6 chiffres.");
      return;
    }
    setEnvoi(true);
    setMessage("");
    const r = await validerCode(email, code);
    if (r.ok) {
      router.replace("/planning");
      return;
    }
    setEnvoi(false);
    setMessage(r.message);
  }

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center px-5 py-10">
      <h1 className="text-2xl font-semibold">Pointage</h1>
      <p className="mt-1 text-sm text-slate-500">Les Nettoyeurs</p>

      {etape === "email" ? (
        <form onSubmit={demanderCode} className="mt-8 flex flex-col gap-3" noValidate>
          <label htmlFor="email" className="text-sm font-medium">
            Votre adresse email
          </label>
          <input
            id="email"
            type="email"
            inputMode="email"
            autoComplete="email"
            autoCapitalize="none"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="rounded-lg border border-slate-300 px-4 py-3 text-base focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-600/30"
            placeholder="prenom.nom@exemple.fr"
            required
          />
          <button
            type="submit"
            disabled={envoi}
            className="mt-2 rounded-lg bg-blue-700 px-4 py-3 font-medium text-white disabled:opacity-60"
          >
            {envoi ? "Envoi…" : "Recevoir mon code"}
          </button>
        </form>
      ) : (
        <form onSubmit={verifier} className="mt-8 flex flex-col gap-3" noValidate>
          <p className="text-sm text-slate-600">
            Code envoyé à <strong>{email.trim()}</strong>
          </p>
          <label htmlFor="code" className="text-sm font-medium">
            Code reçu par email
          </label>
          <input
            id="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]*"
            maxLength={8}
            value={code}
            onChange={(e) => setCode(nettoyerCode(e.target.value))}
            className="rounded-lg border border-slate-300 px-4 py-3 text-center text-2xl tracking-[0.4em] focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-600/30"
            placeholder="••••••"
            required
          />
          <button
            type="submit"
            disabled={envoi}
            className="mt-2 rounded-lg bg-blue-700 px-4 py-3 font-medium text-white disabled:opacity-60"
          >
            {envoi ? "Vérification…" : "Valider"}
          </button>
          <button
            type="button"
            onClick={() => {
              setEtape("email");
              setCode("");
              setMessage("");
            }}
            className="text-sm text-blue-700 underline"
          >
            Changer d&apos;adresse
          </button>
        </form>
      )}

      {message && (
        <p role="alert" className="mt-4 rounded-lg bg-slate-100 px-4 py-3 text-sm text-slate-700">
          {message}
        </p>
      )}
    </main>
  );
}
