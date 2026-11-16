// Réponses HTTP communes aux Edge Functions appelées par le front Next.js.

// Origines autorisées : variable ALLOWED_ORIGINS (séparées par des virgules),
// par exemple « http://localhost:3000,https://pointage.vercel.app ».
// Sans réglage : toutes (l'authentification repose de toute façon sur le jeton).
const origines = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((o) => o.trim())
  .filter(Boolean);

export function enTetesCors(req: Request): Record<string, string> {
  const origine = req.headers.get("Origin") ?? "";
  const autorisee = origines.length === 0
    ? "*"
    : origines.includes(origine)
    ? origine
    : origines[0];
  return {
    "Access-Control-Allow-Origin": autorisee,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export function reponseJson(req: Request, corps: unknown, statut = 200): Response {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { ...enTetesCors(req), "Content-Type": "application/json; charset=utf-8" },
  });
}
