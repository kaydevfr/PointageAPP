# Pointage Les Nettoyeurs (Supabase + WeWeb)

Le cahier des charges complet est dans [CLAUDE.md](CLAUDE.md). Les choix et hypothèses sont dans [docs/decisions.md](docs/decisions.md).

## État

- **Phase 0 (fait)** : schéma, RLS, fonctions SQL métier, tâches `pg_cron`, données de test et tests pgTAP.
- **Phase 1 (en cours)** :
  - fait : comptes réservés aux salariés connus (hook Auth et `mon_profil`), Edge Function `pointer` (bouton), fiches de montage WeWeb ;
  - reste : synchronisation Bubble (`sync-bubble`), renvoi des pointages vers Bubble, pages et RPC admin.
- **Phase 2** : puces sécurisées, page de scan et passkeys.

## Structure

```
supabase/
  config.toml
  migrations/   01 types · 02 référentiel · 03 pointages · 04 anti-triche · 05 admin
                06 fonctions de calcul · 07 logique de pointage · 08 droits/RLS · 09 cron
  tests/        pgTAP, un fichier par thème
  seed.sql      données locales fictives
supabase/functions/pointer   Edge Function du bouton (+ tests Deno)
weweb/        fiches de montage et actions JavaScript à coller
outils/test-pglite.mjs   vérification rapide sans Docker
docs/decisions.md
```

## Prérequis

- **Docker Desktop**, indispensable pour faire tourner Supabase en local.
- **Node.js**. La CLI Supabase s'utilise avec `npx supabase …`.

## Commandes

```bash
npm install
```

Vérification rapide, sans Docker. Elle utilise Postgres en WASM (PGlite) avec PostGIS, simule l'environnement Supabase et embarque un mini pgTAP :

```bash
npm test
```

`npm test` lance aussi les tests Deno des Edge Functions. Deno est téléchargé automatiquement par `npx`.

Vérification de référence, avec Docker. Elle utilise le vrai Supabase et le vrai pgTAP :

```bash
npx supabase start
```

```bash
npx supabase db reset
```

```bash
npx supabase test db
```

## Fonctions principales

| Fonction | Appelée par | Rôle |
|---|---|---|
| `public.mon_profil()` | WeWeb, après chaque connexion | Relie le compte à la fiche salarié ; dit si l'accès est autorisé et s'il faut afficher les boutons |
| `public.mon_planning(date)` | WeWeb (utilisateur connecté) | Les cartes du jour, avec l'état d'affichage et le bouton à montrer |
| `POST /functions/v1/pointer` | WeWeb (bouton) | Vérifie la session, puis appelle `traiter_pointage` |
| `public.hook_avant_creation_compte(event)` | Supabase Auth (hook) | Refuse les emails inconnus ou archivés |
| `public.traiter_pointage(profil, site, méthode, pointage?, créneau?, preuves)` | Edge Functions (`service_role`) | Arrivée, départ ou action ignorée, avec alertes et statut de confiance |
| `public.nfc_reserver_compteur(puce, compteur)` | Edge Function `nfc-scan` | Anti-rejeu SUN |
| `public.generer_pointages(date?)` | `pg_cron`, toutes les heures | Génère les pointages prévus, de façon idempotente |
| `public.corriger_veille()` | `pg_cron`, toutes les heures | Clôture les pointages restés ouverts (`NO_DEPARTURE`) |
| `public.purger_positions()` | `pg_cron`, chaque nuit | Purge RGPD des coordonnées |

Toute la logique est dans le schéma `private`, qui n'est pas exposé par l'API.

## Déploiement (plus tard)

Le projet Supabase doit être créé en **région UE**. Ensuite :

```bash
npx supabase link --project-ref <ref>
```

```bash
npx supabase db push
```
