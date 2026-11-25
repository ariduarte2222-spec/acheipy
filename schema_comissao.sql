-- ACHEI · comissão de 10% do valor do produto vendido. Pode rodar mesmo se já rodou a versão antiga.
create table if not exists commissions(
  id uuid primary key default gen_random_uuid(),
  listing_id uuid unique references listings on delete set null,
  seller_id uuid not null references profiles,
  title text not null,
  amount bigint not null default 0,
  status text not null default 'pending' check (status in ('pending','paid')),
  created_at timestamptz default now(), paid_at timestamptz);
alter table commissions alter column amount set default 0;
alter table commissions enable row level security;
drop policy if exists "ver própria comissão" on commissions;
create policy "ver própria comissão" on commissions for select using (seller_id = auth.uid() or is_admin());
drop policy if exists "admin marca pago" on commissions;
create policy "admin marca pago" on commissions for update using (is_admin());

create table if not exists settings(key text primary key, value text);
alter table settings enable row level security;
drop policy if exists "ler config" on settings;
create policy "ler config" on settings for select using (true);
drop policy if exists "admin altera config" on settings;
create policy "admin altera config" on settings for all using (is_admin()) with check (is_admin());
insert into settings values ('payment_info', 'Combine o pagamento com o administrador') on conflict do nothing;

create or replace function register_commission() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'sold' and old.status is distinct from 'sold' then
    insert into commissions(listing_id, seller_id, title, amount)
    values (new.id, new.user_id, new.title, round(new.price * 0.10))
    on conflict (listing_id) do nothing;
  elsif old.status = 'sold' and new.status = 'active' then
    delete from commissions where listing_id = new.id and status = 'pending';
  end if;
  return new;
end $$;
drop trigger if exists t_commission on listings;
create trigger t_commission after update on listings for each row execute function register_commission();

create or replace function block_unpaid() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() and exists (select 1 from commissions where seller_id = new.user_id and status = 'pending' and created_at < now() - interval '7 days')
  then raise exception 'Você tem taxa pendente há mais de 7 dias. Pague para publicar novos anúncios.'; end if;
  return new;
end $$;
drop trigger if exists t_block_unpaid on listings;
create trigger t_block_unpaid before insert on listings for each row execute function block_unpaid();

-- recalcula comissões antigas ainda pendentes (eram ₲ 100.000 fixos)
update commissions c set amount = round(l.price * 0.10) from listings l where c.listing_id = l.id and c.status = 'pending';
