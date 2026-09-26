-- Timed holds (dead hang, plank, L-sit…) store seconds on each set.
-- Safe to run more than once.
alter table form.sets
    add column if not exists duration_seconds int;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'sets_duration_seconds_check' and conrelid = 'form.sets'::regclass
    ) then
        alter table form.sets
            add constraint sets_duration_seconds_check check (duration_seconds >= 0);
    end if;
end $$;

-- Make the API see the new column right away.
notify pgrst, 'reload schema';
