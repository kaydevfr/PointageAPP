# Front Next.js : pointage Les Nettoyeurs

Il ne fait **qu'afficher et appeler** Supabase. Aucune règle métier ici : l'heure, le choix du pointage, l'anti-triche et le statut de confiance sont dans Supabase.

## Pages

| Page | Rôle |
|---|---|
| `/connexion` | Email → code reçu par email → vérification que le compte est actif (`mon_profil`) |
| `/planning` | Cartes du jour (`mon_planning`), boutons de pointage (Edge Function `pointer`), écran d'explication sur la localisation |

`src/proxy.ts` rafraîchit la session et renvoie vers `/connexion` un visiteur qui n'est pas connecté. Next.js 16 appelle ce fichier `proxy` (l'ancien `middleware`).

## Commandes

Installation :

```bash
npm install
```

Serveur de développement, sur http://localhost:3000 :

```bash
npm run dev
```

Tests (Vitest) :

```bash
npm test
```

Compilation de production :

```bash
npm run build
```

## Variables d'environnement

En local, elles vont dans `web/.env.local` (non versionné). Sur Vercel, elles vont dans *Settings → Environment Variables*.

| Nom | Valeur |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://ywxmdbrnslfapvvfndbj.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | La clé **`anon`** (publique) du projet |

**Jamais la clé `service_role`, ni aucune autre clé secrète, dans le front.**

## Déploiement sur Vercel

1. *Add New → Project* → importer le dépôt GitHub `PointageAPP`.
2. **Root Directory : `web`**.
3. Ajouter les deux variables d'environnement.
4. Deploy. La région est Paris (`cdg1`), réglée dans `vercel.json`.
5. Dans Supabase, *Authentication → URL Configuration* : mettre l'adresse Vercel comme **Site URL**, et l'ajouter aux **Redirect URLs**.
