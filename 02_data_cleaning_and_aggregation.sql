-- =====================================================================
-- MAJI NDOGO WATER CRISIS PROJECT
-- Part 2: Cleaning data, honouring the workers, analysing the scope
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Clean up the employee table: generate missing email addresses
-- ---------------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;

UPDATE md_water_services.employee
SET email = CONCAT(LOWER(REPLACE(employee_name, ' ', '.')), '@ndogowater.gov');

-- ---------------------------------------------------------------------
-- 2. Clean up phone numbers (trailing whitespace was breaking SMS)
-- ---------------------------------------------------------------------
SELECT
    LENGTH(TRIM(phone_number)) AS trimmed_phone_number
FROM
    md_water_services.employee;

UPDATE md_water_services.employee
SET phone_number = TRIM(phone_number);

-- ---------------------------------------------------------------------
-- 3. Honouring the workers: where do our employees live?
-- ---------------------------------------------------------------------
SELECT
    town_name,
    COUNT(*) AS num_employees
FROM
    md_water_services.employee
GROUP BY
    town_name;

-- ---------------------------------------------------------------------
-- 4. Find our top 3 field surveyors by number of visits
-- ---------------------------------------------------------------------
SELECT
    assigned_employee_id,
    COUNT(*) AS number_of_visits
FROM
    md_water_services.visits
GROUP BY
    assigned_employee_id
ORDER BY
    number_of_visits DESC
LIMIT 3;

-- Look up their contact details to send a congratulatory message
SELECT
    employee_name,
    phone_number,
    email
FROM md_water_services.employee
WHERE assigned_employee_id IN (1, 30, 34);

-- ---------------------------------------------------------------------
-- 5. Analysing locations: where are the water sources?
-- ---------------------------------------------------------------------
SELECT
    town_name,
    COUNT(*) AS records_per_town
FROM
    md_water_services.location
GROUP BY
    town_name
ORDER BY records_per_town DESC;

SELECT
    province_name,
    COUNT(*) AS records_per_province
FROM
    md_water_services.location
GROUP BY
    province_name
ORDER BY records_per_province DESC;

-- Group by both province and town, since some town names repeat
-- across different provinces (e.g. two towns called "Harare")
SELECT
    province_name,
    town_name,
    COUNT(town_name) AS records_per_town
FROM
    md_water_services.location
GROUP BY
    town_name,
    province_name
ORDER BY records_per_town DESC;

SELECT
    location_type,
    COUNT(*) AS num_sources
FROM md_water_services.location
GROUP BY
    location_type;

-- ---------------------------------------------------------------------
-- 6. Diving into the sources: scope of the problem
-- ---------------------------------------------------------------------
SELECT
    type_of_water_source,
    SUM(number_of_people_served) AS total_people_served,
    COUNT(type_of_water_source) AS total_water_sources
FROM md_water_services.water_source
GROUP BY
    type_of_water_source
ORDER BY
    total_water_sources DESC;

-- Total number of people surveyed
SELECT
    SUM(number_of_people_served) AS total_people
FROM md_water_services.water_source;

SELECT
    type_of_water_source,
    COUNT(type_of_water_source) AS num_of_sources
FROM md_water_services.water_source
GROUP BY type_of_water_source
ORDER BY num_of_sources DESC;

-- Average number of people served per source (helps reveal capacity/load)
SELECT
    type_of_water_source,
    ROUND(AVG(number_of_people_served), 0) AS avg_people_served,
    COUNT(type_of_water_source) AS total_water_sources
FROM md_water_services.water_source
GROUP BY
    type_of_water_source
ORDER BY
    total_water_sources DESC;

-- Percentage of the surveyed population served by each source type
SELECT
    type_of_water_source,
    ROUND(
        SUM(number_of_people_served) / (
            SELECT SUM(number_of_people_served)
            FROM md_water_services.water_source
        ) * 100, 0
    ) AS percentage_people_per_source
FROM
    md_water_services.water_source
GROUP BY
    type_of_water_source
ORDER BY
    percentage_people_per_source DESC;

