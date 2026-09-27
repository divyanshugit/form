-- Your own exercises: what a set records (metric) and a short description.
-- Safe to run more than once.
alter table form.custom_exercises
    add column if not exists metric text not null default 'weightReps';

alter table form.custom_exercises
    add column if not exists description text;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'custom_exercises_metric_check' and conrelid = 'form.custom_exercises'::regclass
    ) then
        alter table form.custom_exercises
            add constraint custom_exercises_metric_check
            check (metric in ('weightReps', 'bodyweightReps', 'duration'));
    end if;
end $$;

notify pgrst, 'reload schema';
