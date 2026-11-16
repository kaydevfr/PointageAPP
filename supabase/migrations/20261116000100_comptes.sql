-- =====================================================================
-- 10 — Comptes : seuls les salariés connus (et actifs) peuvent se créer
-- un compte, et chaque compte est relié à sa fiche salarié par l'email.
-- (§7.3 « Comptes »)
-- =====================================================================

-- Un email est-il celui d'un salarié actif ?
create function private.email_autorise(p_email text) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.profiles p
                  where p.email = lower(trim(p_email)) and not p.archive)
$$;

-- Relie un compte Auth à la fiche salarié de même email (si elle n'est pas
-- déjà reliée à un autre compte). Renvoie l'id du profil, ou null.
create function private.lier_compte(p_user_id uuid, p_email text) returns uuid
language plpgsql set search_path = '' as $$
declare
  v_id uuid;
begin
  if p_user_id is null or p_email is null then
    return null;
  end if;

  select p.id into v_id from public.profiles p where p.user_id = p_user_id;
  if found then
    return v_id;
  end if;

  update public.profiles p
     set user_id = p_user_id
   where p.email = lower(trim(p_email))
     and p.user_id is null
  returning p.id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Hook Supabase Auth « before user created » : refuse la création d'un
-- compte pour un email inconnu ou archivé. Branché dans config.toml
-- (local) et dans le tableau de bord Supabase (Authentication → Hooks).
-- ---------------------------------------------------------------------
create function public.hook_avant_creation_compte(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if private.email_autorise(event -> 'user' ->> 'email') then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403,
    'message', 'Cette adresse email n''est pas reconnue. Contactez votre responsable.'));
end $$;

-- Relie le compte dès sa création.
create function private.trg_lier_compte() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.lier_compte(new.id, new.email);
  return new;
end $$;

create trigger lier_compte_apres_creation
  after insert on auth.users
  for each row execute function private.trg_lier_compte();

-- RPC appelée par WeWeb juste après chaque connexion : relie le compte si la
-- fiche salarié a été créée après lui (synchro Bubble), et dit si l'accès est
-- autorisé. Ne renvoie que ce dont l'interface a besoin.
create function public.mon_profil() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id     uuid;
  v_profil public.profiles;
begin
  v_id := private.lier_compte(auth.uid(), auth.jwt() ->> 'email');
  select * into v_profil from public.profiles p where p.id = v_id;

  if v_profil.id is null or v_profil.archive then
    return jsonb_build_object('autorise', false,
      'message', 'Votre compte n''est pas actif. Contactez votre responsable.');
  end if;

  return jsonb_build_object(
    'autorise', true,
    'id', v_profil.id,
    'prenom', v_profil.prenom,
    'nom', v_profil.nom,
    'role', v_profil.role,
    'langue', v_profil.langue,
    -- true = pas de NFC : l'interface affiche les boutons de pointage
    'pointage_bouton', v_profil.pointage_nfc);
end $$;

-- Droits
revoke all on function public.hook_avant_creation_compte(jsonb) from public, anon, authenticated;
grant execute on function public.hook_avant_creation_compte(jsonb) to supabase_auth_admin;
revoke all on function public.mon_profil() from public, anon;
grant execute on function public.mon_profil() to authenticated;
revoke all on function private.email_autorise(text), private.lier_compte(uuid, text), private.trg_lier_compte()
  from public, anon, authenticated;
