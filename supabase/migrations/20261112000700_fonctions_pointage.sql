-- =====================================================================
-- 07 — Logique de pointage : génération, choix, action, correction,
--      anti-rejeu NFC, purge, planning de l'agent.
--
-- Convention : la logique est dans private.* et reçoit l'instant courant
-- en paramètre (p_maintenant) pour être testable. Les fonctions public.*
-- sont de simples enveloppes qui passent now() : l'heure vient TOUJOURS
-- du serveur, jamais du téléphone.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Lectures tolérantes des preuves envoyées par l'Edge Function :
-- une valeur malformée devient null au lieu de bloquer le pointage.
-- ---------------------------------------------------------------------
create function private.essai_timestamptz(p text) returns timestamptz
language plpgsql stable set search_path = '' as $$
begin
  return nullif(p, '')::timestamptz;
exception when others then
  return null;
end $$;

create function private.essai_float(p text) returns double precision
language plpgsql immutable set search_path = '' as $$
begin
  return nullif(p, '')::double precision;
exception when others then
  return null;
end $$;

create function private.essai_int(p text) returns int
language plpgsql immutable set search_path = '' as $$
begin
  return nullif(p, '')::int;
exception when others then
  return null;
end $$;

create function private.essai_uuid(p text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  return nullif(p, '')::uuid;
exception when others then
  return null;
end $$;

create function private.essai_inet(p text) returns inet
language plpgsql immutable set search_path = '' as $$
begin
  return nullif(p, '')::inet;
exception when others then
  return null;
end $$;

create function private.fusion_alertes(p_a text[], p_b text[]) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array(select distinct x from unnest(coalesce(p_a, '{}') || coalesce(p_b, '{}')) x
                        where x is not null order by 1), '{}')
$$;

-- ---------------------------------------------------------------------
-- Pointages prévus pour une date (§9.1), sans rien écrire.
--   - créneaux du jour ISO, hors déplacement, hors simulation, actifs ;
--   - profil non archivé, date de démarrage atteinte ; site sous contrat ;
--   - fin < début : le créneau passe minuit, la fin est le lendemain ;
--   - temps de déplacement : celui du créneau de trajet qui précède
--     immédiatement (même jour, ordre inférieur, sans vrai créneau entre).
-- ---------------------------------------------------------------------
create function private.pointages_prevus(p_date date, p_profile_id uuid default null)
returns table (
  profile_id            uuid,
  site_id               uuid,
  creneau_id            uuid,
  date_jour             date,
  prevu_debut           timestamptz,
  prevu_fin             timestamptz,
  prevu_min             int,
  temps_deplacement_min int
)
language sql stable set search_path = '' as $$
  select c.profile_id, c.site_id, c.id, p_date, h.debut, h.fin,
         coalesce(c.duree_min, private.minutes_entre(h.debut, h.fin)),
         coalesce(t.temps, c.temps_deplacement_min)
    from public.creneaux c
    join public.profiles p on p.id = c.profile_id
    join public.sites s    on s.id = c.site_id
   cross join lateral (
         select private.a_paris(p_date, c.heure_debut) as debut,
                private.a_paris(case when c.heure_fin < c.heure_debut then p_date + 1 else p_date end,
                                c.heure_fin) as fin
   ) h
    left join lateral (
         select coalesce(tr.temps_deplacement_min, tr.duree_min) as temps
           from public.creneaux tr
          where tr.profile_id = c.profile_id
            and tr.jour_semaine = c.jour_semaine
            and tr.deplacement and tr.actif and not tr.simulation
            and tr.ordre < c.ordre
            and not exists (
                  select 1 from public.creneaux x
                   where x.profile_id = c.profile_id
                     and x.jour_semaine = c.jour_semaine
                     and not x.deplacement and x.actif and not x.simulation
                     and x.ordre > tr.ordre and x.ordre < c.ordre)
          order by tr.ordre desc
          limit 1
   ) t on true
   where c.jour_semaine = extract(isodow from p_date)
     and not c.deplacement
     and not c.simulation
     and c.actif
     and not p.archive
     and (p.date_demarrage_planning is null or p.date_demarrage_planning <= p_date)
     and not s.contrat_termine
     and (p_profile_id is null or c.profile_id = p_profile_id)
