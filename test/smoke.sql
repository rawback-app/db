-- Smoke test, run by test/smoke.sh against a fresh container with
-- ON_ERROR_STOP: each extension is installed where the init script puts it
-- and does the job Rawback uses it for. A failed ASSERT aborts the run.

-- 1. First start created the extensions in POSTGRES_DB and made
--    template_postgis a template.
DO $$
DECLARE
  ext text;
BEGIN
  FOREACH ext IN ARRAY ARRAY['postgis', 'pg_trgm', 'pgroonga'] LOOP
    ASSERT EXISTS (SELECT FROM pg_extension WHERE extname = ext),
      format('extension %s is missing from %s', ext, current_database());
  END LOOP;
  ASSERT EXISTS (SELECT FROM pg_database WHERE datname = 'template_postgis' AND datistemplate),
    'template_postgis is missing or not a template';
END
$$;

-- 2. PostGIS: geography distance, the way images.location is queried.
DO $$
DECLARE
  tokyo_tower geography := ST_SetSRID(ST_MakePoint(139.7454, 35.6586), 4326)::geography;
  zojoji      geography := ST_SetSRID(ST_MakePoint(139.7480, 35.6575), 4326)::geography;
  kyoto       geography := ST_SetSRID(ST_MakePoint(135.7681, 34.9858), 4326)::geography;
BEGIN
  ASSERT ST_DWithin(tokyo_tower, zojoji, 1000), 'ST_DWithin: points ~300 m apart are not within 1 km';
  ASSERT NOT ST_DWithin(tokyo_tower, kyoto, 1000), 'ST_DWithin: Tokyo and Kyoto are within 1 km';
END
$$;

-- 3. pg_trgm: the word-similarity operator library search uses, at the
--    default pg_trgm.word_similarity_threshold.
DO $$
BEGIN
  ASSERT 'sunsett' <% 'sunset over lisbon', 'pg_trgm: <% missed a one-letter typo';
  ASSERT NOT ('kyoto' <% 'sunset over lisbon'), 'pg_trgm: <% matched an unrelated word';
END
$$;

-- 4. PGroonga: full-text search over mixed-script text through the index.
CREATE TABLE smoke_captions (
  id      int PRIMARY KEY,
  caption text NOT NULL
);
INSERT INTO smoke_captions VALUES
  (1, '東京タワーの夜景'),
  (2, '京都の紅葉と金閣寺'),
  (3, '上海外滩的夜色'),
  (4, '서울 남산타워 야경'),
  (5, 'Sunset over Lisbon');
CREATE INDEX smoke_captions_pgroonga ON smoke_captions USING pgroonga (caption);
SET enable_seqscan = off;

DO $$
BEGIN
  ASSERT (SELECT array_agg(id ORDER BY id) FROM smoke_captions WHERE caption &@~ '夜景') = ARRAY[1],
    'pgroonga: Japanese query';
  ASSERT (SELECT array_agg(id ORDER BY id) FROM smoke_captions WHERE caption &@~ '夜色') = ARRAY[3],
    'pgroonga: Chinese query';
  ASSERT (SELECT array_agg(id ORDER BY id) FROM smoke_captions WHERE caption &@~ '야경') = ARRAY[4],
    'pgroonga: Korean query';
  ASSERT (SELECT array_agg(id ORDER BY id) FROM smoke_captions WHERE caption &@~ 'lisbon') = ARRAY[5],
    'pgroonga: case-insensitive English query';
  ASSERT (SELECT array_agg(id ORDER BY id) FROM smoke_captions WHERE caption &@~ '京都 OR 上海') = ARRAY[2, 3],
    'pgroonga: OR query';
END
$$;

RESET enable_seqscan;
DROP TABLE smoke_captions;

-- 5. A database created from template_postgis starts with the extensions.
CREATE DATABASE smoke_from_template TEMPLATE template_postgis;
\connect smoke_from_template

DO $$
DECLARE
  ext text;
BEGIN
  FOREACH ext IN ARRAY ARRAY['postgis', 'pg_trgm', 'pgroonga'] LOOP
    ASSERT EXISTS (SELECT FROM pg_extension WHERE extname = ext),
      format('extension %s is missing from a database created from template_postgis', ext);
  END LOOP;
END
$$;