-- ---------------------------------------------------------------------
-- 7. Start of a solution: ranking sources for repair priority
-- ---------------------------------------------------------------------
-- Rank each TYPE of water source by total population served
-- (tap_in_home excluded -- it's already the best possible source)
SELECT
    type_of_water_source,
    SUM(number_of_people_served) AS population_served,
    RANK() OVER (ORDER BY SUM(number_of_people_served) DESC) AS rank_by_population
FROM
    md_water_services.water_source
WHERE
    type_of_water_source != 'tap_in_home'
GROUP BY
    type_of_water_source;

-- Rank individual SOURCES within each type, by population served
SELECT
    source_id,
    type_of_water_source,
    number_of_people_served,
    DENSE_RANK() OVER (
        PARTITION BY type_of_water_source
        ORDER BY number_of_people_served DESC
    ) AS priority_rank
FROM
    md_water_services.water_source
WHERE
    type_of_water_source != 'tap_in_home';

-- ---------------------------------------------------------------------
-- 8. Analysing queues: how long did the survey take, and how long
--    do citizens wait for water?
-- ---------------------------------------------------------------------
SELECT
    DATEDIFF(MAX(time_of_record), MIN(time_of_record)) AS survey_duration
FROM
    md_water_services.visits;

-- Average queue time (0-minute "queues" from in-home taps are excluded
-- via NULLIF, since AVG() ignores NULLs)
SELECT
    AVG(NULLIF(time_in_queue, 0)) AS avg_queue_time
FROM
    md_water_services.visits;

-- Average queue time by day of the week
SELECT
    DAYNAME(time_of_record) AS day_of_week,
    AVG(NULLIF(time_in_queue, 0)) AS avg_queue_time
FROM
    md_water_services.visits
GROUP BY
    day_of_week
ORDER BY avg_queue_time;

-- Average queue time by hour of the day
SELECT
    TIME_FORMAT(TIME(time_of_record), '%H:00') AS hour_of_day,
    ROUND(AVG(NULLIF(time_in_queue, 0)), 0) AS avg_queue_time
FROM
    md_water_services.visits
GROUP BY
    hour_of_day
ORDER BY
    hour_of_day;

-- Build a pivot table: queue time broken down by both hour AND day
-- (demonstrated here for Sunday; repeat the CASE pattern for each day)
SELECT
    TIME_FORMAT(TIME(time_of_record), '%H:00') AS hour_of_day,
    DAYNAME(time_of_record),
    CASE
        WHEN DAYNAME(time_of_record) = 'Sunday' THEN time_in_queue
        ELSE NULL
    END AS Sunday
FROM
    md_water_services.visits
WHERE
    time_in_queue != 0; -- this excludes other sources with 0 queue times

-- ---------------------------------------------------------------------
-- 9. Extra practice queries
-- ---------------------------------------------------------------------
-- Which 2 employees made the fewest visits?
SELECT
    assigned_employee_id,
    COUNT(*) AS number_of_visit
FROM md_water_services.visits
GROUP BY
    assigned_employee_id
ORDER BY number_of_visit ASC
LIMIT 2;

SELECT
    employee_name,
    position
FROM md_water_services.employee
WHERE assigned_employee_id IN (20, 22);

-- Which months had the most/fewest "Clean" well results?
SELECT
    MONTHNAME(date) AS month_,
    COUNT(*) AS number_of_clean_sources
FROM
    md_water_services.well_pollution
WHERE
    results = 'Clean'
GROUP BY
    month_
ORDER BY
    number_of_clean_sources DESC;

-- How many days was the water source at '38 Marrakech Avenue' surveyed?
SELECT location_id
FROM md_water_services.location
WHERE address = '38 Marrakech Avenue';

SELECT
    DATEDIFF(MAX(time_of_record), MIN(time_of_record)) AS days_surveyed
FROM
    md_water_services.visits
WHERE
    location_id = (
        SELECT location_id
        FROM md_water_services.location
        WHERE address = '38 Marrakech Avenue'
    );