$$;

-- Génération idempotente : la contrainte d'unicité empêche les doublons.
create function private.generer_pointages(p_date date) returns int
language plpgsql set search_path = '' as $$
declare
  v_nb int;
begin
  insert into public.pointages
         (profile_id, site_id, creneau_id, date_jour, prevu_debut, prevu_fin, prevu_min, temps_deplacement_min)
  select pp.profile_id, pp.site_id, pp.creneau_id, pp.date_jour, pp.prevu_debut, pp.prevu_fin,
         pp.prevu_min, pp.temps_deplacement_min
    from private.pointages_prevus(p_date) pp
      on conflict on constraint pointages_unicite do nothing;
  get diagnostics v_nb = row_count;
  return v_nb;
end $$;

-- ---------------------------------------------------------------------
-- Un pointage peut-il encore recevoir une action ?
--   - tous ceux du jour (Paris) ;
--   - ceux de la veille encore ouverts dont la fin prévue (+ délai) n'est
--     pas passée : créneaux qui passent minuit.
-- La correction de nuit traite exactement le complément.
-- ---------------------------------------------------------------------
create function private.est_actionnable(
  p_date_jour date, p_depart_at timestamptz, p_prevu_fin timestamptz, p_maintenant timestamptz
) returns boolean
language sql stable set search_path = '' as $$
  select p_date_jour = private.date_paris(p_maintenant)
      or (    p_date_jour = private.date_paris(p_maintenant) - 1
          and p_depart_at is null
          and p_prevu_fin is not null
          and p_maintenant < p_prevu_fin
                + make_interval(hours => private.reglage_num('delai_depart_apres_fin_h')::int))
$$;

-- ---------------------------------------------------------------------
-- Choix du pointage pour un scan sur un site (§9.2, étapes 1 à 3)
--   1. un pointage en cours (arrivée sans départ) est prioritaire :
--      on referme ce qu'on a ouvert ;
--   2. sinon le pointage non terminé dont l'heure prévue est la plus
--      proche de maintenant ;
--   3. les pointages terminés en dernier (pour renvoyer leur état).
-- Renvoie null si aucun : l'appelant crée un pointage hors planning.
-- ---------------------------------------------------------------------
create function private.choisir_pointage(p_profile_id uuid, p_site_id uuid, p_maintenant timestamptz)
returns uuid
language sql stable set search_path = '' as $$
  select p.id
    from public.pointages p
   where p.profile_id = p_profile_id
     and p.site_id = p_site_id
     and private.est_actionnable(p.date_jour, p.depart_at, p.prevu_fin, p_maintenant)
   order by (p.arrivee_at is not null and p.depart_at is null) desc,
            (p.depart_at is not null) asc,
            abs(extract(epoch from (coalesce(p.prevu_debut, p.arrivee_at) - p_maintenant))) asc nulls last,
            p.created_at
   limit 1
$$;

