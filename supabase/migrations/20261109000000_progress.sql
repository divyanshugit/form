-- Progress: body measures, test results, HYROX splits, protein checks and milestone ticks (form.metrics),
-- plus WHOOP heart-rate zones and distance on workouts for share cards.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Workouts: WHOOP zone durations (ms in zones 0–5) and distance
-- ---------------------------------------------------------------------------
alter table form.workouts add column if not exists zone_ms bigint[];
alter table form.workouts add column if not exists distance_m numeric;

-- ---------------------------------------------------------------------------
-- Metrics: one measured number at a point in time
--   kind examples: 'weight_kg', 'waist_cm', 'test:run_1k_s', 'test:pullups_max',
--                  'hyrox:ski_s', 'protein_ok', 'milestone:first_pullup'
-- ---------------------------------------------------------------------------
create table if not exists form.metrics (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    recorded_at timestamptz not null default now(),
    kind        text not null check (char_length(kind) between 1 and 80),
    value       numeric not null,
    workout_id  uuid references form.workouts (id) on delete set null,
    note        text,
    created_at  timestamptz not null default now()
);

create index if not exists metrics_user_kind_time on form.metrics (user_id, kind, recorded_at desc);

alter table form.metrics enable row level security;

do $$
begin
    if not exists (
        select 1 from pg_policies where schemaname = 'form' and tablename = 'metrics' and policyname = 'owner_all'
    ) then
        create policy "owner_all" on form.metrics for all to authenticated
            using ((select auth.uid()) = user_id)
            with check ((select auth.uid()) = user_id);
    end if;
end $$;

grant select, insert, update, delete on form.metrics to authenticated;

notify pgrst, 'reload schema';
