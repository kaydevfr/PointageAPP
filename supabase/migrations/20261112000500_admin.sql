-- =====================================================================
-- 05 — Admin : historique des corrections et réglages
-- =====================================================================

create table public.audit_admin (
  id           bigint generated always as identity primary key,
  admin_id     uuid not null references public.profiles (id),
  pointage_id  uuid references public.pointages (id) on delete set null,
  action       text not null,
  motif        text,
  avant        jsonb,
  apres        jsonb,
  at           timestamptz not null default now()
);
create index on public.audit_admin (pointage_id);

create table public.reglages (
  cle     text primary key,
  valeur  jsonb not null,
  description text
);

insert into public.reglages (cle, valeur, description) values
  ('rayon_defaut_m',               '200', 'Rayon autorisé autour d''un site sans rayon propre (m)'),
  ('precision_max_m',              '150', 'Précision GPS au-delà de laquelle on ne conclut rien (m)'),
  ('anti_rebond_min',              '5',   'Délai minimal entre arrivée et départ (min)'),
  ('ecart_horloge_max_s',          '120', 'Écart toléré entre l''heure du téléphone et du serveur (s)'),
  ('limite_actions_minute',        '10',  'Actions de pointage max par minute et par agent'),
  ('delai_depart_apres_fin_h',     '4',   'Après la fin prévue + ce délai, un pointage ouvert est clôturé par la correction de nuit (h)'),
  ('conservation_positions_jours', '60',  'Durée de conservation des coordonnées précises (jours)'),
  ('nouvel_appareil_h',            '24',  'Une passkey créée depuis moins de ce délai, alors que le salarié en avait déjà une, lève NEW_DEVICE (h)'),
  ('appareil_partage_jours',       '30',  'Fenêtre de recherche d''un même appareil utilisé par un autre compte (jours)');

alter table public.audit_admin enable row level security;
alter table public.reglages    enable row level security;

-- Lecture typée d'un réglage numérique.
create function private.reglage_num(p_cle text) returns numeric
language sql stable set search_path = '' as $$
  select (r.valeur #>> '{}')::numeric from public.reglages r where r.cle = p_cle
$$;
