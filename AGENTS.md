# db — agent guide

The house PostgreSQL image for Rawback, published as `ghcr.io/rawback-app/db`. It is PostgreSQL 18
plus PostGIS 3.6 plus PGroonga 4.0 on Debian trixie, for `linux/amd64`. It is a drop-in replacement
for `docker.io/postgis/postgis:18-3.6` (same base image, same `PGDATA`, same `template_postgis`), with
PGroonga added.

There is no application code here: a Dockerfile, two shell scripts that ship in the image, a smoke
test, and the CI that builds and publishes it. README.md is the user-facing half (tags, quick start,
migration, upgrading). This file is the operational half.

Consumers are `../server` (it needs `postgis` and `pg_trgm`; see "Search & geo" in its AGENTS.md) and,
later, every other Rawback service that needs Postgres.

## Commands

```bash
make build                  # docker build -t rawback-db:dev .
make test                   # build + test/smoke.sh rawback-db:dev
make run / make stop        # local server on 127.0.0.1:5432, volume rawback-db-data
make psql                   # psql inside the running container
DOCKER=podman make test     # every target takes DOCKER=
test/smoke.sh <image>       # smoke-test any image, e.g. one pulled from GHCR
```

## Layout

| Path | What |
| --- | --- |
| `Dockerfile` | `FROM postgres:${PG_MAJOR}-trixie`, plus PostGIS from apt.postgresql.org and PGroonga from packages.groonga.org |
| `initdb/10-rawback-extensions.sh` | Copied to `/docker-entrypoint-initdb.d/`. On first start it creates `template_postgis`, then `postgis`, `pg_trgm` and `pgroonga` in it and in `$POSTGRES_DB`. |
| `scripts/update-extensions.sh` | Copied to `/usr/local/bin/`. Run after an image upgrade: `postgis_extensions_upgrade()` and `ALTER EXTENSION ... UPDATE` in every database that accepts connections. |
| `test/smoke.sh`, `test/smoke.sql` | Start the image, assert that every extension works, run the health check command and the update script, and print the versions (also to `$GITHUB_STEP_SUMMARY`). |
| `.github/workflows/build.yml` | On PR (path-filtered) and `workflow_dispatch`: build and smoke test, no push |
| `.github/workflows/release.yml` | release-please; on a release, build, smoke test, then push to GHCR |
| `release-please-config.json`, `.release-please-manifest.json`, `version.txt` | `release-type: simple`, `always-bump-patch` |

## Invariants

- **`PG_MAJOR` is a data-format decision, not a version bump.** A PG 19 server cannot open a PG 18
  data directory. Changing the `ARG` needs a migration plan (`pg_upgrade` or dump and restore) for
  every deployment. The `18` and `18-3.6` tags must never point at another major.
- **The base must stay trixie or newer.** PGroonga dropped Debian 12 in 4.0.8. The Groonga apt
  source is chosen by the codename in `/etc/os-release`, so a base change follows automatically, but
  only if Groonga publishes for that codename.
- **Minor lines are pinned; patch releases float.** `POSTGIS_VERSION` and `PGROONGA_VERSION` are
  asserted against `dpkg-query` after install. A new minor in apt fails the build on purpose: existing
  databases need `update-extensions.sh` after a minor bump, and `POSTGIS_VERSION` is part of the
  image tag. Bump the `ARG`, and don't loosen the check.
- **The release workflow reads `ARG PG_MAJOR=` and `ARG POSTGIS_VERSION=` with `sed`** to build the
  `<pg>-<postgis>` and `<pg>` tags. Keep those lines in the form `ARG NAME=value`, one per line.
- **The init script runs only on an empty data directory.** Anything that existing deployments also
  need belongs in `update-extensions.sh` and the README's upgrade steps, not only in `initdb/`. The
  script is executable, so the entrypoint runs it as a subprocess instead of sourcing it. It
  therefore uses its own `psql`, not the entrypoint's `docker_process_sql`.
- **Only the extensions Rawback uses are created** (`postgis`, `pg_trgm`, `pgroonga`). Unlike
  `postgis/postgis`, topology and the tiger geocoder are installed but not created. Adding an
  extension to the init script means adding it to `smoke.sql`, to `update-extensions.sh`, and to the
  README's "First start".
- **The health check is TCP on purpose** (`pg_isready -h 127.0.0.1`). During first start the
  entrypoint runs a socket-only server, and the smoke test relies on the same distinction to wait for
  the real one.
- **Release pushes what was tested.** The release job builds with `load: true`, smoke-tests that
  image, then runs build-push again on the same builder, so every layer comes from that build's
  cache. Don't add a step between them that changes the build context.

## Validation

```bash
make test
```

The build needs apt.postgresql.org, deb.debian.org and packages.groonga.org. A sandbox that cannot
reach them cannot build the image, and then **CI is the only build verification**. The `Build`
workflow runs on any PR that touches `Dockerfile`, `.dockerignore`, `initdb/`, `scripts/`, `test/` or
the workflows. Read its job summary for the versions it actually resolved.

Shell scripts should pass `shellcheck` and `bash -n`.

## Commit & PR

Conventional Commits with a scope. `feat` and `fix` cut a release (`always-bump-patch`, so it is
always a patch bump). `chore`, `test` and `ci` never cut one, because their changelog sections are
hidden.

```
feat(image): add pg_cron
fix(deps): bump PGroonga to 4.1
docs(readme): document the quadlet health check
ci(release): tag <pg>-<postgis>
```

A rebuild that only picks up floating patch versions (a PostgreSQL minor, a PostGIS or PGroonga patch)
still needs a `fix(deps): ...` commit to produce a release.

PRs should list which component versions change. When `PG_MAJOR` or a minor line changes, they
should also give the upgrade steps that consumers have to run.
