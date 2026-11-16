# WeWeb : fiches de montage

WeWeb **affiche et appelle**, rien de plus. Toutes les règles (heure, choix du pointage, anti-triche, statut) sont dans Supabase.

## 0. Avant de commencer (une seule fois)

1. **Projet Supabase en ligne, en région UE**, avec la base poussée (`npx supabase db push`) et la fonction déployée (`npx supabase functions deploy pointer`).
2. **Dans Supabase, Authentication** :
   - **Hooks** → « Before User Created » → type Postgres → fonction `public.hook_avant_creation_compte`. Ce hook refuse les emails inconnus ou archivés.
   - **Email Templates** → « Magic Link » : mettre le **code** `{{ .Token }}` dans le message, pour que l'agent reçoive un code à 6 chiffres plutôt qu'un lien.
   - **URL Configuration** : ajouter l'adresse de l'application WeWeb.
3. **Dans WeWeb, Plugins** → ajouter **Supabase** :
   - **Project URL** : `https://<ref>.supabase.co` ;
   - **Clé publique** : la clé `anon`. **Jamais** la clé `service_role`, ni aucune autre clé.

   Ajouter aussi le plugin **Supabase Auth**, pour protéger les pages.
4. **Secret de la fonction**, si tu veux limiter les origines autorisées :

   ```bash
   npx supabase secrets set ALLOWED_ORIGINS=https://editor.weweb.io,https://<ton-domaine>
   ```

> ⚠️ **À vérifier au premier montage** : les actions JavaScript utilisent le client Supabase du plugin, `wwLib.wwPlugins.supabase.instance`. Si l'éditeur indique un autre nom, ou si la session n'est pas partagée avec le plugin Supabase Auth, signale-le : on adaptera les actions.

## Les fiches

| Fiche | Page | Fichiers JS |
|---|---|---|
| [01-connexion.md](fiches/01-connexion.md) | Connexion par code email | [actions/connexion.js](actions/connexion.js) (A et B) |
| [02-planning.md](fiches/02-planning.md) | Planning du jour + boutons | [actions/connexion.js](actions/connexion.js) (C), [actions/pointer.js](actions/pointer.js), [actions/geolocaliser.js](actions/geolocaliser.js) |

Les pages admin (liste des pointages, réglages des sites) viendront avec leurs RPC dédiées. Elles ne sont pas encore écrites.
