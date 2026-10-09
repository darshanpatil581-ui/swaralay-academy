-- Swaralay Music Academy: Supabase schema
-- Run in Supabase Dashboard > SQL Editor (whole file, once).

-- 1. Roles ------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'student' check (role in ('admin','student'))
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

-- every new sign-up becomes a student; promote yourself to admin manually (step at the bottom)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id) values (new.id);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2. Core tables -------------------------------------------------------
create table public.batches (
  id uuid primary key default gen_random_uuid(),
  name text not null,                -- e.g. 'Batch A - Morning'
  timing text,
  active boolean default true
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  full_name text not null check (char_length(full_name) between 3 and 100),
  whatsapp text not null check (whatsapp ~ '^[6-9][0-9]{9}$'),
  dob date not null check (dob < current_date),
  class_format text not null check (class_format in ('Online','Offline')),
  track text not null check (track in ('Individual','Group')),
  batch_id uuid references batches(id),
  monthly_fee numeric(10,2) not null default 0,   -- set per student by admin
  admission_date date,                            -- drives billing; separate from dob
  status text not null default 'pending' check (status in ('pending','active','inactive')),
  created_at timestamptz default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  type text not null check (type in ('Registration','Monthly Tuition')),
  amount numeric(10,2) not null check (amount > 0),
  screenshot_path text,
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  submitted_at timestamptz default now(),
  verified_at timestamptz,
  verified_by uuid references auth.users(id)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  on_date date not null,
  status text not null check (status in ('Present','Absent','Holiday')),
  unique (student_id, on_date)
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  slot_start timestamptz not null,
  status text not null default 'booked' check (status in ('booked','cancelled')),
  created_at timestamptz default now()
);
-- DOUBLE-BOOKING PROTECTION: one active booking per exact slot, enforced by the database
create unique index one_booking_per_slot on public.bookings (slot_start) where status = 'booked';

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null, body text, image_path text,
  posted_on date default current_date
);
create table public.gallery (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('Performances','Student Recitals','Academy Events','Classes','Achievements')),
  image_path text not null, created_at timestamptz default now()
);

-- key/value settings (academy info, fees, templates, on/off switches)
create table public.settings (key text primary key, value text);
insert into settings(key,value) values
 ('academy_name','Swaralay Music Academy'),('address','Nashik'),('phone',''),('whatsapp',''),('email',''),('maps_url',''),
 ('registration_fee','750'),('upi_id','swaralay@sbi'),
 ('birthday_on','true'),('reminder_on','true'),('confirmation_on','true'),
 ('birthday_template','Dear {student_name}, Swaralay Music Academy wishes you a very Happy Birthday!'),
 ('fee_template','Dear {student_name}, your monthly tuition fee of Rs {fee} is due on {due_date}.');

-- one row per automated message; the unique key stops duplicates
create table public.whatsapp_logs (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  kind text not null check (kind in ('birthday','fee_reminder','payment_confirmation')),
  for_date date not null,
  status text not null default 'scheduled' check (status in ('scheduled','sent','failed')),
  detail text, sent_at timestamptz,
  unique (student_id, kind, for_date)
);

-- 3. Helper queries used by the daily jobs -----------------------------
-- next billing date = next monthly anniversary of admission_date
create or replace function public.next_due(adm date) returns date
language sql immutable as $$
  select (adm + (m || ' months')::interval)::date
  from generate_series(1, 1200) m
  where (adm + (m || ' months')::interval)::date > current_date limit 1;
$$;

create or replace view public.students_due_in_3_days as
  select * from students
  where status = 'active' and admission_date is not null and next_due(admission_date) = current_date + 3;

create or replace view public.students_birthday_today as
  select * from students
  where status = 'active'
    and to_char(dob,'MM-DD') = to_char(current_date,'MM-DD');

