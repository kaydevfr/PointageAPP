# Fiche 01 : page « Connexion »

**But** : l'agent saisit son email, reçoit un code à 6 chiffres, le tape, et arrive sur son planning.

## Page

- Nom : `Connexion`, URL : `/connexion`.
- **Non protégée** : accessible sans être connecté.

## Variables (onglet Data → Variables)

| Nom | Type | Valeur initiale |
|---|---|---|
| `email` | Text | vide |
| `code` | Text | vide |
| `etape` | Text | `email` |
| `message` | Text | vide |
| `envoi_en_cours` | Boolean | false |

## Éléments

1. **Logo et titre** : « Pointage Les Nettoyeurs ».
2. **Bloc « Étape email »**, affiché si `etape = "email"` :
   - un champ Email, lié à la variable `email`. Type `email`, autocomplétion `email` ;
   - un bouton **« Recevoir mon code »**, désactivé si `envoi_en_cours`.
3. **Bloc « Étape code »**, affiché si `etape = "code"` :
   - le texte « Code envoyé à {email} » ;
   - un champ Code, lié à `code`. Type numérique, 6 caractères, autocomplétion `one-time-code` : sur iPhone, le code se propose alors tout seul ;
   - un bouton **« Valider »**, désactivé si `envoi_en_cours` ;
   - un lien « Changer d'adresse », qui remet `etape` à `email`.
4. **Texte `message`**, affiché s'il n'est pas vide, en rouge discret (jamais de ton accusateur).

## Workflows

### Bouton « Recevoir mon code » (On click)
1. Change variable value : `envoi_en_cours` = true.
2. **Custom JavaScript** : coller le bloc **A** de [connexion.js](../actions/connexion.js).
3. Change variable value : `message` = `result.message` (résultat de l'étape 2).
4. True/False split sur `result.ok` :
   - vrai → `etape` = `code` ;
   - faux → rien de plus (le message est affiché).
5. Change variable value : `envoi_en_cours` = false.

### Bouton « Valider » (On click)
1. `envoi_en_cours` = true.
2. **Custom JavaScript** : coller le bloc **B** de [connexion.js](../actions/connexion.js).
3. True/False split sur `result.ok` :
   - vrai → **Navigate to** page `Planning` ;
   - faux → `message` = `result.message`.
4. `envoi_en_cours` = false.

## Points d'attention

- **Email inconnu ou archivé** : le serveur refuse, et l'agent voit « Cette adresse email n'est pas reconnue… ».
- **Passkey (Face ID ou empreinte)** : elle s'ajoutera en phase 2, après la validation du code.
- **Avertissement Safari** : il efface les données d'un site non ouvert depuis 7 jours. L'agent devra alors redemander un code.
