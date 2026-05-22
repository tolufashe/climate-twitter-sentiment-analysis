-- ============================================================
-- SECTION 1: RAW TABLE CREATION AND DATA INGESTION
-- ============================================================

-- Create raw table matching the CSV structure exactly
CREATE TABLE climate_tweets_raw (
    created_at      TIMESTAMP WITH TIME ZONE,
    id              BIGINT,
    lng             FLOAT,
    lat             FLOAT,
    topic           VARCHAR(100),
    sentiment       FLOAT,
    stance          VARCHAR(20),
    gender          VARCHAR(20),
    temperature_avg FLOAT,
    aggressiveness  VARCHAR(20)
);

-- Load raw data from CSV file
COPY climate_tweets_raw
FROM 'C:/The Climate Change Twitter Dataset.csv'
DELIMITER ','
CSV HEADER;

-- Verify row count, returns 15,789,411 rows
SELECT COUNT(*) FROM climate_tweets_raw;

-- Preview first and last 10 rows to confirm columns loaded correctly
SELECT * FROM climate_tweets_raw LIMIT 10;
SELECT * FROM climate_tweets_raw ORDER BY created_at DESC LIMIT 10;

-- Check actual date range of the dataset
SELECT MIN(created_at), MAX(created_at) FROM climate_tweets_raw;


-- ============================================================
-- SECTION 1B: DATA QUALITY INVESTIGATION
-- ============================================================

-- Check for duplicate tweets
SELECT COUNT(*) - COUNT(DISTINCT id) AS duplicate_count
FROM climate_tweets_raw;

-- Check for missing values across all columns
SELECT
    COUNT(*) - COUNT(lng)             AS missing_lng,
    COUNT(*) - COUNT(lat)             AS missing_lat,
    COUNT(*) - COUNT(topic)           AS missing_topic,
    COUNT(*) - COUNT(sentiment)       AS missing_sentiment,
    COUNT(*) - COUNT(stance)          AS missing_stance,
    COUNT(*) - COUNT(gender)          AS missing_gender,
    COUNT(*) - COUNT(temperature_avg) AS missing_temp,
    COUNT(*) - COUNT(aggressiveness)  AS missing_aggressiveness
FROM climate_tweets_raw;

-- Check distinct values in categorical columns for inconsistencies
SELECT DISTINCT stance FROM climate_tweets_raw;
SELECT DISTINCT gender FROM climate_tweets_raw;
SELECT DISTINCT aggressiveness FROM climate_tweets_raw;
SELECT DISTINCT topic FROM climate_tweets_raw;

-- Confirm sentiment is within the expected range of -1 to 1
SELECT MIN(sentiment), MAX(sentiment) FROM climate_tweets_raw;

-- Check temperature deviation range
SELECT MIN(temperature_avg), MAX(temperature_avg) FROM climate_tweets_raw;

-- Check volume of extreme temperature deviation values
SELECT
    COUNT(*) FILTER (WHERE temperature_avg > 15) AS above_15,
    COUNT(*) FILTER (WHERE temperature_avg < -15) AS below_minus_15
FROM climate_tweets_raw;

-- Verify coordinate values are within valid geographic bounds
SELECT
    MIN(lng), MAX(lng),
    MIN(lat), MAX(lat)
FROM climate_tweets_raw;

-- Check most frequent coordinate pairs
SELECT lng, lat, COUNT(*) AS frequency
FROM climate_tweets_raw
WHERE lng IS NOT NULL
GROUP BY lng, lat
ORDER BY frequency DESC
LIMIT 20;

-- Distribution across key analytical columns
SELECT topic, COUNT(*) AS tweet_count
FROM climate_tweets_raw
GROUP BY topic
ORDER BY tweet_count DESC;

SELECT stance, COUNT(*) AS tweet_count
FROM climate_tweets_raw
GROUP BY stance
ORDER BY tweet_count DESC;

SELECT aggressiveness, COUNT(*) AS tweet_count
FROM climate_tweets_raw
GROUP BY aggressiveness
ORDER BY tweet_count DESC;

-- Yearly tweet volume
SELECT EXTRACT(YEAR FROM created_at) AS year, COUNT(*) AS tweet_count
FROM climate_tweets_raw
GROUP BY year
ORDER BY year;


-- ============================================================
-- SECTION 2: DATA CLEANING
-- Creates a clean table from the raw data applying:
-- Typo fix in the topic column
-- Casing standardisation across categorical columns
-- Continent assignment derived from coordinates
-- ============================================================

-- Rows with no coordinates are assigned Other in the continent column
-- Regional analysis covers only geotagged tweets

