# syntax=docker/dockerfile:1

# PostgreSQL major. Changing it is a data migration (pg_upgrade or dump and
# restore), never an image swap: see "Upgrading" in README.md. The release
# workflow reads this line for the image tags.
ARG PG_MAJOR=18

# trixie is not a free choice: PGroonga dropped Debian 12 (bookworm) in 4.0.8.
FROM postgres:${PG_MAJOR}-trixie

# The PostGIS and PGroonga minor lines this image ships. Patch releases float
# to the newest in their apt repositories at build time; a new minor fails the
# build until the line is bumped here, because existing databases then need an
# extension update (scripts/update-extensions.sh). The release workflow reads
# POSTGIS_VERSION for the image tags.
ARG POSTGIS_MAJOR=3
ARG POSTGIS_VERSION=3.6
ARG PGROONGA_VERSION=4.0

LABEL org.opencontainers.image.title="rawback-db" \
      org.opencontainers.image.description="PostgreSQL ${PG_MAJOR} with PostGIS ${POSTGIS_VERSION} and PGroonga ${PGROONGA_VERSION}" \
      org.opencontainers.image.source="https://github.com/rawback-app/db" \
      org.opencontainers.image.licenses="MIT"

# PG_MAJOR comes from the base image's ENV. PostGIS is on apt.postgresql.org,
# which the base image already configures; PGroonga comes from Groonga's own
# repository, whose postgresql-*-pgdg-pgroonga packages are built against it.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    curl -fsSL --retry 3 -o /tmp/groonga-apt-source.deb \
        "https://packages.groonga.org/debian/groonga-apt-source-latest-${codename}.deb"; \
    apt-get install -y --no-install-recommends /tmp/groonga-apt-source.deb; \
    rm /tmp/groonga-apt-source.deb; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "postgresql-${PG_MAJOR}-postgis-${POSTGIS_MAJOR}" \
        "postgresql-${PG_MAJOR}-postgis-${POSTGIS_MAJOR}-scripts" \
        "postgresql-${PG_MAJOR}-pgdg-pgroonga"; \
    postgis="$(dpkg-query -W -f '${Version}' "postgresql-${PG_MAJOR}-postgis-${POSTGIS_MAJOR}")"; \
    case "$postgis" in \
        "${POSTGIS_VERSION}".*) ;; \
        *) echo "expected PostGIS ${POSTGIS_VERSION}.x, apt resolved ${postgis}" >&2; exit 1 ;; \
    esac; \
    pgroonga="$(dpkg-query -W -f '${Version}' "postgresql-${PG_MAJOR}-pgdg-pgroonga")"; \
    case "$pgroonga" in \
        "${PGROONGA_VERSION}".*) ;; \
        *) echo "expected PGroonga ${PGROONGA_VERSION}.x, apt resolved ${pgroonga}" >&2; exit 1 ;; \
    esac; \
    apt-get purge -y --auto-remove curl; \
    rm -rf /var/lib/apt/lists/*

COPY --chmod=755 initdb/ /docker-entrypoint-initdb.d/
COPY --chmod=755 scripts/update-extensions.sh /usr/local/bin/update-extensions.sh

# TCP on purpose: during first-start initialisation the entrypoint runs a
# socket-only server, so this stays unhealthy until the real one is up.
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
    CMD ["pg_isready", "-q", "-h", "127.0.0.1"]
