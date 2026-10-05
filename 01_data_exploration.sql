-- =====================================================================
-- MAJI NDOGO WATER CRISIS PROJECT
-- Part 1: Getting to know the data
-- =====================================================================
-- Goal: Explore the database structure, understand what each table
-- contains, and get a first look at the scale and nature of the
-- water crisis in Maji Ndogo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Discover the tables in the database
-- ---------------------------------------------------------------------
SHOW TABLES;

-- Tables found: data_dictionary, employee, global_water_access,
-- location, water_quality, visits, water_source, well_pollution

-- ---------------------------------------------------------------------
-- 2. Preview each table to understand its structure and contents
-- ---------------------------------------------------------------------
SELECT * FROM md_water_services.location LIMIT 5;
SELECT * FROM md_water_services.visits LIMIT 5;
SELECT * FROM md_water_services.water_source LIMIT 5;
SELECT * FROM md_water_services.data_dictionary;

-- ---------------------------------------------------------------------
-- 3. Dive into water sources: what types exist?
-- ---------------------------------------------------------------------
SELECT DISTINCT type_of_water_source
FROM md_water_services.water_source;

-- Types found: tap_in_home, tap_in_home_broken, well, shared_tap, river

-- ---------------------------------------------------------------------
-- 4. Unpack the visits table: queue time patterns
-- ---------------------------------------------------------------------
-- Which locations had extremely long queue times (500+ minutes)?
SELECT *
FROM md_water_services.visits
WHERE time_in_queue >= 500;

-- Cross-check a few of those source_ids against water_source to see
-- what type of source causes such long queues
SELECT *
FROM md_water_services.water_source
WHERE source_id IN (
    'AkRu05234224',
    'HaZa21742224',
    'AkKi00881224',
    'HaRu19601224',
    'SoRu36096224',
    'SoRu37635224',
    'SoRu38776224'
);

-- ---------------------------------------------------------------------
-- 5. Water source quality: spotting a data integrity problem
-- ---------------------------------------------------------------------
-- Surveyors only revisited shared taps (to measure changing queue
-- times). So a visit_count = 2 record for a home tap, with a perfect
-- quality score of 10, looks suspicious -- it suggests a data entry
-- mistake (or worse).
SELECT COUNT(*)
FROM md_water_services.water_quality
WHERE subjective_quality_score = 10
    AND visit_count = 2;

-- Result: 218 suspicious records -> flagged for an independent audit
-- (this becomes the starting point of Part 3)

-- ---------------------------------------------------------------------
-- 6. Pollution issues: finding mislabeled "Clean" records
-- ---------------------------------------------------------------------
-- Some records were marked "Clean" in the results column simply
-- because the description text started with the word "Clean", even
-- though the actual biological contamination reading says otherwise.
SELECT *
FROM md_water_services.well_pollution
WHERE description LIKE 'Clean_%';   -- "Clean" followed by more text

-- Confirm the scope of the problem: Clean-labelled description, but
-- biological contamination is actually present
SELECT *
FROM md_water_services.well_pollution
WHERE description LIKE 'Clean_%'
   OR (results = 'Clean' AND biological > 0.01);

-- ---------------------------------------------------------------------
-- 7. Fix the pollution data (safely, using a backup copy first)
-- ---------------------------------------------------------------------
CREATE TABLE
    md_water_services.well_pollution_copy
AS (
    SELECT *
    FROM md_water_services.well_pollution
);

-- Case 1a: fix descriptions that mistakenly say "Clean Bacteria: E. coli"
UPDATE
    well_pollution_copy
SET
    description = 'Bacteria: E. coli'
WHERE
    description = 'Clean Bacteria: E. coli';

-- Case 1b: fix descriptions that mistakenly say "Clean Bacteria: Giardia Lamblia"
UPDATE
    well_pollution_copy
SET
    description = 'Bacteria: Giardia Lamblia'
WHERE
    description = 'Clean Bacteria: Giardia Lamblia';

-- Case 2: fix the results column where biological contamination is
-- present but results was incorrectly set to 'Clean'
UPDATE
    well_pollution_copy
SET
    results = 'Contaminated: Biological'
WHERE
    biological > 0.01 AND results = 'Clean';

-- Verify the fix worked (should return 0 rows)
SELECT *
FROM well_pollution_copy
WHERE description LIKE 'Clean_%'
   OR (results = 'Clean' AND biological > 0.01);

-- Once verified, apply the same three fixes to the real table
UPDATE
    well_pollution
SET
    description = 'Bacteria: E. coli'
WHERE
    description = 'Clean Bacteria: E. coli';

UPDATE
    well_pollution
SET
    description = 'Bacteria: Giardia Lamblia'
WHERE
    description = 'Clean Bacteria: Giardia Lamblia';

UPDATE
    well_pollution
SET
    results = 'Contaminated: Biological'
WHERE
    biological > 0.01 AND results = 'Clean';

-- Clean up the temporary backup copy
DROP TABLE
    md_water_services.well_pollution_copy;