-- admin-only payment verification (atomic)
create or replace function public.verify_payment(pid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update payments set status='verified', verified_at=now(), verified_by=auth.uid()
    where id = pid and status = 'pending';
  update students set status='active', admission_date = coalesce(admission_date, current_date)
    where id = (select student_id from payments where id = pid) and status='pending';
end $$;

-- 4. Row Level Security ------------------------------------------------
alter table profiles enable row level security;
alter table batches enable row level security;
alter table students enable row level security;
alter table payments enable row level security;
alter table attendance enable row level security;
alter table bookings enable row level security;
alter table announcements enable row level security;
alter table gallery enable row level security;
alter table settings enable row level security;
alter table whatsapp_logs enable row level security;

create or replace function public.my_student_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from students where user_id = auth.uid();
$$;

create policy "own profile" on profiles for select using (id = auth.uid() or is_admin());

create policy "admin all batches" on batches for all using (is_admin()) with check (is_admin());
create policy "read batches" on batches for select using (auth.uid() is not null);

create policy "admin all students" on students for all using (is_admin()) with check (is_admin());
create policy "student reads self" on students for select using (user_id = auth.uid());
create policy "student registers self" on students for insert
  with check (user_id = auth.uid() and status = 'pending' and monthly_fee = 0);

create policy "admin all payments" on payments for all using (is_admin()) with check (is_admin());
create policy "student reads own payments" on payments for select using (student_id = my_student_id());
create policy "student submits own payment" on payments for insert
  with check (student_id = my_student_id() and status = 'pending');

create policy "admin all attendance" on attendance for all using (is_admin()) with check (is_admin());
create policy "student reads own attendance" on attendance for select using (student_id = my_student_id());

create policy "admin all bookings" on bookings for all using (is_admin()) with check (is_admin());
create policy "student reads own bookings" on bookings for select using (student_id = my_student_id());
create policy "student books own slot" on bookings for insert
  with check (student_id = my_student_id() and status = 'booked');
-- students also need to see which slots are taken, without seeing who took them:
create or replace function public.taken_slots(from_ts timestamptz, to_ts timestamptz)
returns table(slot_start timestamptz) language sql security definer set search_path = public as $$
  select slot_start from bookings where status='booked' and slot_start between from_ts and to_ts;
$$;

create policy "public read announcements" on announcements for select using (true);
create policy "admin manage announcements" on announcements for all using (is_admin()) with check (is_admin());
create policy "public read gallery" on gallery for select using (true);
create policy "admin manage gallery" on gallery for all using (is_admin()) with check (is_admin());

-- public site may read only non-sensitive settings; admin reads/writes all
create policy "public read safe settings" on settings for select
  using (key in ('academy_name','address','phone','whatsapp','email','maps_url','registration_fee','upi_id'));
create policy "admin all settings" on settings for all using (is_admin()) with check (is_admin());

create policy "admin all logs" on whatsapp_logs for all using (is_admin()) with check (is_admin());

-- 5. Storage ----------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-screenshots','payment-screenshots', false, 5242880, array['image/png','image/jpeg'])
on conflict do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-images','site-images', true, 10485760, array['image/png','image/jpeg','image/webp'])
on conflict do nothing;

-- students upload only into a folder named after their own auth id
create policy "student uploads own screenshot" on storage.objects for insert
  with check (bucket_id='payment-screenshots' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "student reads own screenshot" on storage.objects for select
  using (bucket_id='payment-screenshots' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "admin reads screenshots" on storage.objects for select
  using (bucket_id='payment-screenshots' and is_admin());
create policy "public reads site images" on storage.objects for select using (bucket_id='site-images');
create policy "admin manages site images" on storage.objects for all
  using (bucket_id='site-images' and is_admin()) with check (bucket_id='site-images' and is_admin());

-- 6. Make yourself admin (run AFTER you sign up once with your email) ----
-- update profiles set role='admin' where id = (select id from auth.users where email = 'YOUR_EMAIL_HERE');
