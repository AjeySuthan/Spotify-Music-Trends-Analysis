/* ==========================================================================
   Spotify Music Trends and Hit Profile Analysis (1990 to 2024)
   SQL Server script: cleaning, views, and analysis queries

   Dataset : Spotify Tracks Dataset (Updated Every Week), Kaggle, gauthamvijayaraj
   Table   : dbo.spotify_tracks (imported with SSMS "Import Flat File";
             artist_name was set to nvarchar(max))
   Download: 1 November 2026

   How to use: change the database name below, then run each section in order.
   Run each section by highlighting it and pressing F5. GO separates batches.
   ========================================================================== */

USE spotify_tracks;
GO


/* ==========================================================================
   SECTION 1: SAFETY BACKUP
   ========================================================================== */

IF OBJECT_ID('dbo.spotify_tracks_backup') IS NULL
    SELECT * INTO dbo.spotify_tracks_backup FROM dbo.spotify_tracks;
GO

SELECT COUNT(*) AS backup_rows FROM dbo.spotify_tracks_backup;   -- expect 62,317
GO


/* ==========================================================================
   SECTION 2: DATA QUALITY CHECKS (before cleaning)
   ========================================================================== */

-- Total rows
SELECT COUNT(*) AS total_rows FROM dbo.spotify_tracks;

-- Year range
SELECT MIN(year) AS first_year, MAX(year) AS last_year FROM dbo.spotify_tracks;

-- Tracks per year
SELECT year, COUNT(*) AS tracks
FROM dbo.spotify_tracks
GROUP BY year
ORDER BY year;

-- Rows with missing audio features
SELECT COUNT(*) AS rows_with_missing_audio
FROM dbo.spotify_tracks
WHERE danceability IS NULL OR energy IS NULL OR valence IS NULL
   OR loudness IS NULL OR tempo IS NULL OR acousticness IS NULL
   OR speechiness IS NULL OR liveness IS NULL;

-- Duplicate track IDs
SELECT COUNT(*) AS duplicate_ids FROM (
    SELECT track_id
    FROM dbo.spotify_tracks
    GROUP BY track_id
    HAVING COUNT(*) > 1
) x;

-- Popularity spread
SELECT MIN(popularity) AS min_pop,
       MAX(popularity) AS max_pop,
       AVG(CAST(popularity AS FLOAT)) AS avg_pop,
       SUM(CASE WHEN popularity = 0  THEN 1 ELSE 0 END) AS zero_pop,
       SUM(CASE WHEN popularity >= 70 THEN 1 ELSE 0 END) AS pop_70_plus
FROM dbo.spotify_tracks;

-- Tracks per language tag (language is NOT used in the analysis: unreliable labels)
SELECT language, COUNT(*) AS tracks
FROM dbo.spotify_tracks
GROUP BY language
ORDER BY tracks DESC;
GO


/* ==========================================================================
   SECTION 3: CLEANING
   ========================================================================== */

-- 3a. Remove rows with missing audio features (401 rows in my run)
DELETE FROM dbo.spotify_tracks
WHERE danceability IS NULL OR energy IS NULL OR valence IS NULL
   OR loudness IS NULL OR tempo IS NULL OR acousticness IS NULL
   OR speechiness IS NULL OR liveness IS NULL;
GO

-- 3b. Remove duplicate tracks, keeping the most popular copy (78 duplicates)
WITH d AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY track_id ORDER BY popularity DESC) AS rn
    FROM dbo.spotify_tracks
)
DELETE FROM d WHERE rn > 1;
GO

-- 3c. Check: rows and unique IDs should now be equal (61,839 in my run)
SELECT COUNT(*) AS rows_now, COUNT(DISTINCT track_id) AS unique_ids
FROM dbo.spotify_tracks;
GO

-- 3d. Add helper columns (only if they do not exist yet)
IF COL_LENGTH('dbo.spotify_tracks', 'duration_min') IS NULL
    ALTER TABLE dbo.spotify_tracks ADD duration_min FLOAT;