-- ---------------------------------------------------------------------
-- Action de pointage (arrivée, départ ou rien), §9.2
--
-- Appelée par les Edge Functions `pointer` et `nfc-scan` APRÈS leurs
-- propres vérifications (passkey, signature SUN). p_preuves :
--   lat, lng, precision_m   position (facultative)
--   device_at               heure du téléphone (indice seulement)
--   passkey_id              passkey vérifiée par l'Edge Function (sinon absent)
--   appareil_id             identifiant aléatoire gardé par le navigateur
--   nfc_tag_id, nfc_compteur puce lue (NFC) ; absent = ancienne puce sans fiche
--   user_agent, ip
--
-- Bouton : p_pointage_id ou p_creneau_id (carte du planning), p_site_id ignoré.
-- NFC    : p_site_id (déduit de la puce par l'Edge Function).
--
-- La réponse ne contient JAMAIS les alertes ni le statut de confiance.
-- ---------------------------------------------------------------------
create function private.traiter_pointage(
  p_profile_id  uuid,
  p_site_id     uuid,
  p_methode     public.methode_pointage,
  p_pointage_id uuid,
  p_creneau_id  uuid,
  p_preuves     jsonb,
  p_maintenant  timestamptz
) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_preuves      jsonb := coalesce(p_preuves, '{}'::jsonb);
  v_lat          double precision := private.essai_float(v_preuves ->> 'lat');
  v_lng          double precision := private.essai_float(v_preuves ->> 'lng');
  v_precision    double precision := private.essai_float(v_preuves ->> 'precision_m');
  v_device_at    timestamptz      := private.essai_timestamptz(v_preuves ->> 'device_at');
  v_passkey_id   uuid             := private.essai_uuid(v_preuves ->> 'passkey_id');
  v_appareil_id  text             := nullif(v_preuves ->> 'appareil_id', '');
  v_tag_id       uuid             := private.essai_uuid(v_preuves ->> 'nfc_tag_id');
  v_aujourdhui   date             := private.date_paris(p_maintenant);
  v_profil       public.profiles;
  v_p            public.pointages;
  v_tag          public.nfc_tags;
  v_passkey      public.passkeys;
  v_pos          record;
  v_temps        record;
  v_nb           int;
  v_alertes      text[] := '{}';
  v_presence     boolean := false;
  v_appareil     boolean := false;
  v_type         public.type_evenement;
  v_statut       public.statut_confiance;
  v_action       text;
  v_message      text;
  v_evenement_id bigint;
begin
  -- Un seul traitement à la fois par agent : double clic, requêtes simultanées.
  perform pg_advisory_xact_lock(hashtextextended('pointage:' || p_profile_id::text, 0));

  select * into v_profil from public.profiles where id = p_profile_id;
  if not found or v_profil.archive then
    return jsonb_build_object('action', 'refuse', 'code', 'PROFIL_INACTIF',
      'message', 'Votre compte n''est pas actif. Contactez votre responsable.');
  end if;

  -- Limite de débit : N actions par minute et par agent.
  select count(*) into v_nb
    from public.evenements_pointage e
   where e.profile_id = p_profile_id
     and e.server_at > p_maintenant - interval '1 minute';
  if v_nb >= private.reglage_num('limite_actions_minute') then
    return jsonb_build_object('action', 'limite', 'code', 'RATE_LIMIT',
      'message', 'Trop de tentatives. Réessayez dans une minute.');
  end if;

  -- ── 1. Quel pointage ? ───────────────────────────────────────────────
  if p_pointage_id is not null then
    select * into v_p
      from public.pointages p
     where p.id = p_pointage_id
       and p.profile_id = p_profile_id
       and private.est_actionnable(p.date_jour, p.depart_at, p.prevu_fin, p_maintenant)
       for update;
    if not found then
      return jsonb_build_object('action', 'erreur', 'code', 'POINTAGE_INVALIDE',
        'message', 'Ce créneau n''est pas disponible. Actualisez la page.');
    end if;

  elsif p_creneau_id is not null then
    -- Carte dont le pointage prévu n'a pas encore été généré : on le crée.
    insert into public.pointages
           (profile_id, site_id, creneau_id, date_jour, prevu_debut, prevu_fin, prevu_min, temps_deplacement_min)
    select pp.profile_id, pp.site_id, pp.creneau_id, pp.date_jour, pp.prevu_debut, pp.prevu_fin,
           pp.prevu_min, pp.temps_deplacement_min
      from private.pointages_prevus(v_aujourdhui, p_profile_id) pp
     where pp.creneau_id = p_creneau_id
        on conflict on constraint pointages_unicite do nothing;

    select p.* into v_p
      from public.pointages p
      join private.pointages_prevus(v_aujourdhui, p_profile_id) pp
        on pp.site_id = p.site_id and pp.prevu_debut = p.prevu_debut
     where pp.creneau_id = p_creneau_id
       and p.profile_id = p_profile_id
       and p.date_jour = v_aujourdhui
       for update of p;
    if not found then
      return jsonb_build_object('action', 'erreur', 'code', 'CRENEAU_INVALIDE',
        'message', 'Ce créneau n''est pas disponible. Actualisez la page.');
    end if;

  else
    if p_site_id is null then
      return jsonb_build_object('action', 'erreur', 'code', 'SITE_INCONNU',
        'message', 'Site introuvable. Rescannez la puce.');
    end if;

    select * into v_p
      from public.pointages p
     where p.id = private.choisir_pointage(p_profile_id, p_site_id, p_maintenant)
       for update;

    if not found then
      -- Aucun pointage : hors planning, arrivée immédiate.
      insert into public.pointages (profile_id, site_id, date_jour, hors_planning)
      values (p_profile_id, p_site_id, v_aujourdhui, true)
      returning * into v_p;

      if not exists (select 1 from public.creneaux c
                      where c.profile_id = p_profile_id and c.site_id = p_site_id
                        and c.actif and not c.simulation) then
        v_alertes := array_append(v_alertes, 'SITE_NOT_PLANNED');
      end if;
    end if;
  end if;

  -- ── 2. Quelle action ? ───────────────────────────────────────────────
  if v_p.arrivee_at is null then
    v_type := 'arrivee';
    v_action := 'arrivee';
  elsif v_p.depart_at is null then
    if p_maintenant - v_p.arrivee_at
         < make_interval(mins => private.reglage_num('anti_rebond_min')::int) then
      v_type := 'ignore';
      v_action := 'deja_pointe';
    else
      v_type := 'depart';
      v_action := 'depart';
    end if;
  else
    v_type := 'ignore';
    v_action := 'termine';
  end if;

  -- ── 3. Preuves et alertes ────────────────────────────────────────────
  v_alertes := v_alertes || private.alerte_horloge(v_device_at, p_maintenant);

  select * into v_pos from private.evaluer_position(v_p.site_id, v_lat, v_lng, v_precision);

  if p_methode = 'bouton' then
    if not v_profil.pointage_nfc then
      v_alertes := array_append(v_alertes, 'BUTTON_NOT_ALLOWED');
    end if;
    v_alertes := v_alertes || v_pos.alertes;
    v_presence := v_pos.dans_zone;
  else
    if v_tag_id is not null then
      select * into v_tag from public.nfc_tags t where t.id = v_tag_id;
    end if;
    if v_tag.id is not null and v_tag.type = 'ntag424' and v_tag.site_id = v_p.site_id then
      v_presence := true;   -- signature SUN vérifiée par l'Edge Function
    else
      v_alertes := array_append(v_alertes, 'STATIC_TAG');
    end if;
    -- Avec le NFC, la position est facultative : seule une sortie de zone compte.
    if 'OUT_OF_ZONE' = any (v_pos.alertes) then
      v_alertes := array_append(v_alertes, 'OUT_OF_ZONE');
    end if;
  end if;

  if v_passkey_id is not null then
    select * into v_passkey from public.passkeys k
     where k.id = v_passkey_id and k.profile_id = p_profile_id and not k.revoque;
  end if;
  if v_passkey.id is not null then
    v_appareil := true;
    if v_passkey.created_at > p_maintenant
                                - make_interval(hours => private.reglage_num('nouvel_appareil_h')::int)
       and exists (select 1 from public.passkeys k
                    where k.profile_id = p_profile_id and k.id <> v_passkey.id
                      and k.created_at < v_passkey.created_at) then
      v_alertes := array_append(v_alertes, 'NEW_DEVICE');
    end if;
  else
    v_alertes := array_append(v_alertes, 'NO_DEVICE_PROOF');
  end if;

  -- Même téléphone utilisé par un autre compte.
  if v_appareil_id is not null and (
       exists (select 1 from public.passkeys k
                where k.appareil_id = v_appareil_id and k.profile_id <> p_profile_id and not k.revoque)
    or exists (select 1 from public.evenements_pointage e
                where e.appareil_id = v_appareil_id and e.profile_id <> p_profile_id
                  and e.server_at > p_maintenant
                                    - make_interval(days => private.reglage_num('appareil_partage_jours')::int))
  ) then
    v_alertes := array_append(v_alertes, 'SHARED_DEVICE');
  end if;

  v_alertes := private.fusion_alertes(v_alertes, '{}');
  v_statut := private.statut_confiance(v_presence, v_appareil, v_alertes);

  -- ── 4. Journal ───────────────────────────────────────────────────────
  insert into public.evenements_pointage
         (pointage_id, profile_id, site_id, type, methode, server_at, device_at,
          lat, lng, precision_m, distance_m, nfc_tag_id, nfc_compteur, passkey_id, appareil_id,
          user_agent, ip, alertes, statut, details)
  values (v_p.id, p_profile_id, v_p.site_id, v_type, p_methode, p_maintenant, v_device_at,
          v_lat, v_lng, v_precision, v_pos.distance_m, v_tag.id,
          private.essai_int(v_preuves ->> 'nfc_compteur'), v_passkey.id, v_appareil_id,
          left(v_preuves ->> 'user_agent', 500), private.essai_inet(v_preuves ->> 'ip'),
          v_alertes, v_statut,
          jsonb_build_object('action', v_action, 'dans_zone', v_pos.dans_zone))
  returning id into v_evenement_id;

  -- ── 5. Mise à jour du pointage ───────────────────────────────────────
  if v_type = 'arrivee' then
    update public.pointages p
       set arrivee_at = p_maintenant,
           alertes = private.fusion_alertes(p.alertes, v_alertes),
           statut_confiance = greatest(p.statut_confiance, v_statut),
           bubble_sync_at = null,
           bubble_sync_prochain_essai = p_maintenant
     where p.id = v_p.id
    returning * into v_p;
    v_message := 'Arrivée pointée à ' || private.hhmm(p_maintenant) || ' ✓';

  elsif v_type = 'depart' then
    select * into v_temps from private.calcul_temps(v_p.arrivee_at, p_maintenant, v_p.prevu_min);
    update public.pointages p
       set depart_at = p_maintenant,
           realise_min = v_temps.realise_min,
           realise_nuit_min = v_temps.realise_nuit_min,
           realise_jour_min = v_temps.realise_jour_min,
           ecart_min = case when p.hors_planning then null else v_temps.ecart_min end,
           alertes = private.fusion_alertes(p.alertes, v_alertes),
           statut_confiance = greatest(p.statut_confiance, v_statut),
           bubble_sync_at = null,
           bubble_sync_prochain_essai = p_maintenant
     where p.id = v_p.id
    returning * into v_p;
    v_message := 'Départ pointé à ' || private.hhmm(p_maintenant) || ' ✓';

  elsif v_action = 'deja_pointe' then
    v_message := 'Déjà pointé à ' || private.hhmm(v_p.arrivee_at);
  else
    v_message := 'Départ déjà pointé à ' || private.hhmm(v_p.depart_at);
  end if;

  return jsonb_build_object(
    'action', v_action,
    'message', v_message,
    'evenement_id', v_evenement_id,
    'pointage', jsonb_build_object(
      'id', v_p.id,
      'site_id', v_p.site_id,
      'date_jour', v_p.date_jour,
      'prevu_debut', v_p.prevu_debut,
      'prevu_fin', v_p.prevu_fin,
      'arrivee_at', v_p.arrivee_at,
      'depart_at', v_p.depart_at,
      'hors_planning', v_p.hors_planning));
end $$;

-- ---------------------------------------------------------------------
-- Correction de nuit (§9.4) : pointage ouvert et plus actionnable
--   → réalisé = prévu, écart vide, nuit/jour recalculés, alerte NO_DEPARTURE.
-- Idempotente (on ne retouche pas un pointage déjà corrigé).
-- ---------------------------------------------------------------------
create function private.corriger_pointages_ouverts(p_maintenant timestamptz) returns int
language plpgsql set search_path = '' as $$
declare
  v_nb int;
begin
  update public.pointages p
     set realise_min = p.prevu_min,
         ecart_min = null,
         (realise_nuit_min, realise_jour_min) = (
           select t.realise_nuit_min, t.realise_jour_min
             from private.calcul_temps(p.arrivee_at,
                                       p.arrivee_at + make_interval(mins => p.prevu_min),
                                       p.prevu_min) t),
         alertes = private.fusion_alertes(p.alertes, array['NO_DEPARTURE']),
         bubble_sync_at = null,
         bubble_sync_prochain_essai = p_maintenant
   where p.arrivee_at is not null
     and p.depart_at is null
     and not ('NO_DEPARTURE' = any (p.alertes))
     and p.date_jour < private.date_paris(p_maintenant)
     and not private.est_actionnable(p.date_jour, p.depart_at, p.prevu_fin, p_maintenant);
  get diagnostics v_nb = row_count;
  return v_nb;
end $$;

-- ---------------------------------------------------------------------
-- Anti-rejeu NFC (§5.2) : un compteur SUN ne sert qu'une fois.
-- La mise à jour conditionnelle est atomique : deux requêtes simultanées
-- avec le même compteur ne peuvent pas réussir toutes les deux.
-- Renvoie l'id de la réservation (10 min), ou null si le lien est rejoué.
-- ---------------------------------------------------------------------
create function private.reserver_compteur(p_tag_id uuid, p_compteur int, p_maintenant timestamptz)
returns uuid
language plpgsql set search_path = '' as $$
declare
  v_id uuid;
begin
  update public.nfc_tags t
     set dernier_compteur = p_compteur
   where t.id = p_tag_id
     and t.actif
     and t.type = 'ntag424'
     and t.dernier_compteur < p_compteur;
  if not found then
    return null;
  end if;

  insert into public.nfc_reservations (tag_id, compteur, created_at, expires_at)
  values (p_tag_id, p_compteur, p_maintenant, p_maintenant + interval '10 minutes')
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Purge RGPD : coordonnées précises effacées après N jours ;
-- la distance et le statut sont conservés.
-- ---------------------------------------------------------------------
create function private.purger_positions(p_maintenant timestamptz) returns int
language plpgsql set search_path = '' as $$
declare
  v_nb int;
begin
  update public.evenements_pointage e
     set lat = null, lng = null, precision_m = null
   where (e.lat is not null or e.lng is not null)
     and e.server_at < p_maintenant
                       - make_interval(days => private.reglage_num('conservation_positions_jours')::int);
  get diagnostics v_nb = row_count;
  return v_nb;
end $$;

-- ---------------------------------------------------------------------
-- Identité de l'utilisateur connecté (utilisé par la RLS et les RPC)
-- ---------------------------------------------------------------------
create function private.mon_profil_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p where p.user_id = auth.uid() and not p.archive
$$;

create function private.mon_role() returns public.role_profil
language sql stable security definer set search_path = '' as $$
  select p.role from public.profiles p where p.user_id = auth.uid() and not p.archive
$$;

create function private.est_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.mon_role() = 'admin', false)
$$;

