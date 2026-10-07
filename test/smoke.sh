#!/usr/bin/env bash
# Starts the image on an empty volume, waits for the real server, then runs
# smoke.sql, the image's health check command and update-extensions.sh against
# it. Prints the bundled versions, and adds them to the job summary in CI.
#
#   test/smoke.sh <image>        # DOCKER=podman test/smoke.sh <image>
set -Eeuo pipefail

image="${1:?usage: test/smoke.sh <image>}"
docker="${DOCKER:-docker}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name="rawback-db-smoke-$$"
password=smoke

cleanup() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "smoke test failed; container logs:" >&2
        "$docker" logs "$name" >&2 || true
    fi
    "$docker" rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$docker" run -d --name "$name" \
    -e POSTGRES_PASSWORD="$password" \
    -e POSTGRES_DB=rawback_smoke \
    "$image" >/dev/null

# Over TCP on purpose: the entrypoint runs the init scripts against a
# socket-only server and restarts it, so only the final server answers here.
psql=("$docker" exec -i -e PGPASSWORD="$password" "$name"
    psql -h 127.0.0.1 -U postgres -d rawback_smoke -X -v ON_ERROR_STOP=1)

for _ in $(seq 1 90); do
    if "${psql[@]}" -qAt -c 'SELECT 1' >/dev/null 2>&1; then
        ready=1
        break
    fi
    if [ "$("$docker" inspect -f '{{.State.Running}}' "$name")" != true ]; then
        echo "container exited during startup" >&2
        exit 1
    fi
    sleep 1
done
if [ -z "${ready:-}" ]; then
    echo "server did not accept TCP connections within 90s" >&2
    exit 1
fi

"${psql[@]}" -q <"$here/smoke.sql"
"$docker" exec "$name" pg_isready -q -h 127.0.0.1
"$docker" exec -u postgres "$name" update-extensions.sh

versions="$("${psql[@]}" -qAt -F ' | ' <<'SQL'
SELECT 'PostgreSQL', current_setting('server_version');
SELECT 'PostGIS', postgis_lib_version();
SELECT 'PGroonga', extversion FROM pg_extension WHERE extname = 'pgroonga';
SELECT 'pg_trgm', extversion FROM pg_extension WHERE extname = 'pg_trgm';
SQL
)"

echo "smoke test passed for $image"
echo "$versions"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### \`$image\`"
        echo
        echo "| Component | Version |"
        echo "| --- | --- |"
        while IFS= read -r line; do
            echo "| $line |"
        done <<<"$versions"
    } >>"$GITHUB_STEP_SUMMARY"
fi