CREATE TABLE climate_tweets_clean AS
SELECT
    created_at,
    id,
    lng,
    lat,
    CASE
        WHEN lat BETWEEN 7   AND 72  AND lng BETWEEN -170 AND -50 THEN 'North America'
        WHEN lat BETWEEN -60 AND 15  AND lng BETWEEN -82  AND -34 THEN 'South America'
        WHEN lat BETWEEN 35  AND 72  AND lng BETWEEN -25  AND 45  THEN 'Europe'
        WHEN lat BETWEEN -35 AND 37  AND lng BETWEEN -18  AND 52  THEN 'Africa'
        WHEN lat BETWEEN -11 AND 55  AND lng BETWEEN 25   AND 180 THEN 'Asia'
        WHEN lat BETWEEN -50 AND -10 AND lng BETWEEN 110  AND 180 THEN 'Oceania'
        ELSE 'Other'
    END AS continent,
    REPLACE(INITCAP(topic), 'Intervantion', 'Intervention') AS topic,
    sentiment,
    LOWER(stance)         AS stance,
    LOWER(gender)         AS gender,
    temperature_avg,
    LOWER(aggressiveness) AS aggressiveness
FROM climate_tweets_raw;

-- Verify row count matches raw table, expected 15,789,411
SELECT COUNT(*) FROM climate_tweets_clean;

-- Verify topic typo fix and casing standardisation
SELECT DISTINCT topic FROM climate_tweets_clean;
SELECT DISTINCT stance FROM climate_tweets_clean;
SELECT DISTINCT gender FROM climate_tweets_clean;
SELECT DISTINCT aggressiveness FROM climate_tweets_clean;

-- Verify continent distribution
SELECT continent, COUNT(*) AS tweet_count
FROM climate_tweets_clean
GROUP BY continent
ORDER BY tweet_count DESC;


-- ============================================================
-- SECTION 3: ANALYTICAL VIEWS FOR POWER BI
-- ============================================================

-- ------------------------------------------------------------
-- View 1: Master Aggregation View
-- Designed to feed all chart visuals and slicers in Power BI
-- Groups by all dimensions to maintain full cross-filtering interactivity
-- Filtering of Other continents and undefined gender is handled in Power BI
-- ------------------------------------------------------------

CREATE VIEW vw_master_climate_metrics AS
SELECT
    EXTRACT(YEAR FROM created_at)  AS tweet_year,
    EXTRACT(MONTH FROM created_at) AS tweet_month,
    topic,
    continent,
    gender,
    stance,
    aggressiveness,
    COUNT(id)      AS total_tweets,
    SUM(sentiment) AS total_sentiment,
    AVG(sentiment) AS avg_sentiment
FROM climate_tweets_clean
GROUP BY 1, 2, 3, 4, 5, 6, 7;

-- ------------------------------------------------------------
-- View 2: Spatial Binning View for Map
-- Designed to feed the map visual in Power BI
-- Coordinates rounded to 1 decimal place to create an 11km grid
-- Excludes rows with no coordinate data
-- ------------------------------------------------------------

CREATE VIEW vw_map_grid AS
SELECT
    ROUND(lat::NUMERIC, 1) AS grid_lat,
    ROUND(lng::NUMERIC, 1) AS grid_lng,
    COUNT(id)              AS tweet_volume,
    AVG(sentiment)         AS avg_sentiment,
    SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) AS aggressive_count
FROM climate_tweets_clean
WHERE lat IS NOT NULL AND lng IS NOT NULL
GROUP BY 1, 2;

-- NOTE: This view was built for an 11km grid spatial map visual.
-- It was replaced in the final Power BI dashboard with continent-level
-- aggregations from vw_master_climate_metrics due to rendering
-- performance issues in Power BI Service. Retained here for
-- reproducibility and future spatial analysis if performance constraints change.

-- ============================================================
-- SECTION 4: DESCRIPTIVE ANALYTICS
-- ============================================================

-- 1. Overall summary
SELECT
    COUNT(id) AS total_tweets,
    MIN(created_at) AS earliest_tweet,
    MAX(created_at) AS latest_tweet,
    ROUND(AVG(sentiment)::NUMERIC, 4) AS avg_sentiment,
    COUNT(DISTINCT topic) AS total_topics,
    COUNT(DISTINCT continent) AS total_continents
FROM climate_tweets_clean;

-- 2. Tweet volume by year
SELECT
    EXTRACT(YEAR FROM created_at) AS tweet_year,
    COUNT(id) AS total_tweets
FROM climate_tweets_clean
GROUP BY 1
ORDER BY 1;

-- 3. Stance distribution with average sentiment
SELECT
    stance,
    COUNT(id) AS total_tweets,
    ROUND(COUNT(id) * 100.0 / SUM(COUNT(id)) OVER(), 2) AS percentage,
    ROUND(AVG(sentiment)::NUMERIC, 4) AS avg_sentiment
FROM climate_tweets_clean
GROUP BY 1
ORDER BY 2 DESC;

-- 4. Topic distribution with stance breakdown
SELECT
    topic,
    COUNT(id) AS total_tweets,
    SUM(CASE WHEN stance = 'believer' THEN 1 ELSE 0 END) AS believers,
    SUM(CASE WHEN stance = 'denier' THEN 1 ELSE 0 END) AS deniers,
    SUM(CASE WHEN stance = 'neutral' THEN 1 ELSE 0 END) AS neutrals,
    ROUND(AVG(sentiment)::NUMERIC, 4) AS avg_sentiment
