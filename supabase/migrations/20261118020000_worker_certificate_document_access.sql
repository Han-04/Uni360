begin;

create policy worker_certificate_storage_own_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'worker-certificates'
    and exists (
      select 1
      from maintenance_api.worker_certification certificate
      where certificate.worker_id = (select auth.uid())
        and certificate.document_path = storage.objects.name
        and public.can_read_own_workforce(certificate.worker_id)
    )
  );

commit;
