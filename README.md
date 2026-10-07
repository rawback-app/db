# Rawback DB

The PostgreSQL image that every Rawback service runs on. It is PostgreSQL 18 with PostGIS 3.6 and
PGroonga 4.0 on Debian trixie, published as `ghcr.io/rawback-app/db`.

It is a drop-in replacement for `docker.io/postgis/postgis:18-3.6`. It shares that image's base image,
data directory layout and `template_postgis`, and adds [PGroonga](https://pgroonga.github.io/) for
full-text search in Japanese, Chinese, Korean and every other language.

## What's inside

| Component | Version | Source |
| --- | --- | --- |
| PostgreSQL | 18, newest 18.x at build time | the official [`postgres:18-trixie`](https://hub.docker.com/_/postgres) image |
| PostGIS | 3.6.x (raster, topology and SFCGAL libraries included) | apt.postgresql.org, `postgresql-18-postgis-3` |
| PGroonga | 4.0.x | packages.groonga.org, `postgresql-18-pgdg-pgroonga` |
| pg_trgm | bundled with PostgreSQL | contrib |

The Dockerfile pins the minor versions and lets patch releases float, so every build takes the newest
18.x, 3.6.x and 4.0.x. If apt resolves a different PostGIS or PGroonga minor, the build fails rather
than ship it. Each release job's summary lists the exact versions that went into it.

The image is built for `linux/amd64` only. Apple Silicon runs it under emulation.

## Tags

| Tag | Example | Changes on | Use it for |
| --- | --- | --- | --- |
| `<pg>-<postgis>` | `18-3.6` | every release on that pair | Apps and CI. It pins the same things `postgis/postgis:18-3.6` does. |
| `<pg>` | `18` | every release on PostgreSQL 18 | Anything that should only follow the data directory's major version. |
| `<release>` | `0.0.1` | never | Pinning production. |
| `latest` | | every release | Throwaway local use only. It will cross a PostgreSQL major one day. |

Neither `18` nor `18-3.6` ever moves to another PostgreSQL major, so neither can produce a data
directory that the next container cannot open.

## Quick start

```bash
docker run -d --name rawback-db --shm-size=256m \
  -e POSTGRES_PASSWORD=change-me \
  -e POSTGRES_DB=rawback \
  -p 127.0.0.1:5432:5432 \
  -v rawback-db:/var/lib/postgresql \
  ghcr.io/rawback-app/db:18-3.6

psql "postgres://postgres:change-me@127.0.0.1:5432/rawback?sslmode=disable"
```

The volume goes on `/var/lib/postgresql`, which is where PostgreSQL 18 images expect it. `PGDATA` is
`/var/lib/postgresql/18/docker`. `--shm-size` gives parallel queries more than Docker's default 64 MB
of shared memory.

As a Podman quadlet (`/etc/containers/systemd/rawback-db.container`):

```ini
[Unit]
Description=Rawback PostgreSQL

[Container]
ContainerName=rawback-db
Image=ghcr.io/rawback-app/db:18-3.6
Environment=POSTGRES_DB=rawback
# podman secret create rawback-db-password -
Secret=rawback-db-password,type=env,target=POSTGRES_PASSWORD
Volume=rawback-db:/var/lib/postgresql
PublishPort=127.0.0.1:5432:5432
PodmanArgs=--shm-size=256m

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

The image ships a `HEALTHCHECK` (`pg_isready -h 127.0.0.1`). It turns healthy only once the real
server is listening on TCP, not while the first-start initialisation is still running.

Every variable and behaviour of the official `postgres` image applies unchanged, including
`POSTGRES_USER`, `POSTGRES_INITDB_ARGS` and extra scripts in `/docker-entrypoint-initdb.d`. Name your
own scripts so that they sort after `10-`, and the extensions will already exist when they run.

## First start

On an empty volume, `initdb/10-rawback-extensions.sh` does two things:

- It creates `template_postgis`, a template database, as `postgis/postgis` does.
- It creates `postgis`, `pg_trgm` and `pgroonga` in `template_postgis` and in `POSTGRES_DB`.

Application roles that are not superusers can therefore use these extensions without the privilege
to create them. `CREATE DATABASE app TEMPLATE template_postgis` starts a new database with the same
set.

There are two differences from `postgis/postgis`. This image does not create `postgis_topology`,
`fuzzystrmatch` or `postgis_tiger_geocoder`; their libraries are installed, so `CREATE EXTENSION`
them if you need them. It does create `pgroonga`.

The script never runs against an existing volume, because the postgres entrypoint skips
`/docker-entrypoint-initdb.d` once a data directory exists. On an existing volume, create the
extensions yourself.

## Using PGroonga

```sql
CREATE INDEX images_title_pgroonga ON images USING pgroonga (title);

SELECT id, title FROM images WHERE title &@~ '夜景 OR night';
```

- **`&@~` takes Groonga query syntax.** Whitespace means AND, `OR` means OR, `-` excludes
  (`tokyo - tower`), and quotes mark a phrase. `&@` matches a single keyword.
- **The defaults are `TokenBigram` and `NormalizerAuto`.** CJK text is indexed as bigrams, runs of
  Latin letters as words, and matching ignores case and character width. No dictionary is needed.
- **MeCab is not bundled.** If you need morphological tokenisation for Japanese, extend the image with
  `groonga-tokenizer-mecab`.
- See the [PGroonga reference](https://pgroonga.github.io/reference/) for operators, scoring and
  index options.

## Migrating from `postgis/postgis:18-3.6`

Both images are built `FROM postgres:18-trixie`. The PostgreSQL major, the glibc and ICU collation
versions and the data directory layout are all the same, so you swap the image on the existing
volume. There is no dump and restore.

1. Back up: run `pg_dumpall`, or snapshot the volume.
2. Stop the old container. Start this image with the same volume, mounted at the same path, and the
   same environment.
3. Run `docker exec -u postgres <container> update-extensions.sh`. This brings PostGIS's SQL objects
   up to the library if the patch versions differ.
4. In each database that wants it, run `CREATE EXTENSION pgroonga;` as a superuser. The first-start
   script does not run on an existing volume.

## Upgrading

- **A new release of this image** brings a PostgreSQL minor, PostGIS and PGroonga patches, or a
  rebuilt base. Pull it, recreate the container on the same volume, then run
  `docker exec -u postgres <container> update-extensions.sh`. The script is idempotent and updates
  `postgis` (and the rest of its family), `pg_trgm` and `pgroonga` in every database that has them.
- **A PostGIS minor bump** (for example 3.7) gets a new `18-3.7` tag. Follow the same steps once you
  move to that tag.
- **A PostgreSQL major** (19) is not an image swap. The data directory has to be migrated with
  `pg_upgrade`, or by dump and restore into a fresh volume. This repo will publish `19-*` tags
  alongside the `18-*` ones.

## Development

| Command | What it does |
| --- | --- |
| `make build` | Build `rawback-db:dev` |
| `make test` | Build, then run `test/smoke.sh` against a throwaway container |
| `make run` / `make stop` | Run a local server on `127.0.0.1:5432` with a `rawback-db-data` volume, or remove it |
| `make psql` | Open `psql` in the running container |

Every target accepts `DOCKER=podman`.

`test/smoke.sh <image>` starts the image on an empty volume and runs `test/smoke.sql`. That file
checks that the extensions and `template_postgis` exist, that `ST_DWithin` works on geography, that
the `<%` trigram operator works, and that PGroonga searches Japanese, Chinese, Korean and English
through its index. The script then runs the health check command and `update-extensions.sh`, and
prints the bundled versions.

### Bumping versions

Change the `ARG` lines at the top of the `Dockerfile`:

| ARG | Meaning |
| --- | --- |
| `PG_MAJOR` | PostgreSQL major and the base image tag. Changing it needs a data migration (see Upgrading) and changes the `<pg>` tags. |
| `POSTGIS_VERSION` | PostGIS minor line, which is part of the `<pg>-<postgis>` tag |
| `PGROONGA_VERSION` | PGroonga minor line |

The release workflow reads `PG_MAJOR` and `POSTGIS_VERSION` from those lines to build the tags.

## Releases

[release-please](https://github.com/googleapis/release-please) runs on every push to `main`, and
commits follow Conventional Commits. Merging its release PR does three things. It builds the image,
runs the smoke test against that exact build, and only then pushes `<release>`, `<pg>-<postgis>`,
`<pg>` and `latest` to `ghcr.io/rawback-app/db`.

A PostgreSQL minor or a patch release of PostGIS or PGroonga needs no code change, but it only
reaches the published image with a new release. Merge any `fix(deps): ...` commit to get one.

Pull requests that touch the image are built and smoke-tested by `.github/workflows/build.yml`,
without pushing.

### Pulling from GHCR

If the package is private:

- **Hosts** need `podman login ghcr.io` (or `docker login`) with a token that has `read:packages`.
- **Another repository's workflow** needs read access granted under the package's settings (*Manage
  Actions access*). It also needs registry credentials on its service container:

  ```yaml
  services:
    postgres:
      image: ghcr.io/rawback-app/db:18-3.6
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
  ```

## Related repos

- [rawback-app/server](https://github.com/rawback-app/server) is the Go backend and the first
  consumer. It needs `postgis` and `pg_trgm`.
- [rawback-app/web](https://github.com/rawback-app/web) is the Next.js web client.
- [rawback-app/ios](https://github.com/rawback-app/ios) is the iOS, iPadOS and Mac Catalyst client.

## License

MIT