IF COL_LENGTH('dbo.spotify_tracks', 'is_hit') IS NULL
    ALTER TABLE dbo.spotify_tracks ADD is_hit INT;
GO

-- 3e. Fill duration in minutes
UPDATE dbo.spotify_tracks
SET duration_min = ROUND(duration_ms / 60000.0, 2);
GO

-- 3f. Hit flag: top 10% of popularity (cutoff was 45 in my run)
--     Highlight this whole block and run it in one go (the @cutoff variable
--     only exists during a single run).
DECLARE @cutoff FLOAT = (
    SELECT TOP 1 PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY popularity) OVER ()
    FROM dbo.spotify_tracks
);

UPDATE dbo.spotify_tracks
SET is_hit = CASE WHEN popularity >= @cutoff THEN 1 ELSE 0 END;

SELECT @cutoff AS hit_cutoff;
SELECT is_hit, COUNT(*) AS tracks
FROM dbo.spotify_tracks
GROUP BY is_hit;     -- expect about 10% hits (6,229 hits, 55,610 non-hits)
GO


/* ==========================================================================
   SECTION 4: VIEWS FOR POWER BI
   ========================================================================== */

CREATE OR ALTER VIEW dbo.v_trends_by_year AS
SELECT year,
       COUNT(*)                     AS tracks,
       ROUND(AVG(danceability), 3)  AS danceability,
       ROUND(AVG(energy), 3)        AS energy,
       ROUND(AVG(valence), 3)       AS valence,
       ROUND(AVG(loudness), 2)      AS loudness_db,
       ROUND(AVG(duration_min), 2)  AS duration_min
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY year;
GO

CREATE OR ALTER VIEW dbo.v_trends_by_era AS
SELECT CASE WHEN year BETWEEN 1990 AND 1999 THEN '1. 1990-1999'
            WHEN year BETWEEN 2000 AND 2014 THEN '2. 2000-2014'
            ELSE '3. 2015-2024' END   AS era,
       COUNT(*)                       AS tracks,
       ROUND(AVG(danceability), 3)    AS danceability,
       ROUND(AVG(energy), 3)          AS energy,
       ROUND(AVG(valence), 3)         AS valence,
       ROUND(AVG(loudness), 2)        AS loudness_db,
       ROUND(AVG(duration_min), 2)    AS duration_min
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY CASE WHEN year BETWEEN 1990 AND 1999 THEN '1. 1990-1999'
              WHEN year BETWEEN 2000 AND 2014 THEN '2. 2000-2014'
              ELSE '3. 2015-2024' END;
GO

CREATE OR ALTER VIEW dbo.v_hit_vs_nonhit AS
SELECT CASE WHEN is_hit = 1 THEN 'Hit' ELSE 'Non-hit' END AS group_name,
       COUNT(*)                     AS tracks,
       ROUND(AVG(danceability), 3)  AS danceability,
       ROUND(AVG(energy), 3)        AS energy,
       ROUND(AVG(valence), 3)       AS valence,
       ROUND(AVG(loudness), 2)      AS loudness_db,
       ROUND(AVG(tempo), 1)         AS tempo,
       ROUND(AVG(acousticness), 3)  AS acousticness,
       ROUND(AVG(duration_min), 2)  AS duration_min
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY is_hit;
GO

CREATE OR ALTER VIEW dbo.v_hit_rate_by_loudness AS
SELECT CASE WHEN loudness < -12 THEN '1. Below -12 dB'
            WHEN loudness < -9  THEN '2. -12 to -9 dB'
            WHEN loudness < -6  THEN '3. -9 to -6 dB'
            ELSE '4. Above -6 dB' END AS loudness_band,
       COUNT(*)                                  AS tracks,
       ROUND(100.0 * SUM(is_hit) / COUNT(*), 1)  AS hit_rate_pct
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY CASE WHEN loudness < -12 THEN '1. Below -12 dB'
              WHEN loudness < -9  THEN '2. -12 to -9 dB'
              WHEN loudness < -6  THEN '3. -9 to -6 dB'
              ELSE '4. Above -6 dB' END;
