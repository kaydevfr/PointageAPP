-- =====================================================================
-- 06 — Fonctions de calcul (pures ou en lecture seule), toutes testées
-- Fuseau : tous les « aujourd'hui », « 6 h » et heures de créneau sont
-- calculés en Europe/Paris. Les durées viennent d'une soustraction entre
-- timestamptz : elles restent justes lors des changements d'heure.
-- =====================================================================

-- Date du jour à Paris pour un instant donné.
create function private.date_paris(p_ts timestamptz) returns date
language sql stable set search_path = '' as $$
  select (p_ts at time zone 'Europe/Paris')::date
$$;

-- Instant correspondant à une date + une heure « murale » à Paris.
create function private.a_paris(p_date date, p_heure time) returns timestamptz
language sql stable set search_path = '' as $$
  select (p_date + p_heure) at time zone 'Europe/Paris'
$$;

-- « 07:58 » à l'heure de Paris.
create function private.hhmm(p_ts timestamptz) returns text
language sql stable set search_path = '' as $$
  select to_char(p_ts at time zone 'Europe/Paris', 'HH24:MI')
$$;

create function private.minutes_entre(p_debut timestamptz, p_fin timestamptz) returns int
language sql immutable set search_path = '' as $$
  select round(extract(epoch from (p_fin - p_debut)) / 60)::int
$$;

-- ---------------------------------------------------------------------
-- Calculs au départ (§9.3)
--   réalisé = départ − arrivée
--   nuit    = si arrivée avant 6 h (Paris) : min(départ, 6 h) − arrivée, sinon 0
--             (corrige le défaut Bubble : 4 h → 5 h 30 = 90 min, pas 120)
--   jour    = réalisé − nuit
--   écart   = réalisé − prévu (null si pas de prévu, donc hors planning)
-- ---------------------------------------------------------------------
create function private.calcul_temps(
  p_arrivee   timestamptz,
  p_depart    timestamptz,
  p_prevu_min int,
  out realise_min      int,
  out realise_nuit_min int,
  out realise_jour_min int,
  out ecart_min        int
)
language plpgsql stable set search_path = '' as $$
declare
  v_six timestamptz;
begin
  if p_arrivee is null or p_depart is null then
    return;
  end if;

  realise_min := private.minutes_entre(p_arrivee, p_depart);

  v_six := private.a_paris(private.date_paris(p_arrivee), time '06:00');
  if p_arrivee < v_six then
    realise_nuit_min := private.minutes_entre(p_arrivee, least(p_depart, v_six));
  else
    realise_nuit_min := 0;
  end if;

  realise_jour_min := realise_min - realise_nuit_min;
  ecart_min := case when p_prevu_min is null then null else realise_min - p_prevu_min end;
end $$;

-- ---------------------------------------------------------------------
-- Alertes : classement (§5.6)
-- ---------------------------------------------------------------------

-- Alertes graves : le pointage passe « à vérifier ».
-- BUTTON_NOT_ALLOWED (ajout) : bouton utilisé par un agent qui a le NFC,
-- ce qui suppose un appel forgé, l'interface ne montrant pas le bouton.
create function private.alertes_graves() returns text[]
language sql immutable set search_path = '' as $$
  select array['OUT_OF_ZONE', 'DEVICE_CLOCK_SKEW', 'SHARED_DEVICE', 'IDENTICAL_COORDS',
               'IMPOSSIBLE_TRAVEL', 'REPLAYED_TAG', 'BUTTON_NOT_ALLOWED']
$$;

-- Alertes qui signifient « pas de preuve » : le pointage ne peut pas être vérifié.
create function private.alertes_sans_preuve() returns text[]
language sql immutable set search_path = '' as $$
  select array['NO_LOCATION', 'LOW_ACCURACY', 'STATIC_TAG', 'SITE_NO_POSITION',
               'NO_DEVICE_PROOF', 'NEW_DEVICE']
$$;

-- ---------------------------------------------------------------------
-- Statut de confiance : LA fonction unique, réutilisée partout (§5.6)
--   ⚠️ à vérifier : au moins une alerte grave
--   ❓ non vérifié : pas de preuve de présence ou de l'appareil
--   ✅ vérifié     : présence prouvée + appareil prouvé + aucune alerte bloquante
-- ---------------------------------------------------------------------
create function private.statut_confiance(
  p_preuve_presence boolean,
  p_preuve_appareil boolean,
  p_alertes         text[]
) returns public.statut_confiance
language sql immutable set search_path = '' as $$
  select (case
    when coalesce(p_alertes, '{}') && private.alertes_graves() then 'a_verifier'
    when coalesce(p_alertes, '{}') && private.alertes_sans_preuve() then 'non_verifie'
    when coalesce(p_preuve_presence, false) and coalesce(p_preuve_appareil, false) then 'verifie'
    else 'non_verifie'
  end)::public.statut_confiance
$$;

-- ---------------------------------------------------------------------
-- Position par rapport au site (§5.4)
--   pas de position        → NO_LOCATION
--   précision > seuil      → LOW_ACCURACY (on ne conclut rien sur la zone)
--   distance > rayon       → OUT_OF_ZONE
--   site sans coordonnées  → SITE_NO_POSITION
-- La distance est calculée dès que la position et le site sont connus.
-- ---------------------------------------------------------------------
create function private.evaluer_position(
  p_site_id     uuid,
  p_lat         double precision,
  p_lng         double precision,
  p_precision_m double precision,
  out distance_m int,
  out dans_zone  boolean,
  out alertes    text[]
)
language plpgsql stable set search_path = '' as $$
declare
  v_geo   extensions.geography;
  v_rayon int;
begin
  dans_zone := false;
  alertes := '{}';

  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    alertes := array['NO_LOCATION'];
    return;
  end if;

  select coalesce(s.geo_corrige, s.geo),
         coalesce(s.rayon_m, private.reglage_num('rayon_defaut_m')::int)
    into v_geo, v_rayon
    from public.sites s
   where s.id = p_site_id;

  if v_geo is null then
    alertes := array['SITE_NO_POSITION'];
    return;
  end if;

  distance_m := round(extensions.st_distance(
    v_geo,
    extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography
  ))::int;

  if p_precision_m is null or p_precision_m > private.reglage_num('precision_max_m') then
    alertes := array['LOW_ACCURACY'];
  elsif distance_m > v_rayon then
    alertes := array['OUT_OF_ZONE'];
  else
    dans_zone := true;
  end if;
end $$;

-- Heure du téléphone : simple indice, jamais enregistrée comme heure de pointage.
create function private.alerte_horloge(p_device_at timestamptz, p_server_at timestamptz)
returns text[]
language sql stable set search_path = '' as $$
  select case
    when p_device_at is not null
     and abs(extract(epoch from (p_device_at - p_server_at))) > private.reglage_num('ecart_horloge_max_s')
    then array['DEVICE_CLOCK_SKEW']
    else '{}'::text[]
  end
$$;
