#!/usr/bin/env bash
# First start only: the postgres entrypoint runs /docker-entrypoint-initdb.d
# when the data directory is empty and never against an existing one.
#
# Creates template_postgis, as the postgis/postgis image does, and the
# extensions this image exists for in it and in $POSTGRES_DB. Databases created
# with `TEMPLATE template_postgis` then start with the same set, and roles that
# are not superusers can use them without being able to create them.
set -Eeuo pipefail

# The server is socket-only at this point; never follow a PGHOST from the
# container's environment (the entrypoint's own docker_process_sql does the same).
unset PGHOST PGHOSTADDR
psql=(psql -v ON_ERROR_STOP=1 --no-psqlrc --no-password --username "$POSTGRES_USER")

"${psql[@]}" --dbname postgres <<'SQL'
CREATE DATABASE template_postgis IS_TEMPLATE true;
SQL

for db in template_postgis "$POSTGRES_DB"; do
    echo "rawback-db: creating postgis, pg_trgm and pgroonga in $db"
    "${psql[@]}" --dbname "$db" <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgroonga;
SQL
done