GO

-- Quick check that the views exist
SELECT name FROM sys.views WHERE name LIKE 'v[_]%';
GO


/* ==========================================================================
   SECTION 5: PROBLEM 1, TRENDS BY YEAR
   ========================================================================== */

-- 5a. Average sound features per year (1990 to 2024)
SELECT year,
       COUNT(*)                     AS tracks,
       ROUND(AVG(danceability), 3)  AS danceability,
       ROUND(AVG(energy), 3)        AS energy,
       ROUND(AVG(valence), 3)       AS valence,
       ROUND(AVG(loudness), 2)      AS loudness_db,
       ROUND(AVG(duration_min), 2)  AS duration_min
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY year
ORDER BY year;

-- 5b. Three-era comparison (uses every song in each era, not an average of years)
SELECT * FROM dbo.v_trends_by_era ORDER BY era;

-- 5c. Spread within eras: how much individual songs vary
SELECT CASE WHEN year BETWEEN 1990 AND 1999 THEN '1990-1999'
            WHEN year BETWEEN 2015 AND 2024 THEN '2015-2024' END AS era,
       COUNT(*)                         AS tracks,
       ROUND(STDEV(duration_min), 2)    AS duration_spread,
       ROUND(STDEV(danceability), 3)    AS danceability_spread
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 1999 OR year BETWEEN 2015 AND 2024
GROUP BY CASE WHEN year BETWEEN 1990 AND 1999 THEN '1990-1999'
              WHEN year BETWEEN 2015 AND 2024 THEN '2015-2024' END;

-- 5d. Share of zero-popularity songs per year (why average popularity is not used)
SELECT year,
       COUNT(*) AS tracks,
       ROUND(100.0 * SUM(CASE WHEN popularity = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_zero_popularity,
       ROUND(AVG(CASE WHEN popularity > 0 THEN CAST(popularity AS FLOAT) END), 1)   AS avg_popularity_excl_zero
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY year
ORDER BY year;
GO


/* ==========================================================================
   SECTION 6: PROBLEM 2, HIT VS NON-HIT PROFILE
   ========================================================================== */

-- 6a. Average sound profile of hits vs non-hits
SELECT is_hit,
       COUNT(*)                     AS tracks,
       ROUND(AVG(danceability), 3)  AS danceability,
       ROUND(AVG(energy), 3)        AS energy,
       ROUND(AVG(valence), 3)       AS valence,
       ROUND(AVG(loudness), 2)      AS loudness_db,
       ROUND(AVG(tempo), 1)         AS tempo,
       ROUND(AVG(acousticness), 3)  AS acousticness,
       ROUND(AVG(speechiness), 3)   AS speechiness,
       ROUND(AVG(duration_min), 2)  AS duration_min
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY is_hit;

-- 6b. Same comparison inside two eras (checks that era is not driving the result)
SELECT CASE WHEN year BETWEEN 1990 AND 2014 THEN '1990-2014'
            ELSE '2015-2024' END       AS era,
       is_hit,
       COUNT(*)                        AS tracks,
       ROUND(AVG(loudness), 2)         AS loudness_db,
       ROUND(AVG(energy), 3)           AS energy,
       ROUND(AVG(acousticness), 3)     AS acousticness,
       ROUND(AVG(danceability), 3)     AS danceability
FROM dbo.spotify_tracks
WHERE year BETWEEN 1990 AND 2024
GROUP BY CASE WHEN year BETWEEN 1990 AND 2014 THEN '1990-2014'
              ELSE '2015-2024' END,
         is_hit
ORDER BY era, is_hit;

-- 6c. Hit rate by loudness band
SELECT * FROM dbo.v_hit_rate_by_loudness ORDER BY loudness_band;
GO
