#!/usr/bin/env bash
# Brings the SQL side of the bundled extensions up to the libraries in this
# image, in every database that accepts connections. Run it after starting a
# newer image on an existing data directory:
#
#   docker exec -u postgres <container> update-extensions.sh
#
# Idempotent: an extension that is already current is left as it is, and a
# database without one of them is skipped.
set -Eeuo pipefail

psql=(psql -v ON_ERROR_STOP=1 --no-psqlrc --no-password --username "${POSTGRES_USER:-postgres}")

databases="$("${psql[@]}" --dbname template1 -AtX \
    -c 'SELECT datname FROM pg_database WHERE datallowconn ORDER BY datname')"

while IFS= read -r db; do
    [ -n "$db" ] || continue
    echo "rawback-db: updating extensions in $db"
    "${psql[@]}" --dbname "$db" <<'SQL'
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_extension WHERE extname = 'postgis') THEN
    -- Also updates postgis_raster, postgis_topology and the rest of the family.
    PERFORM postgis_extensions_upgrade();
  END IF;
  IF EXISTS (SELECT FROM pg_extension WHERE extname = 'pg_trgm') THEN
    ALTER EXTENSION pg_trgm UPDATE;
  END IF;
  IF EXISTS (SELECT FROM pg_extension WHERE extname = 'pgroonga') THEN
    ALTER EXTENSION pgroonga UPDATE;
  END IF;
END
$$;
SQL
done <<<"$databases"
