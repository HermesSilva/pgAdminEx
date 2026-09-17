SELECT nsp.oid
FROM pg_catalog.pg_namespace nsp
WHERE nsp.nspname = 'public'
  AND pg_catalog.has_schema_privilege(nsp.oid, 'USAGE');
