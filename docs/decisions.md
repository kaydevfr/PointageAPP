# Décisions et hypothèses

Ce fichier liste ce qui a été tranché, ou supposé faute de réponse. Une hypothèse se change facilement : elle est soit isolée dans une fonction, soit stockée dans `reglages`.

## Section 13 du cahier des charges (recommandations appliquées)

| # | Sujet | Choix appliqué | Où le changer |
|---|---|---|---|
| 1 | Référence des données | Bubble reste la référence en phase 1 | — |
| 2 | Connexion | Code à usage unique par email | Phase 1 |
| 3 | Nouveau téléphone | Accepté, avec l'alerte `NEW_DEVICE` pendant 24 h après la création de la passkey | `reglages.nouvel_appareil_h` |
| 4 | Rayon et conservation | 200 m ; positions gardées 60 jours | `reglages.rayon_defaut_m`, `reglages.conservation_positions_jours` |
| 5 | Puces NTAG 424 DNA | Non tranché, sans effet sur la phase 0 | — |
| 6 | Agents Container | Hors périmètre | — |
| 7 | Créneaux qui passent minuit | Gérés : la fin est fixée au lendemain | — |

## Hypothèses à confirmer (questions posées, pas encore de réponse)

1. **Heures de nuit** : seulement **avant 6 h**, comme écrit au §9.3. Avec cette règle, un passage de 22 h à 2 h compte 0 min de nuit. Pour compter aussi le soir (21 h → 6 h, par exemple), il suffit de modifier `private.calcul_temps`.
2. **Numéro du jour dans Bubble** : on suppose que l'attribut « No » vaut 1 pour lundi et 7 pour dimanche (norme ISO). La conversion se fera dans `sync-bubble` (phase 1).
3. **Téléphone partagé (`SHARED_DEVICE`)** : un identifiant aléatoire (`appareil_id`) est gardé dans le navigateur. La détection est approximative, car Safari efface ces données au bout de 7 jours d'inactivité.

## Choix techniques (écarts ou précisions par rapport au cahier des charges)

- **`profiles.id` ≠ `auth.users.id`** : les profils sont créés par la synchronisation avant que les comptes existent. La colonne `user_id` est remplie à la première connexion.
- **Ordre de choix d'un pointage** : un pointage **en cours** (arrivée sans départ) est toujours servi en premier, puis celui dont l'heure prévue est la plus proche. Sans cette règle, un départ pointé à 10 h 20 sur un créneau 8 h → 10 h tomberait sur le créneau suivant de 10 h 30 du même site.
- **Créneaux qui passent minuit** : un pointage de la veille reste actionnable jusqu'à 4 h après sa fin prévue (`reglages.delai_depart_apres_fin_h`). La correction de nuit ne le touche qu'une fois ce délai passé.
- **Alerte ajoutée `BUTTON_NOT_ALLOWED`** (grave) : bouton utilisé par un agent qui a le NFC. L'interface ne lui montre pas de bouton, donc l'appel a été forgé. Le pointage est quand même enregistré.
- **Alerte ajoutée `SITE_NO_POSITION`** : le site n'a pas de coordonnées, donc la présence ne peut pas être prouvée.
- **NFC et position** : avec une puce, la position est facultative. Seul `OUT_OF_ZONE` est retenu ; il n'y a pas de `NO_LOCATION`.
- **Alertes invisibles pour l'agent** : `pointages.alertes`, `pointages.statut_confiance` et le journal `evenements_pointage` ne sont pas lisibles avec la clé `anon` ni par un utilisateur connecté. L'admin y accédera par des RPC (phase 1).
- **Pas d'écriture directe, même pour l'admin** : ses corrections passeront par `admin_corriger_pointage`, avec historique dans `audit_admin` (phase 1).
- **Heure injectable** : la logique (`private.*`) reçoit l'instant en paramètre, pour être testable. Les fonctions `public.*` appelables passent toujours `now()`.