-- Profils visibles : soi-même ; l'équipe d'un chef ; tout le monde pour l'admin.
create function private.profils_visibles() returns setof uuid
language sql stable security definer set search_path = '' as $$
  with moi as (
    select p.id, p.role from public.profiles p where p.user_id = auth.uid() and not p.archive
  )
  select m.id from moi m
  union
  select p.id from public.profiles p join moi m on m.role = 'admin'
  union
  select p.id from public.profiles p join moi m on m.role = 'chef_secteur' and p.chef_secteur_id = m.id
  union
  select p.id from public.profiles p join moi m on m.role = 'chef_equipe' and p.chef_equipe_id = m.id
$$;

-- Sites visibles (§2.5) :
--   - sites où l'on est affecté ou planifié ;
--   - volant : + sites des secteurs attribués. SANS secteur : seulement les siens
--     (corrige le défaut Bubble où il voyait tout) ;
--   - chef de secteur : + sites de son secteur ; chefs : + sites de leur équipe ;
--   - admin : tous.
create function private.sites_visibles() returns setof uuid
language sql stable security definer set search_path = '' as $$
  with moi as (
    select p.id, p.role from public.profiles p where p.user_id = auth.uid() and not p.archive
  )
  select s.id from public.sites s join moi m on m.role = 'admin'
  union
  select sa.site_id from public.site_agents sa join moi m on sa.profile_id = m.id
  union
  select c.site_id from public.creneaux c join moi m on c.profile_id = m.id
   where c.actif and c.site_id is not null
  union
  select s.id from public.sites s
    join public.volant_secteurs vs on vs.chef_secteur_id = s.chef_secteur_id
    join moi m on vs.volant_id = m.id
  union
  select s.id from public.sites s join moi m on m.role = 'chef_secteur' and s.chef_secteur_id = m.id
  union
  select c.site_id from public.creneaux c
    join moi m on m.role in ('chef_secteur', 'chef_equipe')
    join public.profiles p on p.id = c.profile_id
   where c.actif and c.site_id is not null
     and (p.chef_secteur_id = m.id or p.chef_equipe_id = m.id)
