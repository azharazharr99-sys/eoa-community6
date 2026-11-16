-- EOA Community v2.0 | Supabase schema
-- Jalankan seluruh file ini di Supabase Dashboard > SQL Editor.
-- Role admin diberikan manual setelah akun admin dibuat. Jangan membuka UPDATE role ke user biasa.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Anggota EOA',
  city text,
  role text not null default 'member' check (role in ('member','admin')),
  status text not null default 'pending' check (status in ('pending','active')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.community_settings (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  category text not null default 'Informasi',
  author_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.community_settings enable row level security;
alter table public.announcements enable row level security;

-- Profile: anggota dapat melihat daftar anggota, tetapi hanya mengubah nama/kota miliknya.
drop policy if exists "Profiles readable by authenticated users" on public.profiles;
create policy "Profiles readable by authenticated users"
on public.profiles for select to authenticated using (true);

drop policy if exists "Users update own basic profile" on public.profiles;
create policy "Users update own basic profile"
on public.profiles for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id and role = (select p.role from public.profiles p where p.id = auth.uid())
  and status = (select p.status from public.profiles p where p.id = auth.uid()));

drop policy if exists "Admins update profiles" on public.profiles;
create policy "Admins update profiles"
on public.profiles for update to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (true);

-- Pengaturan dashboard bisa dibaca semua pengunjung; hanya admin yang boleh menulis.
drop policy if exists "Settings readable by everyone" on public.community_settings;
create policy "Settings readable by everyone"
on public.community_settings for select to anon, authenticated using (true);

drop policy if exists "Admins manage settings" on public.community_settings;
create policy "Admins manage settings"
on public.community_settings for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Pengumuman dapat dibaca semua pengunjung; admin mengelola konten.
drop policy if exists "Announcements readable by everyone" on public.announcements;
create policy "Announcements readable by everyone"
on public.announcements for select to anon, authenticated using (true);

drop policy if exists "Admins manage announcements" on public.announcements;
create policy "Admins manage announcements"
on public.announcements for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Buat profil otomatis setelah pendaftaran Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, city)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), 'Anggota EOA'),
    nullif(new.raw_user_meta_data ->> 'city', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Data awal dashboard.
insert into public.community_settings (key, value) values
('welcome_title', 'Membangun koneksi, menciptakan dampak.'),
('welcome_description', 'Ruang kolaborasi untuk bertumbuh, berbagi gagasan, dan menciptakan karya.'),
('about_title', 'Satu ruang, banyak kemungkinan.'),
('about_text', 'EOA Community menjadi tempat bertukar ide, membangun relasi, dan mengembangkan proyek bersama.')
on conflict (key) do nothing;

-- AKTIVASI ADMIN:
-- 1. Daftarkan akun melalui website.
-- 2. Buka Authentication > Users, salin UUID akun.
-- 3. Jalankan query ini dengan UUID milikmu:
-- update public.profiles set role = 'admin', status = 'active' where id = 'UUID-AKUN-MILIKMU';
--
-- Aktifkan Realtime untuk tabel profiles, announcements, community_settings
-- melalui Database > Publications > supabase_realtime bila belum aktif.
