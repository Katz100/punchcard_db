create table if not exists public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  display_name varchar(30) default 'User'
)

create table if not exists public.company (
  id uuid not null primary key default gen_random_uuid(),
  profile_id uuid default auth.uid() references public.profiles(id) on delete cascade not null,
  company_name varchar(50) default 'My Company',
  phone_number varchar(50) not null,
  address varchar(255) not null,
  website varchar(255) default 'mywebsite.com',
  reward_name varchar(50) default 'Free Pizza',
  stamps_required int default 6,
  stamps_updated_at timestamp
)

create table if not exists public.roles (
  id uuid not null primary key default gen_random_uuid(),
  role_name varchar(10) not null
)

create table if not exists public.user_roles (
    profile_id uuid default auth.uid() references public.profiles(id) on delete cascade not null,
    role_id uuid references public.roles(id) on delete cascade not null,
    primary key(profile_id, role_id),
    constraint user_cannot_have_nonunique_rows unique(profile_id, role_id)
)

create table if not exists public.company_customers (
    profile_id uuid references public.profiles(id) on delete cascade not null,
    company_id uuid references public.company(id) on delete cascade not null,
    primary key(profile_id, company_id),
    constraint only_unique_row unique(profile_id, company_id)
)

create table if not exists public.customer_stamps (
  id uuid not null primary key default gen_random_uuid(),
  profile_id uuid default auth.uid() references public.profiles(id) on delete cascade not null,
  company_id uuid references public.company(id) on delete cascade not null,
  stamps_count int default 0,
  updated_at timestamp default now()
)

create table if not exists public.customer_rewards (
  id uuid not null primary key default gen_random_uuid(),
  profile_id uuid default auth.uid() references public.profiles(id) on delete cascade not null,
  company_id uuid references public.company(id) on delete cascade not null,
  rewards_count int default 0,
  updated_at timestamp default now()
)


create or replace function increment_customer_stamps(user_id uuid, company uuid)
returns void as
$$

begin
    update customer_stamps
    set stamps_count = stamps_count + 1
    where profile_id = user_id and company_id = company;

    update customer_stamps
    set updated_at = now()
    where profile_id = user_id and company_id = company;
end;
$$
language plpgsql volatile;

create or replace function on_stamps_met() 
returns trigger as $$
begin
  if new.stamps_count >= (select company.stamps_required from company where company.id = new.company_id limit 1) then
    new.stamps_count = 0;
    perform increment_customer_rewards(new.profile_id, new.company_id);
  end if;
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger customer_stamps_threshold_met
before update of stamps_count on customer_stamps
for each row
execute function on_stamps_met

create or replace function increment_customer_rewards(user_id uuid, com_id uuid)
returns void as
$$
begin
    update customer_rewards
    set rewards_count = rewards_count + 1
    where profile_id = user_id and company_id = com_id;
end;
$$
language plpgsql volatile;

create or replace function redeem_customer_reward(user_id uuid, com uuid)
returns void as 
$$
begin 
  if (select rewards_count from customer_rewards where profile_id = user_id and company_id = com) != 0 then
    update customer_rewards
    set rewards_count = rewards_count - 1
    where profile_id = user_id and company_id = com;

    update customer_rewards
    set updated_at = now()
    where profile_id = user_id and company_id = com;
  end if;
end;
$$ 
language plpgsql

create or replace function on_email_verified() 
returns trigger as $$
begin
  if new.email_confirmed_at is not null then
    insert into public.profiles(id, display_name)
    values(new.id, new.raw_user_meta_data->>'display_name');
    return new;
  end if;
end;
$$ language plpgsql security definer;

create trigger email_verified_trigger
after update of email_confirmed_at on auth.users
for each row
execute function on_email_verified();

create or replace function on_profile_added_to_company() 
returns trigger as $$
begin
  insert into customer_stamps
  values(default, new.profile_id, new.company_id, default, default);
  insert into customer_rewards
  values(default, new.profile_id, new.company_id, default, default);
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger profile_added_to_company
after insert on company_customers
for each row
execute function on_profile_added_to_company();
