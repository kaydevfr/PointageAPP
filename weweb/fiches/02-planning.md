# Fiche 02 : page « Planning du jour »

**But** : l'agent voit ses créneaux du jour. S'il n'a pas de NFC, il pointe avec les boutons. L'affichage reprend les règles de Bubble (§2.4 du cahier des charges), **calculées par le serveur**.

## Page

- Nom : `Planning`, URL : `/planning`.
- **Protégée** : utilisateur connecté obligatoire. Sinon, redirection vers `Connexion`.

## Variables

| Nom | Type | Valeur initiale |
|---|---|---|
| `planning` | Array | `[]` |
| `chargement` | Boolean | true |
| `carte_en_cours` | Text | vide (id de la carte en cours d'envoi) |
| `toast` | Text | vide |
| `explication_vue` | Boolean | false |

## Workflow « On page load »

1. **Custom JavaScript** : coller le bloc **C** de [connexion.js](../actions/connexion.js).
2. Change variable value : `planning` = résultat de l'étape 1.
3. `chargement` = false.
4. **Custom JavaScript**, qui lit si l'écran d'explication a déjà été vu :
   ```js
   try { return localStorage.getItem("pointage_explication_vue") === "1"; } catch (_) { return false; }
   ```
5. `explication_vue` = résultat de l'étape 4.

Ajoute aussi un rafraîchissement : un bouton « Actualiser », ou un workflow « On app visible », qui rejoue les étapes 1 et 2.

## Ce que renvoie le serveur pour chaque carte (`mon_planning`)

| Champ | Utilisation |
|---|---|
| `site_nom`, `site_adresse` | Titre et sous-titre de la carte |
| `heure_debut`, `heure_fin` | « 07:00 – 09:00 », déjà à l'heure de Paris |
| `etat` | `a_faire`, `en_cours`, `termine` ou `manque` : couleur ou pastille |
| `affichage` | `a_pointer`, `arrivee_pointee`, `penser_depart`, `termine` ou `manque` |
| `message` | Texte à afficher tel quel (« Arrivée pointée à 07:58 », etc.) |
| `bouton` | `arrivee`, `depart` ou **null** : null = **aucun bouton** |
| `pointage_id`, `creneau_id` | Utilisés par l'action Pointer |
| `hors_planning` | Petite mention « Hors planning » |

**Aucune règle à recoder dans WeWeb** : si `bouton` est null, on n'affiche pas de bouton. Le serveur ne remplit `bouton` que pour les agents **sans NFC**, et seulement le jour même.

## Éléments

1. **Titre** : « Mon planning du jour ».
2. **Chargement** : un spinner, affiché si `chargement`.
3. **Liste répétée** (Repeat) sur `planning`. Pour chaque carte :
   - le nom du site, l'adresse et les horaires ;
   - le texte `message`, s'il n'est pas vide. Le style dépend de `affichage` :
     - `termine` → encadré **vert** ;
     - `penser_depart` → orange ;
     - `manque` → gris ;
   - un **bouton**, affiché si `bouton` n'est pas null :
     - libellé : `bouton = "arrivee"` → « Pointer l'arrivée », sinon « Pointer le départ » ;
     - désactivé si `carte_en_cours` = l'identifiant de la carte (`pointage_id` ou `creneau_id`), pour éviter le double envoi.
4. **Liste vide**, si `planning` est vide et que le chargement est fini : « Aucun créneau aujourd'hui ».
5. **Toast** : le texte `toast`, affiché 4 secondes.
6. **Popup « Localisation »**, l'écran d'explication demandé par la CNIL :
   - texte : « Pour valider votre pointage, l'application vérifie votre position **uniquement au moment où vous pointez**. Elle ne vous suit jamais. Si vous refusez, votre pointage est quand même enregistré. » ;
   - un bouton « J'ai compris ».

## Workflows

### Bouton de la carte (On click)
1. **Si `explication_vue` est faux** :
   - ouvrir la popup « Localisation » et **arrêter là**. Le bouton « J'ai compris » s'occupe de la suite.
2. `carte_en_cours` = `context.item.data.pointage_id || context.item.data.creneau_id`.
3. **Custom JavaScript** : coller [pointer.js](../actions/pointer.js).
4. `toast` = `result.message`. Par exemple « Arrivée pointée à 07:58 ✓ » ou « Pas de connexion, réessayez ».
5. Rejouer le chargement du planning (bloc C), puis `planning` = son résultat.
6. `carte_en_cours` = vide.

**Pas de confirmation avant de pointer**, comme dans Bubble.

### Bouton « J'ai compris » de la popup
1. **Custom JavaScript** :
   ```js
   try { localStorage.setItem("pointage_explication_vue", "1"); } catch (_) {}
   ```
2. `explication_vue` = true.
3. **Custom JavaScript** : coller [geolocaliser.js](../actions/geolocaliser.js). Le navigateur affiche alors sa demande d'autorisation, juste après l'explication.
4. Fermer la popup. L'agent appuie ensuite de nouveau sur son bouton.

## Ce que l'agent ne voit jamais

Les alertes, le statut de confiance, la distance. Le serveur ne les renvoie pas, et la base refuse de les lire avec une session d'agent.

## Tester

- Avec un agent `pointage_nfc = true` : les boutons apparaissent.
  - Pointer l'arrivée → « Arrivée pointée à HH:MM ✓ ».
  - Pointer de nouveau dans les 5 minutes → « Déjà pointé à HH:MM ».
- Refuser la localisation → le pointage passe quand même.
- Avec un agent `pointage_nfc = false` : aucune carte n'a de bouton.
