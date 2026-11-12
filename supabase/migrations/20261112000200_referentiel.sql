-- =====================================================================
-- 02 — Référentiel copié depuis Bubble (salariés, sites, planning)
-- =====================================================================

create table public.profiles (
  id                      uuid primary key default gen_random_uuid(),
  -- Rempli à la première connexion, par rapprochement de l'email Bubble.
  -- Les profils existent avant les comptes : ils sont créés par la synchro.
  user_id                 uuid unique references auth.users (id) on delete set null,
  bubble_id               text not null unique,
  email                   text,                -- toujours stocké en minuscules
  nom                     text,
  prenom                  text,
  telephone               text,
  type_contact            text,                -- valeur brute Bubble (« Agent Container »…)
  role                    public.role_profil not null default 'agent',
  chef_equipe_id          uuid references public.profiles (id) on delete set null,
  chef_secteur_id         uuid references public.profiles (id) on delete set null,
  archive                 boolean not null default false,
  date_demarrage_planning date,
  langue                  text not null default 'fr',
  -- true = la personne N'A PAS de NFC : elle pointe avec le bouton.
  pointage_nfc            boolean not null default false,
  synced_at               timestamptz,
  created_at              timestamptz not null default now(),
  constraint profiles_email_minuscules check (email is null or email = lower(email))
);
create unique index profiles_email_key on public.profiles (email) where email is not null;
create index on public.profiles (chef_secteur_id);
create index on public.profiles (chef_equipe_id);

create table public.sites (
  id               uuid primary key default gen_random_uuid(),
  bubble_id        text not null unique,
  nom              text not null,
  adresse          text,
  geo              extensions.geography(Point, 4326),   -- position géocodée (Bubble)
  geo_corrige      extensions.geography(Point, 4326),   -- position corrigée par l'admin
  rayon_m          int check (rayon_m between 20 and 5000),  -- null = réglage par défaut
  chef_secteur_id  uuid references public.profiles (id) on delete set null,
  contrat_termine  boolean not null default false,
  synced_at        timestamptz,
  created_at       timestamptz not null default now()
);
create index on public.sites (chef_secteur_id);

create table public.site_agents (
  site_id    uuid not null references public.sites (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  primary key (site_id, profile_id)
);
create index on public.site_agents (profile_id);

-- Secteurs d'un volant : un secteur = un chef de secteur.
create table public.volant_secteurs (
  volant_id        uuid not null references public.profiles (id) on delete cascade,
  chef_secteur_id  uuid not null references public.profiles (id) on delete cascade,
  primary key (volant_id, chef_secteur_id)
);

create table public.creneaux (
  id                     uuid primary key default gen_random_uuid(),
  bubble_id              text not null unique,
  profile_id             uuid not null references public.profiles (id) on delete cascade,
  site_id                uuid references public.sites (id) on delete set null,
  jour_semaine           smallint not null check (jour_semaine between 1 and 7),  -- ISO : 1 = lundi
  heure_debut            time not null,
  heure_fin              time not null,      -- fin <= début : le créneau passe minuit
  duree_min              int,
  ordre                  int,
  deplacement            boolean not null default false,  -- trajet, pas un vrai créneau
  temps_deplacement_min  int,
  simulation             boolean not null default false,
  -- Créneau supprimé dans Bubble : on le désactive (les pointages le référencent).
  actif                  boolean not null default true,
  synced_at              timestamptz
);
create index on public.creneaux (profile_id, jour_semaine);
create index on public.creneaux (site_id);

alter table public.profiles        enable row level security;
alter table public.sites           enable row level security;
alter table public.site_agents     enable row level security;
alter table public.volant_secteurs enable row level security;
alter table public.creneaux        enable row level security;
