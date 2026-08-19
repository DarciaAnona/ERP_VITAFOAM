-- ============================================================================
-- VITAFOAM ERP - MIGRATION NON DESTRUCTIVE : RATTACHEMENT ARTICLES / SITES
-- A COPIER-COLLER DANS : Supabase > SQL Editor > New query > Run
-- Cette migration CONSERVE les articles, OF, stock et production existants.
-- ============================================================================

create extension if not exists pgcrypto;

-- 1) Référentiel fixe des 3 couples société / site
create table if not exists public.sites_ref (
  code_societe text primary key,
  site_code text not null unique,
  site_libelle text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint sites_ref_societe_ck check (code_societe in ('VT','VD','VS')),
  constraint sites_ref_code_ck check (site_code in ('VITA','VIDIE','VISA'))
);

insert into public.sites_ref(code_societe, site_code, site_libelle)
values
  ('VT','VITA','Vitafoam Tana'),
  ('VD','VIDIE','Vitafoam Diego'),
  ('VS','VISA','Vitafoam Sambava')
on conflict (code_societe) do update
set site_code = excluded.site_code,
    site_libelle = excluded.site_libelle,
    active = true;

-- 2) Table de rattachement : 1 article peut exister sur plusieurs sites
create table if not exists public.article_sites (
  id uuid primary key default gen_random_uuid(),
  article_id uuid not null references public.articles(id) on delete cascade,
  societe text not null,
  site_code text not null,
  site_libelle text not null,
  created_at timestamptz not null default now(),
  constraint article_sites_societe_ck check (societe in ('VT','VD','VS')),
  constraint article_sites_code_ck check (site_code in ('VITA','VIDIE','VISA')),
  constraint article_sites_article_site_uk unique(article_id, site_code)
);

create index if not exists idx_article_sites_article on public.article_sites(article_id);
create index if not exists idx_article_sites_site on public.article_sites(site_code);

-- 3) S'assure que la colonne historique sites[] existe encore pour compatibilité
alter table public.articles
  add column if not exists sites text[] not null default array[]::text[];

-- 4) Migration des anciens sites[] vers article_sites
insert into public.article_sites(article_id, societe, site_code, site_libelle)
select distinct
  a.id,
  r.code_societe,
  r.site_code,
  r.site_libelle
from public.articles a
cross join lateral unnest(coalesce(a.sites, array[]::text[])) as old_site(site_code)
join public.sites_ref r on r.site_code = old_site.site_code
on conflict (article_id, site_code) do nothing;

-- 5) Tout article géré en stock reçoit obligatoirement le site principal de sa société
insert into public.article_sites(article_id, societe, site_code, site_libelle)
select
  a.id,
  r.code_societe,
  r.site_code,
  r.site_libelle
from public.articles a
join public.sites_ref r on r.code_societe = a.societe
where coalesce(a.gestion_stock, true) = true
on conflict (article_id, site_code) do nothing;

-- 6) Resynchronise le tableau articles.sites depuis la table de rattachement
update public.articles a
set sites = coalesce((
  select array_agg(s.site_code order by
    case s.site_code when 'VITA' then 1 when 'VIDIE' then 2 when 'VISA' then 3 else 9 end)
  from public.article_sites s
  where s.article_id = a.id
), array[]::text[]),
updated_at = now();

-- 7) Fonction de sécurité : rattache un article à un site valide et synchronise sites[]
create or replace function public.attach_article_site(
  p_article_id uuid,
  p_site_code text
)
returns public.article_sites
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_ref public.sites_ref%rowtype;
  v_row public.article_sites%rowtype;
begin
  select * into v_ref
  from public.sites_ref
  where site_code = p_site_code and active = true;

  if not found then
    raise exception 'Site inconnu : %', p_site_code;
  end if;

  insert into public.article_sites(article_id, societe, site_code, site_libelle)
  values (p_article_id, v_ref.code_societe, v_ref.site_code, v_ref.site_libelle)
  on conflict (article_id, site_code) do update
  set societe = excluded.societe,
      site_libelle = excluded.site_libelle
  returning * into v_row;

  update public.articles a
  set sites = coalesce((
    select array_agg(s.site_code order by
      case s.site_code when 'VITA' then 1 when 'VIDIE' then 2 when 'VISA' then 3 else 9 end)
    from public.article_sites s
    where s.article_id = p_article_id
  ), array[]::text[]),
  updated_at = now()
  where a.id = p_article_id;

  return v_row;
end;
$$;

-- 8) RLS prototype, alignée avec l'ERP actuel utilisant la clé anon publique
alter table public.sites_ref enable row level security;
alter table public.article_sites enable row level security;

drop policy if exists prototype_all on public.sites_ref;
create policy prototype_all on public.sites_ref
for all to anon, authenticated
using (true)
with check (true);

drop policy if exists prototype_all on public.article_sites;
create policy prototype_all on public.article_sites
for all to anon, authenticated
using (true)
with check (true);

grant select, insert, update, delete on public.sites_ref to anon, authenticated;
grant select, insert, update, delete on public.article_sites to anon, authenticated;
grant execute on function public.attach_article_site(uuid,text) to anon, authenticated;

-- 9) Vue pratique de contrôle
create or replace view public.v_article_sites as
select
  a.id as article_id,
  a.code as article_code,
  coalesce(a.intitule, a.designation, a.code) as article_designation,
  a.societe as societe_origine,
  s.societe,
  s.site_code,
  s.site_libelle,
  s.created_at as rattache_le
from public.articles a
join public.article_sites s on s.article_id = a.id;

grant select on public.v_article_sites to anon, authenticated;

-- Contrôle final : doit retourner les rattachements existants
select * from public.v_article_sites order by article_code, site_code limit 100;
