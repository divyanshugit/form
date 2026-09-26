-- Progress photos: body weight on each photo, and storage policies for the private bucket.
-- Safe to run more than once.

alter table form.photos
    add column if not exists body_weight_kg numeric(5,2);

-- Private bucket (created in the first migration; repeated here in case it was skipped).
insert into storage.buckets (id, name, public)
values ('form-photos', 'form-photos', false)
on conflict (id) do nothing;

-- Owner-only access: files live under {user_id}/...
do $$
declare
    policy record;
begin
    for policy in
        select * from (values
            ('form_photos_owner_select', 'select'),
            ('form_photos_owner_insert', 'insert'),
            ('form_photos_owner_update', 'update'),
            ('form_photos_owner_delete', 'delete')
        ) as p(name, action)
    loop
        if not exists (
            select 1 from pg_policies
            where schemaname = 'storage' and tablename = 'objects' and policyname = policy.name
        ) then
            if policy.action = 'insert' then
                execute format(
                    'create policy %I on storage.objects for insert to authenticated
                       with check (bucket_id = ''form-photos'' and (storage.foldername(name))[1] = (select auth.uid())::text)',
                    policy.name);
            else
                execute format(
                    'create policy %I on storage.objects for %s to authenticated
                       using (bucket_id = ''form-photos'' and (storage.foldername(name))[1] = (select auth.uid())::text)',
                    policy.name, policy.action);
            end if;
        end if;
    end loop;
end $$;

notify pgrst, 'reload schema';
