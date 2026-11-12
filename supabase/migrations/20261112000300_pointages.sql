-- =====================================================================
-- 03 — Pointages et journal des événements
-- =====================================================================

create table public.pointages (
  id                          uuid primary key default gen_random_uuid(),
  bubble_id                   text unique,
  profile_id                  uuid not null references public.profiles (id),
  site_id                     uuid not null references public.sites (id),
  creneau_id                  uuid references public.creneaux (id) on delete set null,
  date_jour                   date not null,           -- date à l'heure de Paris
  prevu_debut                 timestamptz,
  prevu_fin                   timestamptz,
  prevu_min                   int,
  temps_deplacement_min       int,
  -- Toujours l'heure du serveur (now()), jamais celle du téléphone.
  arrivee_at                  timestamptz,
  depart_at                   timestamptz,
  realise_min                 int,
  realise_nuit_min            int,
  realise_jour_min            int,
  ecart_min                   int,
  hors_planning               boolean not null default false,
  absence                     boolean not null default false,
  valide                      boolean not null default false,
  -- Le plus grave des statuts de ses événements ; null tant que rien n'est pointé.
  statut_confiance            public.statut_confiance,
  -- Union des alertes des événements (+ NO_DEPARTURE). Jamais montré à l'agent.
  alertes                     text[] not null default '{}',
  -- File de renvoi vers Bubble
  bubble_sync_at              timestamptz,
  bubble_sync_error           text,
  bubble_sync_tentatives      int not null default 0,
  bubble_sync_prochain_essai  timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  -- Les pointages hors planning ont prevu_debut null : ils échappent à
  -- cette contrainte (NULL distincts) ; le verrou par profil les protège.
  constraint pointages_unicite unique (profile_id, site_id, date_jour, prevu_debut),
  constraint pointages_depart_apres_arrivee
    check (depart_at is null or (arrivee_at is not null and depart_at >= arrivee_at))
);
create index on public.pointages (profile_id, date_jour);
create index on public.pointages (site_id, date_jour);
create index on public.pointages (date_jour, statut_confiance);
create index on public.pointages (bubble_sync_prochain_essai)
  where bubble_sync_at is null and arrivee_at is not null;

create table public.evenements_pointage (
  id            bigint generated always as identity primary key,
  pointage_id   uuid references public.pointages (id) on delete cascade,  -- null si 'rejete'
  profile_id    uuid not null references public.profiles (id),
  site_id       uuid references public.sites (id),
  type          public.type_evenement not null,
  methode       public.methode_pointage not null,
  server_at     timestamptz not null default now(),
  device_at     timestamptz,                -- indice seulement
  lat           double precision,           -- purgés après la durée de conservation
  lng           double precision,
  precision_m   real,
  distance_m    int,                        -- conservé après la purge
  nfc_tag_id    uuid,
  nfc_compteur  int,
  passkey_id    uuid,
  appareil_id   text,                       -- identifiant aléatoire gardé par le navigateur
  user_agent    text,
  ip            inet,
  alertes       text[] not null default '{}',
  statut        public.statut_confiance,
  details       jsonb not null default '{}'
);
create index on public.evenements_pointage (profile_id, server_at desc);
create index on public.evenements_pointage (pointage_id);
create index on public.evenements_pointage (appareil_id, server_at desc) where appareil_id is not null;

create function private.maj_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger pointages_updated_at before update on public.pointages
  for each row execute function private.maj_updated_at();

alter table public.pointages           enable row level security;
alter table public.evenements_pointage enable row level security;
