# Cahier des charges pour Claude Code : pointage Les Nettoyeurs (Supabase + Next.js)

> **Version 2, 12 novembre 2026.** Elle remplace le guide précédent : le choix technique est maintenant **Supabase** (base de données, authentification, fonctions serveur) et **WeWeb** (l'interface).
> **Mise à jour du 16 novembre 2026 :** l'interface n'est plus faite dans WeWeb mais en **Next.js** (dossier `web/` du dépôt), hébergée sur **Vercel**. Claude Code code donc directement le front. Le reste du cahier des charges est inchangé.
> À placer à la racine du projet sous le nom `CLAUDE.md`. Le message à envoyer à Claude Code pour démarrer est tout en bas (section 15).

---

## 1. Le besoin en une page

Les Nettoyeurs nettoie des immeubles. Ses **agents** et **volants** passent sur plusieurs **sites** par jour, selon un **planning** hebdomadaire, et doivent **pointer leur arrivée et leur départ** sur chaque site.

Aujourd'hui, ce pointage se fait dans l'application Bubble (« Léon »), avec une puce NFC collée sur chaque site. On veut une **nouvelle application de pointage**, construite avec Supabase et Next.js, qui règle deux problèmes :

1. **La triche.** Des agents pointent sans être sur place : lien de la puce copié ou partagé, mode avion, pointage fait par un collègue, etc. La triche doit devenir **difficile, et surtout visible pour l'admin**.
2. **Les agents sans NFC.** Certains téléphones n'ont pas de NFC. Ces agents ont un **bouton** pour pointer, qui utilise la **localisation**.
   - Si l'agent refuse la localisation, ou si elle ne marche pas, **le pointage passe quand même**. Il est simplement marqué « non vérifié » pour l'admin.

**Principe directeur : on ne bloque jamais un agent honnête.** On enregistre des preuves, on calcule un niveau de confiance, et l'admin tranche. L'agent ne voit jamais de message accusateur.

---

## 2. Ce que fait l'application Bubble aujourd'hui (à reproduire)

### 2.1 Données existantes dans Bubble

| Type Bubble | Champs utiles |
|---|---|
| **User** | Nom, Prénom, email, Tél. portable, `Type de contact` (Agent, Agent Container, Agent conteneurs transversal, Volant, Chef d'équipe, Chef de secteur, Admin…), `Chef d'équipe`, `Chef de Secteur`, `archive`, `date_demarrage_planning`, `Langue`, **`pointageNFC`** |
| **Site** | Nom, `Adresse` (adresse géographique avec latitude et longitude), `Chef de Secteur`, `Agents`, `Contrat-termine` |
| **User-slot-planning** (créneau récurrent) | `user`, `site`, `jour` (lundi…dimanche ; l'option a un attribut « No » = numéro du jour), `time-start`, `time-end` (seule l'heure compte), `time-interval`, `ordre`, `deplacement` (oui = trajet, pas un vrai créneau), `temps-deplacement`, `type-user`, `simulation` |
| **Volant-secteur** | `volant` (User), `chef de secteur` (User). Ce sont les secteurs sur lesquels un volant travaille. |
| **Pointage** | `user`, `site`, `date`, `prevu-date_start`, `prevu-date_end`, `prevu-temps` (min), `realise-date_start`, `realise-date_end`, `realise`, `realise-temps`, `realise-jour`, `realise-nuit` (min), `ecart-min`, `temps-deplacement`, `absence`, `apres-midi`, `valide`, `site-nom`, `user-last_name` |

**Le champ `pointageNFC` (à reprendre tel quel) :**
- **oui** = la personne **n'a pas de NFC**. Elle a les boutons de pointage dans l'appli.
- **non ou vide** = la personne pointe avec la puce NFC.
- Dans l'interface, c'est la case « N'a pas de NFC » de la fiche contact. Elle est **décochée par défaut** et s'affiche pour les **Agents et les Volants**.

### 2.2 Génération nocturne des pointages prévus

- Chaque nuit, pour chaque créneau du jour de la semaine (hors déplacement et hors simulation), un **pointage prévu** est créé :
  - heure de début et de fin prévues = le jour même, à l'heure du créneau ;
  - durée prévue = celle du créneau ;
  - temps de déplacement = repris du créneau de trajet qui précède.
- Aucun pointage n'est créé si la date de démarrage du planning de l'agent est dans le futur.
- **Correction de la veille** : si un pointage d'hier a une arrivée mais pas de départ, son temps réalisé devient le temps prévu, et l'écart est vidé.

### 2.3 Pointage par la puce NFC

- La puce contient un **lien fixe** vers la page de pointage du site (`…?site=<id du site>`). Pour les containers, le lien ajoute `&period=AM|PM`.
- À l'ouverture de la page :
  1. On cherche les pointages prévus aujourd'hui pour cet agent sur ce site.
  2. **Aucun** → on crée un pointage « hors planning » et on enregistre l'arrivée.
  3. **Plusieurs** → on prend celui dont l'heure prévue est la plus proche de maintenant.
  4. Pas d'arrivée → **arrivée**. Arrivée sans départ → **départ**.
  5. **Anti-rebond** : un deuxième scan moins de 5 minutes après l'arrivée ne fait rien.
- Au départ :
  - temps réalisé = départ − arrivée ;
  - temps de nuit = minutes avant 6 h ;
  - temps de jour = réalisé − nuit ;
  - écart = réalisé − prévu.

### 2.4 Pointage par bouton (ajouté dans Bubble en novembre 2026)

- Sur l'écran Planning de l'appli, chaque créneau **du jour** affiche :
  - « Pointer l'arrivée », de minuit jusqu'à la fin du créneau ;
  - puis « Arrivée pointée à HH:MM » et le bouton « Pointer le départ » ;
  - après la fin du créneau, si le départ n'est pas pointé : « Créneau terminé : pensez à pointer votre départ » ;
  - une fois le départ pointé, un encadré vert « Arrivée HH:MM · Départ HH:MM ».
- Si le créneau est passé sans arrivée : « Créneau terminé à HH:MM : arrivée non pointée ».
- Pas de confirmation avant de pointer. Le bouton se désactive pendant l'envoi pour éviter les doublons.
- Si le pointage prévu n'existe pas, il est créé au moment de l'arrivée.
- **Aucune vérification de position** : c'est le rôle de la nouvelle application.

### 2.5 Volants et secteurs

- Un volant ne doit voir que les sites des **secteurs** qui lui sont attribués (Volant-secteur), plus les sites où il est lui-même affecté.
- ⚠️ **Défaut de Bubble à ne pas reproduire** : un volant sans aucun secteur voit **tous** les sites. Dans la nouvelle application, un volant sans secteur ne voit **que ses propres sites**.

### 2.6 Autres défauts de Bubble à corriger

- **Temps de nuit** : Bubble calcule « 6 h − arrivée » même quand le départ a lieu avant 6 h. Par exemple, pour 4 h → 5 h 30, il compte 2 h de nuit au lieu de 1 h 30. Calcul correct : `min(départ, 6 h) − arrivée`.
- **Deux créneaux le même jour sur le même site** : dans Bubble, les deux cartes affichent le pointage du premier créneau. Chaque carte doit afficher **son** pointage, celui dont l'heure prévue correspond au créneau.
- **Lien NFC fixe** : il peut être copié et rejoué. Voir la section 5.

---

## 3. Contraintes techniques du web (à bien comprendre)

Le front Next.js produit une **application web** (éventuellement installable en PWA), pas une application native. Conséquences :

| Sujet | Ce qui est possible sur le web | Conséquence |
|---|---|---|
| **Lecture NFC** | Sur **iPhone (XS et plus récents)** et **Android**, scanner une puce qui contient un lien **ouvre ce lien dans le navigateur**, sans application. En revanche, une page web ne peut lire le NFC elle-même que sur **Chrome Android** (Web NFC). | On garde le principe « la puce ouvre une page », mais avec des **puces sécurisées** dont le lien change à chaque scan (section 5.2). Pas besoin de lire le NFC depuis la page. |
| **Localisation** | Disponible, après autorisation de l'utilisateur. Exige le HTTPS. | Utilisable pour le bouton, et en complément du NFC. |
| **Détection de fausse position GPS** | **Impossible** depuis une page web. | On compense par des contrôles côté serveur (section 5.4). |
| **Attestation que la requête vient de la vraie app** | Impossible (pas de Play Integrity ni d'App Attest sur le web). | On compense avec une **passkey** liée au téléphone (section 5.3). |
| **Identifier le téléphone** | Les passkeys (WebAuthn, avec Face ID ou empreinte) fonctionnent dans Safari et Chrome. | C'est la meilleure preuve qu'un pointage vient du téléphone de l'agent. |
| **PWA sur iPhone** | Un lien NFC s'ouvre dans **Safari**, pas dans la PWA installée. Leurs sessions sont **séparées**. | **Point clé** : la page de scan doit fonctionner dans Safari, avec sa propre session, et une reconnexion très rapide (passkey). À tester tôt. |
| **Stockage sur iPhone** | Safari peut effacer les données d'un site qui n'a pas été ouvert depuis 7 jours. | Un agent qui ne pointe pas pendant une semaine devra se reconnecter. La passkey rend ça rapide, en un geste. |
| **Hors ligne** | La page ne charge pas sans réseau. | Le pointage exige du réseau. Pas de file d'attente hors ligne en phase 1. |

> Si un jour ces limites deviennent bloquantes (fausse position, attestation), on pourra emballer l'interface dans une petite application native. La logique Supabase restera la même. Ce n'est pas prévu pour la phase 1.

---

## 4. Exigences fonctionnelles

### 4.1 Agent / volant (application mobile web)

1. **Connexion** : email et code à usage unique (OTP) reçu par email, puis **création d'une passkey** sur le téléphone. Les connexions suivantes se font avec Face ID ou l'empreinte.
2. **Mon planning du jour** : la liste des créneaux (site, adresse, horaires, état : à faire, en cours, terminé, manqué), avec les heures pointées.
3. **Pointer par la puce NFC** : l'agent scanne la puce. Le téléphone ouvre la page de scan, qui enregistre automatiquement l'arrivée ou le départ et affiche « Arrivée pointée à 07:58 ✓ ».
4. **Pointer par bouton** : réservé aux personnes dont `pointageNFC = oui`.
   - Au premier usage, on demande l'autorisation de localisation avec un écran d'explication.
   - Délai maximal de 10 s pour obtenir la position.
   - Permission refusée, délai dépassé ou position indisponible → **le pointage est quand même enregistré**, avec le statut « non vérifié ».
5. Les règles d'affichage de Bubble (section 2.4) sont reprises à l'identique.
6. **Langue** : français par défaut. Le champ `Langue` existe déjà ; la traduction est à prévoir pour plus tard.

### 4.2 Admin (back-office web, dans le front Next.js)

1. **Liste des pointages** : filtres par période, salarié, site, secteur et statut de confiance.
2. **Badge de confiance** sur chaque pointage : ✅ vérifié, ⚠️ à vérifier, ❓ non vérifié.
   - Le détail affiche :
     - la méthode (NFC ou bouton) ;
     - une carte avec la position et le site ;
     - la distance et la précision ;
     - le téléphone (passkey) utilisé ;
     - la liste des alertes.
3. **Valider ou corriger** un pointage, avec un historique de qui a changé quoi.
4. **Réglages par site** :
   - rayon autorisé (200 m par défaut) ;
   - position corrigée, si l'adresse géocodée est imprécise ;
   - puces NFC rattachées au site.
5. **Réglages par salarié** :
   - case « N'a pas de NFC » ;
   - secteurs (pour les volants) ;
   - téléphones enregistrés : voir et révoquer une passkey, par exemple lors d'un changement de téléphone.
6. **Exports** : en phase 1, on garde les exports PDF de Bubble. Ils seront refaits plus tard.

---

## 5. Anti-triche (le cœur du projet)

### 5.1 L'heure vient toujours du serveur

- L'heure enregistrée est `now()` dans Postgres, au moment où Supabase reçoit l'action. **L'heure du téléphone n'est jamais utilisée.**
- Le téléphone envoie quand même son heure, à titre d'indice : un écart de plus de 2 minutes déclenche l'alerte `DEVICE_CLOCK_SKEW`.
- **Les agents ne peuvent pas écrire dans les tables de pointage.** Les règles RLS l'interdisent. Toute action passe par une **Edge Function** (ou une fonction SQL `SECURITY DEFINER`), qui fait les contrôles.

### 5.2 Des puces NFC impossibles à copier : NTAG 424 DNA avec SUN

- On remplace les puces actuelles par des **NTAG 424 DNA**, avec la fonction **SUN / SDM** (Secure Dynamic Messaging) activée.
  - À chaque scan, la puce produit un lien **différent** : `https://<app>/scan?picc=<identifiant + compteur chiffrés>&cmac=<signature>`.
  - Le téléphone (iPhone ou Android) ouvre ce lien.
- Une **Edge Function** `nfc-scan` :
  1. déchiffre `picc` (AES-128) avec la clé de la puce et en extrait l'identifiant de la puce (UID) et le compteur ;
  2. recalcule et vérifie la signature `cmac` (AES-CMAC) ;
  3. **refuse tout compteur inférieur ou égal au dernier compteur enregistré** pour cette puce : un lien copié, partagé ou mis en favori ne marche qu'une seule fois, au moment du vrai scan ;
  4. retrouve le site de la puce, puis applique la logique de la section 9.
- Les **clés AES** de chaque puce sont stockées chiffrées (Supabase Vault). Elles ne quittent jamais le serveur.
- **Puces anciennes (lien fixe)** : acceptées pendant la transition, mais chaque pointage fait avec l'une d'elles reçoit l'alerte `STATIC_TAG` (puce non sécurisée).
- **Délai entre scan et envoi** : la page de scan doit envoyer le lien **immédiatement** à l'ouverture.
  - Si le même lien arrive une seconde fois → `REPLAYED_TAG`, rien n'est enregistré, et l'agent voit simplement l'état actuel de son pointage.
- Prix indicatif : 1 à 3 € la puce. Pour les programmer, l'admin a besoin d'un téléphone Android et d'un outil de programmation (l'application NXP TagXplorer, ou un petit outil fourni plus tard). Une procédure écrite est à prévoir.
- **Implémentation** :
  - AES-CMAC n'existe pas directement dans Web Crypto. Il faut l'implémenter (sous-clés + AES-CBC) ou utiliser une bibliothèque Deno ou npm éprouvée.
  - **Tester avec les vecteurs officiels de NXP** (note d'application AN12196).

### 5.3 Le pointage est lié au téléphone de l'agent : passkey

- À la première connexion, l'agent crée une **passkey** (WebAuthn) sur son téléphone, protégée par Face ID ou l'empreinte.
- **Chaque pointage** (NFC ou bouton) est **signé** avec cette passkey : un défi (challenge) unique fourni par le serveur, puis une vérification dans l'Edge Function, par exemple avec `@simplewebauthn/server`.
  - Côté front, cela passe par l'API WebAuthn du navigateur (par exemple `@simplewebauthn/browser`).
- Conséquences :
  - **Pointer à la place d'un collègue** suppose d'avoir son téléphone **et** de le déverrouiller. C'est le « buddy punching » qu'on veut empêcher.
  - Une passkey utilisée par **deux agents** la même journée est impossible. En revanche, **un même téléphone** avec deux comptes déclenche l'alerte `SHARED_DEVICE`.
  - **Nouveau téléphone** : il est accepté, mais l'alerte `NEW_DEVICE` est levée et l'admin est prévenu (à confirmer, section 13).
- **Si la passkey échoue ou n'est pas disponible** (téléphone trop ancien) : on ne bloque pas. Le pointage est enregistré avec la session normale et l'alerte `NO_DEVICE_PROOF`.

### 5.4 Localisation

- La position est demandée **au moment du pointage** (bouton, et aussi après un scan NFC si l'autorisation a déjà été donnée), en haute précision, sans position en cache (`maximumAge: 0`), avec un délai de 10 s.
- Le serveur calcule la distance au site (PostGIS `ST_Distance` sur `geography`, ou formule de Haversine) :
  - distance ≤ rayon du site → OK ;
  - distance > rayon → `OUT_OF_ZONE` (on garde la distance en mètres) ;
  - précision > 150 m → `LOW_ACCURACY` (on ne conclut rien sur la zone) ;
  - pas de position → `NO_LOCATION`.
- **Fausse position GPS** : elle est indétectable sur le web. On repère les **motifs suspects** côté serveur :
  - exactement les mêmes coordonnées, à 6 décimales près, d'un pointage à l'autre ou d'un jour à l'autre → `IDENTICAL_COORDS` (un vrai GPS varie toujours un peu) ;
  - précision anormalement ronde ou identique à chaque fois ;
  - déplacement impossible entre deux pointages, par exemple 20 km en 3 minutes → `IMPOSSIBLE_TRAVEL`.

### 5.5 Mode avion et hors ligne

- Sans réseau, rien n'est enregistré : l'agent voit « Pas de connexion, réessayez ». Avec les puces sécurisées, on ne peut pas tricher en différant l'envoi : l'heure prise est celle de la réception par le serveur, et le lien ne sert qu'une fois.
- Pour la phase 1, **pas de file d'attente hors ligne**. Si des sites n'ont pas de réseau (sous-sols, parkings), il faut les lister. On envisagera alors une solution dédiée.

### 5.6 Statut de confiance

| Statut | Règle |
|---|---|
| ✅ **Vérifié** | (NFC sécurisé valide **ou** bouton avec position dans la zone et précision correcte) **et** passkey valide **et** aucune alerte grave |
| ⚠️ **À vérifier** | au moins une alerte grave : `OUT_OF_ZONE`, `DEVICE_CLOCK_SKEW`, `SHARED_DEVICE`, `IDENTICAL_COORDS`, `IMPOSSIBLE_TRAVEL`, `REPLAYED_TAG` (tentative) |
| ❓ **Non vérifié** | aucune preuve de présence (`NO_LOCATION`, `LOW_ACCURACY`, `STATIC_TAG`) ou aucune preuve du téléphone (`NO_DEVICE_PROOF`, `NEW_DEVICE`), sans alerte grave |

- Les alertes sont stockées sous forme de **liste de codes**, avec le détail en JSON.
- **L'agent ne voit jamais les alertes.**
- Le calcul se fait dans **une seule fonction SQL testée**, réutilisée partout.

### 5.7 Ce qu'on ne fait pas

- Pas de suivi GPS en continu.
- Pas de blocage automatique.
- Pas de selfie en phase 1 (possible plus tard).

---

## 6. RGPD et droit du travail

- La géolocalisation des salariés est encadrée par la CNIL. On la collecte **uniquement au moment du pointage**.
  - **Informer les salariés** par une note écrite et un écran d'explication dans l'appli.
  - Consulter le CSE s'il existe.
- Durée de conservation : on garde les **coordonnées précises 2 mois maximum** (à valider). Ensuite, on ne garde que la distance et le statut. Une tâche `pg_cron` fait la purge.
- Hébergement : le projet Supabase doit être en **région UE** (Francfort, Paris ou Irlande).
- Une page « Mes pointages » permet au salarié de voir ses propres données.

---

## 7. Architecture

```
Puce NTAG 424 ──scan──▶ navigateur du téléphone (Safari / Chrome)
                               │ ouvre https://<app>/scan?picc=…&cmac=…
                               ▼
                 ┌───────────────────────────┐
                 │ Next.js (front, Vercel)   │  pages : connexion, planning du jour,
                 │ agents + back-office admin│  scan, admin pointages, réglages
                 └────────────┬──────────────┘
                              │ supabase-js (session) + appels Edge Functions
                              ▼
                 ┌───────────────────────────┐
                 │ Supabase (région UE)      │
                 │ • Auth (OTP email)        │
                 │ • Postgres + RLS + PostGIS│
                 │ • Edge Functions (Deno) : │
                 │   nfc-scan, pointer,      │
                 │   passkey-*, sync-bubble  │
                 │ • pg_cron : génération,   │
                 │   correction, purge, sync │
                 │ • Vault : clés des puces  │
                 └────────────┬──────────────┘
                              │ synchronisation (phase 1)
                              ▼
                 ┌───────────────────────────┐
                 │ Bubble (Léon)             │  salariés, sites, planning, secteurs
                 └───────────────────────────┘
```

### 7.1 Répartition des rôles

- **Supabase porte toute la logique** : calculs, choix du pointage, anti-triche, statut de confiance.
- **Le front Next.js ne fait qu'afficher et appeler** les fonctions de Supabase. **Aucune règle métier dans le front**, pour qu'elle reste testable et impossible à contourner.

### 7.2 Ce que Claude Code peut faire, et comment

- **Côté Supabase** : tout le travail, en code versionné dans le dépôt :
  - les migrations SQL dans `supabase/migrations` ;
  - les règles RLS ;
  - les fonctions SQL ;
  - les Edge Functions dans `supabase/functions` ;
  - les tâches `pg_cron` ;
  - les tests (pgTAP pour le SQL, `deno test` pour les fonctions) ;
  - les données de test (`seed.sql`).
- Claude Code utilise la **CLI Supabase** : `supabase start` pour le local, `supabase db push` et `supabase functions deploy` pour le déploiement.
- **Côté front (Next.js, dossier `web/`)** : Claude Code code directement les pages, les composants et les appels à Supabase (`@supabase/ssr`), avec des tests. Le front n'utilise que la clé `anon` et ne contient aucune règle métier. Il est déployé sur Vercel (région Paris).

### 7.3 Lien avec Bubble (phase 1 : Bubble reste la référence)

- **Lecture** : chaque nuit, et à la demande, l'Edge Function `sync-bubble` copie depuis Bubble les salariés, les sites (avec latitude et longitude), les créneaux et les secteurs des volants. La copie se fait par `bubble_id` et ne crée pas de doublons.
  - Dans Bubble, l'**API Data est désactivée** aujourd'hui. Deux possibilités :
    - (a) l'activer, avec des règles de confidentialité adaptées ;
    - (b) **(recommandé)** créer dans Bubble des **workflows API** protégés par une clé, qui renvoient ces listes. L'API Workflow est déjà active.
- **Écriture** : chaque pointage réalisé est renvoyé à Bubble par un workflow API (par exemple `pointage-externe`), avec ses heures et ses temps calculés. Ainsi la page Pointages de Bubble, ses exports PDF et l'affichage des heures sur le Planning de Léon continuent de fonctionner.
  - Il faut ajouter dans Bubble, sur Pointage, les champs `methode` et `verification`.
  - On ajoute aussi une **file de renvoi** : si Bubble ne répond pas, Supabase réessaie plus tard.
- **Comptes** : à la première connexion, l'email Supabase Auth est rapproché de l'email Bubble. Un email absent de Bubble, ou un compte archivé, ne peut pas se connecter.
- **Pendant la transition**, les deux systèmes ne doivent pas créer chacun leurs propres pointages prévus. Il faut choisir **un seul générateur**. Recommandation : Supabase génère les pointages prévus, et on désactive la tâche nocturne de Bubble au moment de basculer.

---

## 8. Modèle de données (Supabase)

```sql
-- Référentiel (copié depuis Bubble)
profiles        (id uuid → auth.users, bubble_id unique, email, nom, prenom, telephone,
                 type_contact, chef_equipe_id, chef_secteur_id, archive bool,
                 date_demarrage_planning date, langue, pointage_nfc bool default false,  -- true = n'a PAS de NFC
                 role 'agent'|'volant'|'admin'|'chef_secteur'|'chef_equipe')
sites           (id, bubble_id unique, nom, adresse, geo geography(Point,4326),
                 geo_corrige geography(Point,4326), rayon_m int default 200,
                 chef_secteur_id, contrat_termine bool)
site_agents     (site_id, profile_id)
volant_secteurs (volant_id, chef_secteur_id)
creneaux        (id, bubble_id unique, profile_id, site_id, jour_semaine smallint 1..7,
                 heure_debut time, heure_fin time, duree_min, ordre, deplacement bool,
                 temps_deplacement_min, simulation bool)

-- Pointage
pointages       (id, bubble_id, profile_id, site_id, creneau_id null, date_jour date,
                 prevu_debut timestamptz, prevu_fin timestamptz, prevu_min,
                 arrivee_at timestamptz, depart_at timestamptz,
                 realise_min, realise_nuit_min, realise_jour_min, ecart_min, temps_deplacement_min,
                 hors_planning bool, absence, valide bool,
                 statut_confiance 'verifie'|'a_verifier'|'non_verifie',
                 bubble_sync_at timestamptz, bubble_sync_error text,
                 unique (profile_id, site_id, date_jour, prevu_debut))
evenements_pointage (id, pointage_id, type 'arrivee'|'depart'|'ignore', methode 'nfc'|'bouton',
                 server_at timestamptz default now(), device_at timestamptz,
                 lat, lng, precision_m, distance_m,
                 nfc_tag_id, nfc_compteur, passkey_id, user_agent, ip,
                 alertes text[], details jsonb)

-- Anti-triche
nfc_tags        (id, site_id, uid, type 'statique'|'ntag424', cle_vault_id, dernier_compteur int, actif bool)
passkeys        (id, profile_id, credential_id unique, public_key, counter, appareil, created_at, last_used_at, revoque bool)
challenges      (id, profile_id, challenge, expires_at, used bool)

-- Admin
audit_admin     (id, admin_id, pointage_id, action, avant jsonb, apres jsonb, at)
reglages        (cle, valeur)  -- rayon par défaut, seuils, durée de conservation
```

**RLS (obligatoire sur toutes les tables) :**
- Un agent ou un volant **lit** son profil, ses créneaux et ses pointages. Il **ne peut rien écrire** dans `pointages` ni dans `evenements_pointage`.
- Un volant lit les sites de ses secteurs et ceux où il est affecté. **Sans secteur, il ne voit que ses sites.**
- Les chefs de secteur et d'équipe lisent les pointages de leur périmètre.
- Un admin lit tout. Ses corrections passent par une fonction qui écrit dans `audit_admin`.

---

## 9. Logique métier (fonctions SQL ou Edge Functions, toutes testées)

**Fuseau horaire** : tous les calculs « aujourd'hui », « avant 6 h » et « heure du créneau » se font en **Europe/Paris**, avec `AT TIME ZONE 'Europe/Paris'`. Postgres stocke tout en `timestamptz`.

### 9.1 Génération des pointages prévus

- `generer_pointages(date)` :
  - pour chaque créneau du jour de la semaine, hors déplacement et hors simulation ;
  - dont le profil est actif (non archivé) et dont la date de démarrage est passée ;
  - on crée le pointage prévu, avec les heures du créneau ce jour-là, à l'heure de Paris.
- **Idempotent** : la contrainte d'unicité empêche les doublons, et l'insertion utilise `on conflict do nothing`.
- **Planification** : `pg_cron` fonctionne en UTC. On lance la tâche **toutes les heures**, et la fonction génère pour la date du jour à Paris. Grâce à l'idempotence, les relances ne posent pas de problème, y compris lors des changements d'heure.
- **Créneau qui passe minuit** (fin < début) : la fin est fixée au lendemain. À confirmer s'il en existe.

### 9.2 Choix du pointage lors d'une action

- `traiter_pointage(profile, site, methode, preuves)` :
  1. On cherche les pointages prévus aujourd'hui pour ce profil sur ce site.
     - Avec le bouton, l'appli envoie l'identifiant du pointage ou du créneau de la carte. Le serveur vérifie qu'il appartient à l'agent et qu'il est du jour.
  2. **Aucun** → on crée un pointage `hors_planning` et on enregistre l'arrivée. L'alerte `SITE_NOT_PLANNED` n'est levée que si le site n'est pas du tout dans le planning de l'agent.
  3. **Plusieurs** → on garde, parmi ceux qui ne sont pas terminés, celui dont l'heure prévue est la plus proche de maintenant.
  4. Pas d'arrivée → **arrivée**.
  5. Arrivée sans départ :
     - si l'arrivée date de moins de 5 min → on ignore et on répond « déjà pointé à HH:MM » ;
     - sinon → **départ**.
  6. Arrivée et départ déjà enregistrés → on renvoie l'état, sans rien modifier.
- **Pas de doublon en cas de double clic** : la fonction verrouille la ligne avec `select … for update`, ou utilise un verrou consultatif par profil.

### 9.3 Calculs au départ

| Valeur | Calcul |
|---|---|
| `realise_min` | arrondi(départ − arrivée), en minutes |
| `realise_nuit_min` | si l'arrivée est avant 6 h (heure de Paris) : `min(départ, 6 h) − arrivée` ; sinon 0 |
| `realise_jour_min` | `realise_min − realise_nuit_min` |
| `ecart_min` | `realise_min − prevu_min` (vide si hors planning) |

### 9.4 Correction de la nuit

- Chaque nuit, tout pointage de la veille qui a une arrivée mais pas de départ reçoit :
  - `realise_min = prevu_min`, un écart vide, et la nuit et le jour recalculés ;
  - l'alerte `NO_DEPARTURE`.

### 9.5 Agents Container

- Un pointage par jour et par demi-journée (matin ou après-midi), selon la puce `period=AM|PM`, sans planning.
- **Hors périmètre en phase 1** (à confirmer).

---

## 10. API exposée au front

| Appel | Rôle |
|---|---|
| `rpc mon_planning(date)` | Créneaux du jour, avec le pointage de chaque carte et son état d'affichage |
| `POST /functions/v1/passkey-register-options` / `-verify` | Création d'une passkey |
| `POST /functions/v1/passkey-auth-options` | Défi à signer avant un pointage |
| `POST /functions/v1/nfc-scan` | `{ picc, cmac }` ou `{ site }` (ancienne puce), `{ passkeyAssertion?, location?, deviceTime }` → `{ action, pointage, message }` |
| `POST /functions/v1/pointer` | `{ pointageId \| creneauId, passkeyAssertion?, location?, deviceTime }` → `{ action, pointage, message }` |
| `rpc admin_pointages(filtres)` / `admin_corriger_pointage(id, valeurs, motif)` | Back-office |
| `POST /functions/v1/sync-bubble` | Synchronisation (appelée par `pg_cron` et à la demande) |

**Règles communes :**
- Limite de 10 actions de pointage par minute et par agent.
- Un défi passkey n'est valable que **60 s** et **une seule fois**.
- **Aucun secret dans le front.** Le front n'utilise que la clé publique (`anon`) de Supabase. Les autres secrets restent dans les variables d'environnement des Edge Functions : clé `service_role`, clé de l'API Bubble, clés des puces.

---

## 11. Parcours de la page de scan (le plus délicat)

1. La puce ouvre `https://<app>/scan?picc=…&cmac=…` dans Safari ou Chrome.
2. La page **envoie tout de suite** `picc` et `cmac` à `nfc-scan`, qui **réserve** ce compteur. Elle n'attend pas la connexion de l'agent, pour qu'un lien copié devienne inutilisable.
3. **Si l'agent est connecté** :
   - la page demande la passkey (Face ID) et la position (si l'autorisation a déjà été donnée, avec 5 s maximum) ;
   - elle finalise le pointage ;
   - elle affiche le résultat.
4. **S'il n'est pas connecté** :
   - la page affiche une connexion rapide (passkey, sinon code par email), puis finalise le scan réservé ;
   - la réservation est valable **10 minutes**. Passé ce délai, l'agent doit rescanner.
5. Dans tous les cas, l'agent voit un message simple : « Arrivée pointée à 07:58 ✓ », « Départ pointé à 10:02 ✓ » ou « Déjà pointé à 07:58 ».

---

## 12. Plan par phases (chaque phase = une PR testable)

**Phase 0 : socle**
- Projet Supabase (région UE), CLI, migrations, RLS, seed de test.
- Fonctions SQL pures avec tests pgTAP :
  - calculs de temps ;
  - choix du pointage ;
  - distance et zone ;
  - statut de confiance ;
  - génération idempotente.
- ✅ `supabase test db` passe et couvre tous les cas de la section 14.

**Phase 1 : bouton + localisation + Bubble**
- `sync-bubble` en lecture, et renvoi des pointages vers Bubble (version **Test** de Bubble d'abord).
- Edge Function `pointer` ; connexion par code email.
- Front Next.js :
  - pages connexion, planning du jour, admin pointages et réglages site ;
  - fiches de montage ;
  - composant de localisation.
- ✅ Un agent de test pointe avec le bouton. Le pointage apparaît avec le bon statut dans l'admin du front **et** dans la page Pointages de Bubble (Test).

**Phase 2 : puces sécurisées + passkeys**
- `nfc-scan` avec la vérification SUN/CMAC (testée sur les vecteurs NXP), anti-rejeu par compteur, page de scan.
- Mode de compatibilité pour les anciennes puces ; procédure de programmation des puces.
- Passkeys : création, signature de chaque pointage, alertes `NEW_DEVICE` et `SHARED_DEVICE`, révocation par l'admin.
- ✅ Un lien de puce rejoué est refusé. Un pointage fait depuis un autre téléphone est signalé. Les parcours iPhone (Safari) et Android (Chrome) sont testés sur de vrais téléphones.

**Phase 3 : fiabilisation**
- Détection des motifs suspects (coordonnées identiques, déplacement impossible).
- Rappels (email ou notification).
- Exports.
- Purge RGPD.
- Bascule complète de la génération nocturne vers Supabase.

---

## 13. Décisions à prendre (Claude Code doit les poser si elles ne sont pas tranchées)

1. **Bubble reste-t-il la référence** pour les salariés, les sites et le planning (recommandé en phase 1) ?
2. **Connexion** : code par email, ou SMS (payant, mais plus simple pour certains agents) ?
3. **Nouveau téléphone** : accepté avec un signalement (recommandé), ou approbation obligatoire de l'admin ?
4. **Rayon par défaut** (200 m ?) et **durée de conservation** des positions (2 mois ?).
5. **Budget et pose des puces NTAG 424 DNA** : combien de sites, et qui les programme ?
6. **Agents Container** : dans le périmètre ou pas ?
7. Existe-t-il des **créneaux qui passent minuit**, et des **sites sans réseau** ?

---

## 14. Cas de test indispensables

- Arrivée puis départ sur un créneau normal → temps réalisé, jour, nuit et écart corrects.
- Arrivée 5 h 00, départ 7 h 00 → 60 min de nuit et 60 min de jour.
- Arrivée 4 h 00, départ 5 h 30 → **90 min de nuit** (Bubble en comptait 120).
- Deux créneaux le même jour sur le même site → chaque carte affiche son pointage, et un scan choisit le bon selon l'heure.
- Site absent du planning → pointage hors planning.
- Deux actions à moins de 5 min d'intervalle → la seconde est ignorée.
- Double clic ou deux requêtes simultanées → un seul pointage.
- Position à 150 m → vérifié ; à 2 km → à vérifier ; précision de 400 m, ou permission refusée → non vérifié, **mais enregistré**.
- Heure du téléphone décalée de 10 min → `DEVICE_CLOCK_SKEW`, et l'heure enregistrée reste celle du serveur.
- Lien SUN rejoué (même compteur) → aucun pointage + `REPLAYED_TAG`. Ancienne puce → `STATIC_TAG`.
- Pointage sans passkey → `NO_DEVICE_PROOF` ; même téléphone pour deux comptes → `SHARED_DEVICE`.
- Volant sans secteur → ne voit que ses sites. Volant avec le secteur X → sites de X + les siens.
- `pointage_nfc = false` → aucun bouton ; `true` → boutons visibles.
- Pas de départ → correction nocturne + `NO_DEPARTURE`.
- Changements d'heure (dernier dimanche de mars et d'octobre) → calculs justes.
- Relancer la génération ou la synchronisation → aucun doublon.
- Agent archivé dans Bubble → ne peut plus pointer après la synchronisation.

---

## 15. Message à envoyer à Claude Code pour démarrer

> Copier-coller ceci dans Claude Code, dans un dossier vide qui contient ce fichier sous le nom `CLAUDE.md` :

```
Lis entièrement CLAUDE.md : c'est le cahier des charges d'une application de pointage
(Supabase + Next.js) pour l'entreprise Les Nettoyeurs.

Règles de travail :
- Toute la logique métier et l'anti-triche vont dans Supabase (SQL, RLS, Edge Functions),
  jamais dans le front Next.js, qui ne fait qu'afficher et appeler.
- Travaille phase par phase (section 12). À chaque phase : un plan court, le code,
  les tests, puis un résumé de ce qui est testé et de ce qui reste.
- Le front est en Next.js (dossier web/), déployé sur Vercel : code-le directement,
  avec des tests, sans y mettre de règle métier.
- Ne fais jamais confiance à l'heure ni à la position envoyées par le téléphone.
- Aucun secret dans le code ni dans le front : variables d'environnement et Vault.
- Teste toujours avec la version Test de Bubble, jamais Live.
- Si une décision de la section 13 n'est pas tranchée et bloque, pose-moi la question
  avant de coder.

Commence par la phase 0 : propose la structure du dépôt et le schéma SQL, puis
attends ma validation avant d'écrire les migrations.
```