$$;

-- ---------------------------------------------------------------------
-- Planning du jour d'un agent (§2.4, §4.1)
-- Chaque carte porte SON pointage (rapproché par l'heure prévue), ce qui
-- corrige le défaut Bubble des deux créneaux le même jour sur le même site.
-- Les boutons ne sont proposés qu'aux personnes sans NFC, et le jour même.
-- ---------------------------------------------------------------------
create function private.planning_du_jour(p_profile_id uuid, p_date date, p_maintenant timestamptz)
returns table (
  creneau_id    uuid,
  pointage_id   uuid,
  site_id       uuid,
  site_nom      text,
  site_adresse  text,
  prevu_debut   timestamptz,
  prevu_fin     timestamptz,
  heure_debut   text,
  heure_fin     text,
  arrivee_at    timestamptz,
  depart_at     timestamptz,
  arrivee_hhmm  text,
  depart_hhmm   text,
  hors_planning boolean,
  etat          text,   -- a_faire | en_cours | termine | manque
  affichage     text,   -- a_pointer | arrivee_pointee | penser_depart | termine | manque
  message       text,
  bouton        text    -- arrivee | depart | null
)
language sql stable set search_path = '' as $$
  with prevus as (
    -- Garde : un profil null ne doit jamais renvoyer le planning de tout le monde.
    select * from private.pointages_prevus(p_date, p_profile_id) where p_profile_id is not null
  ),
  cartes as (
    select pp.creneau_id, p.id as pointage_id, pp.site_id, pp.prevu_debut, pp.prevu_fin,
           p.arrivee_at, p.depart_at, false as hors_planning
      from prevus pp
      left join public.pointages p
        on p.profile_id = pp.profile_id and p.site_id = pp.site_id
       and p.date_jour = p_date and p.prevu_debut = pp.prevu_debut
    union all
    -- Pointages du jour sans créneau correspondant : hors planning,
    -- ou créneau modifié depuis la génération.
    select p.creneau_id, p.id, p.site_id, p.prevu_debut, p.prevu_fin,
           p.arrivee_at, p.depart_at, p.hors_planning
      from public.pointages p
     where p.profile_id = p_profile_id
       and p.date_jour = p_date
       and not exists (select 1 from prevus pp
                        where pp.site_id = p.site_id and pp.prevu_debut = p.prevu_debut)
  ),
  boutons as (
    select pr.pointage_nfc and not pr.archive and p_date = private.date_paris(p_maintenant) as actifs
      from public.profiles pr where pr.id = p_profile_id
  )
  select c.creneau_id, c.pointage_id, c.site_id, s.nom, s.adresse,
         c.prevu_debut, c.prevu_fin,
         private.hhmm(c.prevu_debut), private.hhmm(c.prevu_fin),
         c.arrivee_at, c.depart_at,
         private.hhmm(c.arrivee_at), private.hhmm(c.depart_at),
         c.hors_planning,
         e.etat, e.affichage, e.message,
         case when b.actifs then e.bouton end
    from cartes c
    join public.sites s on s.id = c.site_id
    cross join boutons b
   cross join lateral (
     select case
              when c.depart_at is not null then 'termine'
              when c.arrivee_at is not null then 'en_cours'
              when c.prevu_fin is not null and p_maintenant > c.prevu_fin then 'manque'
              else 'a_faire'
            end as etat,
            case
              when c.depart_at is not null then 'termine'
              when c.arrivee_at is not null and (c.prevu_fin is null or p_maintenant <= c.prevu_fin)
                then 'arrivee_pointee'
              when c.arrivee_at is not null then 'penser_depart'
              when c.prevu_fin is not null and p_maintenant > c.prevu_fin then 'manque'
              else 'a_pointer'
            end as affichage,
            case
              when c.depart_at is not null
                then 'Arrivée ' || private.hhmm(c.arrivee_at) || ' · Départ ' || private.hhmm(c.depart_at)
              when c.arrivee_at is not null and (c.prevu_fin is null or p_maintenant <= c.prevu_fin)
                then 'Arrivée pointée à ' || private.hhmm(c.arrivee_at)
              when c.arrivee_at is not null
                then 'Créneau terminé : pensez à pointer votre départ'
              when c.prevu_fin is not null and p_maintenant > c.prevu_fin
                then 'Créneau terminé à ' || private.hhmm(c.prevu_fin) || ' : arrivée non pointée'
              else null
            end as message,
            case
              when c.depart_at is not null then null
              when c.arrivee_at is not null then 'depart'
              when c.prevu_fin is not null and p_maintenant > c.prevu_fin then null
              else 'arrivee'
            end as bouton
   ) e
   order by c.prevu_debut nulls last, c.arrivee_at
$$;

-- =====================================================================
-- Enveloppes publiques : l'heure est toujours now() côté serveur.
-- =====================================================================

-- Appelée par les Edge Functions (service_role) uniquement.
create function public.traiter_pointage(
  p_profile_id  uuid,
  p_site_id     uuid,
  p_methode     public.methode_pointage,
  p_pointage_id uuid default null,
  p_creneau_id  uuid default null,
  p_preuves     jsonb default '{}'::jsonb
) returns jsonb
language sql security definer set search_path = '' as $$
  select private.traiter_pointage(p_profile_id, p_site_id, p_methode, p_pointage_id, p_creneau_id,
                                  p_preuves, now())
$$;

create function public.nfc_reserver_compteur(p_tag_id uuid, p_compteur int) returns uuid
language sql security definer set search_path = '' as $$
  select private.reserver_compteur(p_tag_id, p_compteur, now())
$$;

-- pg_cron, toutes les heures : génère pour la date du jour à Paris.
create function public.generer_pointages(p_date date default null) returns int
language sql security definer set search_path = '' as $$
  select private.generer_pointages(coalesce(p_date, private.date_paris(now())))
$$;

create function public.corriger_veille() returns int
language sql security definer set search_path = '' as $$
  select private.corriger_pointages_ouverts(now())
$$;

create function public.purger_positions() returns int
language sql security definer set search_path = '' as $$
  select private.purger_positions(now())
$$;

-- RPC WeWeb : planning de l'agent connecté (vide si non connecté ou archivé).
create function public.mon_planning(p_date date default null)
returns table (
  creneau_id    uuid,
  pointage_id   uuid,
  site_id       uuid,
  site_nom      text,
  site_adresse  text,
  prevu_debut   timestamptz,
  prevu_fin     timestamptz,
  heure_debut   text,
  heure_fin     text,
  arrivee_at    timestamptz,
  depart_at     timestamptz,
  arrivee_hhmm  text,
  depart_hhmm   text,
  hors_planning boolean,
  etat          text,
  affichage     text,
  message       text,
  bouton        text
)
language sql stable security definer set search_path = '' as $$
  select * from private.planning_du_jour(private.mon_profil_id(),
                                         coalesce(p_date, private.date_paris(now())),
                                         now())
$$;