FROM climate_tweets_clean
GROUP BY 1
ORDER BY 2 DESC;

-- 5. Aggressiveness distribution
SELECT
    aggressiveness,
    COUNT(id) AS total_tweets,
    ROUND(COUNT(id) * 100.0 / SUM(COUNT(id)) OVER(), 2) AS percentage
FROM climate_tweets_clean
GROUP BY 1
ORDER BY 2 DESC;

-- 6. Gender distribution with stance and aggressiveness
SELECT
    gender,
    COUNT(id) AS total_tweets,
    ROUND(SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) * 100.0 / COUNT(id), 2) AS aggressive_rate,
    SUM(CASE WHEN stance = 'believer' THEN 1 ELSE 0 END) AS believers,
    SUM(CASE WHEN stance = 'denier' THEN 1 ELSE 0 END) AS deniers,
    SUM(CASE WHEN stance = 'neutral' THEN 1 ELSE 0 END) AS neutrals
FROM climate_tweets_clean
GROUP BY 1
ORDER BY 2 DESC;

-- 7. Continent contribution with stance breakdown
SELECT
    continent,
    COUNT(id) AS total_tweets,
    SUM(CASE WHEN stance = 'believer' THEN 1 ELSE 0 END) AS believers,
    SUM(CASE WHEN stance = 'denier' THEN 1 ELSE 0 END) AS deniers,
    SUM(CASE WHEN stance = 'neutral' THEN 1 ELSE 0 END) AS neutrals,
    ROUND(COUNT(id) * 100.0 / SUM(COUNT(id)) OVER(), 2) AS percentage_of_total
FROM climate_tweets_clean
WHERE continent != 'Other'
GROUP BY 1
ORDER BY 2 DESC;


-- ============================================================
-- SECTION 5: DIAGNOSTIC ANALYTICS
-- Investigates relationships and patterns to explain why certain
-- trends occur across stance, topic, region, and climate conditions
-- ============================================================

-- 1. Aggressiveness rate by stance
SELECT
    stance,
    COUNT(id) AS total_tweets,
    SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) AS aggressive_tweets,
    ROUND(SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) * 100.0 / COUNT(id), 2) AS aggressive_rate
FROM climate_tweets_clean
GROUP BY 1
ORDER BY aggressive_rate DESC;

-- 2. Sentiment trend over time by stance
SELECT
    EXTRACT(YEAR FROM created_at) AS tweet_year,
    stance,
    COUNT(id) AS total_tweets,
    ROUND(AVG(sentiment)::NUMERIC, 4) AS avg_sentiment
FROM climate_tweets_clean
GROUP BY 1, 2
ORDER BY 1, 2;

-- 3. Topic aggressiveness rate ranked
SELECT
    topic,
    COUNT(id) AS total_tweets,
    SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) AS aggressive_tweets,
    ROUND(SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) * 100.0 / COUNT(id), 2) AS aggressive_rate,
    ROUND(AVG(sentiment)::NUMERIC, 4) AS avg_sentiment
FROM climate_tweets_clean
GROUP BY 1
ORDER BY aggressive_rate DESC;

-- 4. Regional aggressiveness and sentiment comparison
SELECT
    continent,
    COUNT(id) AS total_tweets,
    SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) AS aggressive_tweets,
    ROUND(SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) * 100.0 / COUNT(id), 2) AS aggressive_rate,
    ROUND(AVG(sentiment)::NUMERIC, 4) AS avg_sentiment
FROM climate_tweets_clean
WHERE continent != 'Other'
GROUP BY 1
ORDER BY aggressive_rate DESC;

-- 5. Temperature deviation effect on aggressiveness
SELECT
    CASE
        WHEN temperature_avg <= -3 THEN '1. Unusually Cold (<= -3°C)'
        WHEN temperature_avg >= 3  THEN '3. Unusually Hot (>= 3°C)'
        ELSE '2. Normal Range'
    END AS weather_condition,
    COUNT(id) AS total_tweets,
    SUM(CASE WHEN stance = 'believer' THEN 1 ELSE 0 END) AS believers,
    SUM(CASE WHEN stance = 'denier' THEN 1 ELSE 0 END) AS deniers,
    ROUND(SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) * 100.0 / COUNT(id), 2) AS aggressive_rate
FROM climate_tweets_clean
WHERE temperature_avg IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- 6. Most aggressive topic per continent
SELECT DISTINCT ON (continent)
    continent,
    topic,
    COUNT(id) AS total_tweets,
    ROUND(SUM(CASE WHEN aggressiveness = 'aggressive' THEN 1 ELSE 0 END) * 100.0 / COUNT(id), 2) AS aggressive_rate,
    ROUND(AVG(sentiment)::NUMERIC, 4) AS avg_sentiment
FROM climate_tweets_clean
WHERE continent != 'Other'
GROUP BY continent, topic
ORDER BY continent, aggressive_rate DESC;