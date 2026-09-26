-- Form: dedicated schema so it can live beside the old Stacked tables in the same project.
-- After applying, add "form" to Dashboard → Project Settings → API → Exposed schemas.

create schema if not exists form;
grant usage on schema form to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Exercises (bundled library lives in the app; only custom ones are stored)
-- ---------------------------------------------------------------------------
create table form.custom_exercises (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
    name              text not null check (length(trim(name)) > 0),
    equipment         text,
    primary_muscle    text,
    secondary_muscles text[] not null default '{}',
    created_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Routines
-- ---------------------------------------------------------------------------
create table form.routines (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
    name       text not null check (length(trim(name)) > 0),
    notes      text,
    sort_order int  not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table form.routine_exercises (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
    routine_id   uuid not null references form.routines(id) on delete cascade,
    exercise_ref text not null,          -- bundled id (e.g. "Barbell_Squat") or "custom:<uuid>"
    position     int  not null,
    target_sets  int  not null default 3 check (target_sets between 1 and 20),
    rest_seconds int  not null default 90 check (rest_seconds between 0 and 900)
);
create index on form.routine_exercises (routine_id, position);

-- ---------------------------------------------------------------------------
-- Workouts
-- ---------------------------------------------------------------------------
create table form.workouts (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
    name             text not null,
    routine_id       uuid references form.routines(id) on delete set null,
    started_at       timestamptz not null,
    ended_at         timestamptz,
    notes            text,
    -- WHOOP (filled after the workout is matched)
    whoop_workout_id text,
    strain           numeric(4,1),
    avg_hr           int,
    max_hr           int,
    kcal             int,
    created_at       timestamptz not null default now(),
    check (ended_at is null or ended_at >= started_at)
);
create index on form.workouts (user_id, started_at desc);

create table form.workout_exercises (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
    workout_id   uuid not null references form.workouts(id) on delete cascade,
    exercise_ref text not null,
    position     int  not null,
    notes        text
);
create index on form.workout_exercises (workout_id, position);
create index on form.workout_exercises (user_id, exercise_ref);

create type form.set_kind as enum ('warmup', 'normal', 'drop', 'failure');

create table form.sets (
    id                  uuid primary key default gen_random_uuid(),
    user_id             uuid not null default auth.uid() references auth.users(id) on delete cascade,
    workout_exercise_id uuid not null references form.workout_exercises(id) on delete cascade,
    position            int  not null,
    kind                form.set_kind not null default 'normal',
    weight_kg           numeric(6,2) check (weight_kg >= 0),
    reps                int check (reps >= 0),
    rpe                 numeric(3,1) check (rpe between 1 and 10),
    completed_at        timestamptz
);
create index on form.sets (workout_exercise_id, position);

-- ---------------------------------------------------------------------------
-- Photos + journal
-- ---------------------------------------------------------------------------
create type form.photo_kind as enum ('progress', 'card');

create table form.photos (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
    workout_id   uuid references form.workouts(id) on delete set null,
    kind         form.photo_kind not null default 'progress',
    storage_path text not null,
    taken_at     timestamptz not null default now()
);
create index on form.photos (user_id, taken_at desc);

create table form.journal_entries (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
    entry_date     date not null default current_date,
    body           text not null default '',
    mood           smallint check (mood between 1 and 5),
    energy         smallint check (energy between 1 and 5),
    body_weight_kg numeric(5,2) check (body_weight_kg > 0),
    workout_id     uuid references form.workouts(id) on delete set null,
    photo_id       uuid references form.photos(id) on delete set null,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);
create index on form.journal_entries (user_id, entry_date desc);

-- ---------------------------------------------------------------------------
-- WHOOP tokens: server-only. No policies → clients can never read/write.
-- ---------------------------------------------------------------------------
create table form.whoop_connections (
    user_id       uuid primary key references auth.users(id) on delete cascade,
    whoop_user_id text,
    access_token  text not null,
    refresh_token text not null,
    expires_at    timestamptz not null,
    updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- RLS: owner-only access on every client table
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
    foreach t in array array[
        'custom_exercises', 'routines', 'routine_exercises', 'workouts',
        'workout_exercises', 'sets', 'photos', 'journal_entries'
    ] loop
        execute format('alter table form.%I enable row level security', t);
        execute format(
            'create policy "owner_all" on form.%I for all to authenticated
               using ((select auth.uid()) = user_id)
               with check ((select auth.uid()) = user_id)', t);
        execute format('grant select, insert, update, delete on form.%I to authenticated', t);
    end loop;
end $$;

alter table form.whoop_connections enable row level security;
revoke all on form.whoop_connections from anon, authenticated;
grant all on form.whoop_connections to service_role;

-- Public-facing flag so the app can show "WHOOP connected" without token access.
create view form.whoop_status with (security_invoker = false) as
    select user_id, updated_at from form.whoop_connections where user_id = auth.uid();
grant select on form.whoop_status to authenticated;

-- updated_at triggers
create function form.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger routines_touch before update on form.routines
    for each row execute function form.touch_updated_at();
create trigger journal_touch before update on form.journal_entries
    for each row execute function form.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Storage: private photo bucket, files under {user_id}/...
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('form-photos', 'form-photos', false)
on conflict (id) do nothing;

create policy "form_photos_owner_select" on storage.objects for select to authenticated
    using (bucket_id = 'form-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "form_photos_owner_insert" on storage.objects for insert to authenticated
    with check (bucket_id = 'form-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "form_photos_owner_delete" on storage.objects for delete to authenticated
    using (bucket_id = 'form-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
