-- ACHEI · rode inteiro no SQL Editor do Supabase
create table profiles(
  id uuid primary key references auth.users on delete cascade,
  name text not null default 'Usuário', city text, whatsapp text, avatar_url text,
  is_admin boolean not null default false, created_at timestamptz default now());
create table categories(id serial primary key, name text unique not null, icon text default '📦');
create table listings(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles on delete cascade,
  title text not null check (char_length(title) between 5 and 100),
  description text not null check (char_length(description) between 10 and 3000),
  price bigint not null check (price >= 0),
  category_id int references categories, subcategory text,
  city text not null, department text not null,
  condition text not null check (condition in ('novo','seminovo','usado','com defeito')),
  images text[] not null default '{}' check (cardinality(images) between 1 and 10),
  status text not null default 'active' check (status in ('pending','active','sold','removed')),
  featured boolean not null default false,
  created_at timestamptz default now());
create index on listings(status, created_at desc);
create table favorites(user_id uuid references profiles on delete cascade, listing_id uuid references listings on delete cascade, primary key(user_id, listing_id));
create table reports(id uuid primary key default gen_random_uuid(), listing_id uuid references listings on delete cascade, reporter_id uuid references profiles on delete cascade, reason text not null check (char_length(reason) between 5 and 500), created_at timestamptz default now(), unique(listing_id, reporter_id));
create table messages(id uuid primary key default gen_random_uuid(), listing_id uuid references listings on delete cascade, sender_id uuid not null references profiles, receiver_id uuid not null references profiles, body text not null check (char_length(body) between 1 and 1000), created_at timestamptz default now());
create table reviews(id uuid primary key default gen_random_uuid(), seller_id uuid references profiles on delete cascade, reviewer_id uuid references profiles on delete cascade, rating int not null check (rating between 1 and 5), comment text check (char_length(comment) <= 500), created_at timestamptz default now(), unique(seller_id, reviewer_id), check (seller_id <> reviewer_id));

create view top_sellers as
  select p.id, p.name, p.avatar_url, p.city, count(l.id) as total
  from profiles p join listings l on l.user_id = p.id and l.status in ('active','sold')
  group by p.id order by total desc limit 8;

create function is_admin() returns boolean language sql security definer stable as
$$ select coalesce((select is_admin from profiles where id = auth.uid()), false) $$;

create function handle_new_user() returns trigger language plpgsql security definer as $$
begin insert into profiles(id, name, avatar_url)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)), new.raw_user_meta_data->>'avatar_url');
  return new; end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

-- anti-spam: máx. 5 anúncios por hora; não-admin não altera destaque/status de moderação/admin
create function guard_listing() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from listings where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 5
      then raise exception 'Limite de anúncios por hora atingido'; end if;
    if not is_admin() then new.featured := false; new.status := 'active'; end if;
  elsif not is_admin() then
    new.featured := old.featured; new.user_id := old.user_id;
    if new.status not in ('active','sold') or old.status = 'removed' then new.status := old.status; end if;
  end if; return new; end $$;
create trigger t_guard_listing before insert or update on listings for each row execute function guard_listing();

create function guard_profile() returns trigger language plpgsql as $$
begin if not is_admin() then new.is_admin := old.is_admin; end if; return new; end $$;
create trigger t_guard_profile before update on profiles for each row execute function guard_profile();

alter table profiles enable row level security; alter table categories enable row level security;
alter table listings enable row level security; alter table favorites enable row level security;
alter table reports enable row level security; alter table messages enable row level security;
alter table reviews enable row level security;

create policy "perfil público" on profiles for select using (true);
create policy "edita próprio perfil" on profiles for update using (id = auth.uid() or is_admin());
create policy "categorias públicas" on categories for select using (true);
create policy "admin gere categorias" on categories for all using (is_admin()) with check (is_admin());
create policy "ver anúncios" on listings for select using (status in ('active','sold') or user_id = auth.uid() or is_admin());
create policy "criar próprio" on listings for insert with check (user_id = auth.uid());
create policy "editar próprio ou admin" on listings for update using (user_id = auth.uid() or is_admin());
create policy "excluir próprio ou admin" on listings for delete using (user_id = auth.uid() or is_admin());
create policy "favoritos próprios" on favorites for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "denunciar" on reports for insert with check (reporter_id = auth.uid());
create policy "admin vê denúncias" on reports for select using (is_admin());
create policy "admin apaga denúncias" on reports for delete using (is_admin());
create policy "ler minhas mensagens" on messages for select using (sender_id = auth.uid() or receiver_id = auth.uid());
create policy "enviar mensagem" on messages for insert with check (sender_id = auth.uid());
create policy "avaliações públicas" on reviews for select using (true);
create policy "avaliar" on reviews for insert with check (reviewer_id = auth.uid());

alter publication supabase_realtime add table messages;

insert into storage.buckets(id, name, public) values ('listing-images','listing-images', true);
create policy "imagens públicas" on storage.objects for select using (bucket_id = 'listing-images');
create policy "upload na própria pasta" on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "apagar da própria pasta" on storage.objects for delete to authenticated
  using (bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text);

insert into categories(name, icon) values
 ('Veículos','🚗'),('Imóveis','🏠'),('Eletrônicos','📱'),('Moda','👕'),('Casa e Jardim','🛋️'),
 ('Esportes','⚽'),('Serviços','🛠️'),('Animais','🐶'),('Outros','📦');

-- Para virar admin (troque o e-mail):
-- update profiles set is_admin = true where id = (select id from auth.users where email = 'seu@email.com');
