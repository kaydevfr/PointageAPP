-- =====================================================================
-- 04 — Anti-triche : puces NFC, réservations de scan, passkeys, défis
-- (tables posées en phase 0, logique complète en phase 2)
-- =====================================================================

create table public.nfc_tags (
  id                uuid primary key default gen_random_uuid(),
  site_id           uuid not null references public.sites (id) on delete cascade,
  uid               text unique,               -- UID de la puce (hex) ; null pour une puce statique
  type              public.type_puce not null,
  cle_vault_id      uuid,                      -- secret dans Supabase Vault (ntag424)
  dernier_compteur  int not null default -1,   -- anti-rejeu : tout compteur <= est refusé
  actif             boolean not null default true,
  created_at        timestamptz not null default now(),
  constraint nfc_tags_ntag424_complet
    check (type = 'statique' or (uid is not null and cle_vault_id is not null))
);
create index on public.nfc_tags (site_id);

-- Un scan SUN valide « réserve » son compteur dès l'ouverture de la page,
-- avant même la connexion de l'agent. La réservation vit 10 minutes.
create table public.nfc_reservations (
  id           uuid primary key default gen_random_uuid(),
  tag_id       uuid not null references public.nfc_tags (id) on delete cascade,
  compteur     int not null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  consomme_at  timestamptz,
  profile_id   uuid references public.profiles (id),
  unique (tag_id, compteur)
);

create table public.passkeys (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references public.profiles (id) on delete cascade,
  credential_id  text not null unique,
  public_key     bytea not null,
  counter        bigint not null default 0,
  appareil       text,                 -- libellé lisible (« iPhone de Paul »)
  appareil_id    text,                 -- identifiant aléatoire gardé par le navigateur
  created_at     timestamptz not null default now(),
  last_used_at   timestamptz,
  revoque        boolean not null default false
);
create index on public.passkeys (profile_id);
create index on public.passkeys (appareil_id) where appareil_id is not null;

create table public.challenges (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid references public.profiles (id) on delete cascade,
  challenge   text not null unique,
  but         text not null check (but in ('register', 'auth')),
  expires_at  timestamptz not null,     -- 60 s
  used        boolean not null default false
);

alter table public.nfc_tags         enable row level security;
alter table public.nfc_reservations enable row level security;
alter table public.passkeys         enable row level security;
alter table public.challenges       enable row level security;
