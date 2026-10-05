-- =====================================================================
-- MAJI NDOGO WATER CRISIS PROJECT
-- Part 4: From analysis to action -- building a repair plan
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Assemble a combined analysis table
-- ---------------------------------------------------------------------
-- location uses location_id, water_source uses source_id -- visits
-- bridges the two. well_pollution only has data for wells, so it must
-- be a LEFT JOIN (an INNER JOIN would silently drop every non-well row).
CREATE VIEW combined_analysis_table AS
-- This view assembles data from different tables into one to simplify analysis
SELECT
    water_source.type_of_water_source AS source_type,
    location.town_name,
    location.province_name,
    location.location_type,
    water_source.number_of_people_served AS people_served,
    visits.time_in_queue,
    well_pollution.results
FROM
    visits
LEFT JOIN
    well_pollution
    ON well_pollution.source_id = visits.source_id
INNER JOIN
    location
    ON location.location_id = visits.location_id
INNER JOIN
    water_source
    ON water_source.source_id = visits.source_id
WHERE
    visits.visit_count = 1;

-- ---------------------------------------------------------------------
-- 2. Provincial-level pivot table: % of people served by source type
-- ---------------------------------------------------------------------
WITH province_totals AS (-- This CTE calculates the population of each province
    SELECT
        province_name,
        SUM(people_served) AS total_ppl_serv
    FROM
        combined_analysis_table
    GROUP BY
        province_name
)
SELECT
    ct.province_name,
    -- These case statements create columns for each type of source.
    -- The results are aggregated and percentages are calculated
    ROUND((SUM(CASE WHEN source_type = 'river'
        THEN people_served ELSE 0 END) * 100.0 / pt.total_ppl_serv), 0) AS river,
    ROUND((SUM(CASE WHEN source_type = 'shared_tap'
        THEN people_served ELSE 0 END) * 100.0 / pt.total_ppl_serv), 0) AS shared_tap,
    ROUND((SUM(CASE WHEN source_type = 'tap_in_home'
        THEN people_served ELSE 0 END) * 100.0 / pt.total_ppl_serv), 0) AS tap_in_home,
    ROUND((SUM(CASE WHEN source_type = 'tap_in_home_broken'
        THEN people_served ELSE 0 END) * 100.0 / pt.total_ppl_serv), 0) AS tap_in_home_broken,
    ROUND((SUM(CASE WHEN source_type = 'well'
        THEN people_served ELSE 0 END) * 100.0 / pt.total_ppl_serv), 0) AS well
FROM
    combined_analysis_table ct
JOIN
    province_totals pt ON ct.province_name = pt.province_name
GROUP BY
    ct.province_name
ORDER BY
    ct.province_name;

-- Insight: Sokoto has the largest population drinking river water --
-- prioritise drilling teams there. Amanzi's taps are mostly broken --
-- fixing infrastructure there restores water AND shortens queues at once.

-- ---------------------------------------------------------------------
-- 3. Town-level pivot table (stored as a temp table for speed)
-- ---------------------------------------------------------------------
-- Town names are not unique (two towns are both called "Harare"), so
-- we must group/join on province_name + town_name together.
CREATE TEMPORARY TABLE town_aggregated_water_access
WITH town_totals AS (-- This CTE calculates the population of each town
    -- Since there are two Harare towns, we have to group by province_name and town_name
    SELECT province_name, town_name, SUM(people_served) AS total_ppl_serv
    FROM combined_analysis_table
    GROUP BY province_name, town_name
)
SELECT
    ct.province_name,
    ct.town_name,
    ROUND((SUM(CASE WHEN source_type = 'river'
        THEN people_served ELSE 0 END) * 100.0 / tt.total_ppl_serv), 0) AS river,
    ROUND((SUM(CASE WHEN source_type = 'shared_tap'
        THEN people_served ELSE 0 END) * 100.0 / tt.total_ppl_serv), 0) AS shared_tap,
    ROUND((SUM(CASE WHEN source_type = 'tap_in_home'
        THEN people_served ELSE 0 END) * 100.0 / tt.total_ppl_serv), 0) AS tap_in_home,
    ROUND((SUM(CASE WHEN source_type = 'tap_in_home_broken'
        THEN people_served ELSE 0 END) * 100.0 / tt.total_ppl_serv), 0) AS tap_in_home_broken,
    ROUND((SUM(CASE WHEN source_type = 'well'
        THEN people_served ELSE 0 END) * 100.0 / tt.total_ppl_serv), 0) AS well
FROM
    combined_analysis_table ct
JOIN -- Since the town names are not unique, we have to join on a composite key
    town_totals tt ON ct.province_name = tt.province_name AND ct.town_name = tt.town_name
GROUP BY -- We group by province first, then by town.
    ct.province_name,
    ct.town_name
ORDER BY
    ct.town_name;

SELECT * FROM town_aggregated_water_access;

-- Which town has the highest ratio of installed-but-broken taps?
SELECT
    province_name,
    town_name,
    ROUND(tap_in_home_broken / (tap_in_home_broken + tap_in_home) * 100, 0) AS Pct_broken_taps
FROM
    town_aggregated_water_access;

-- Insight: Amina (Amanzi) has infrastructure installed, but almost
-- none of it works. Only Dahabu (the capital) has reliably working
-- infrastructure -- worth noting in the final report.

-- ---------------------------------------------------------------------
-- 4. Design the Project_progress table
-- ---------------------------------------------------------------------
-- This is the deliverable: a table engineers can use to track repairs,
-- with data integrity enforced via FOREIGN KEY and CHECK constraints.
CREATE TABLE Project_progress (
    Project_id INT AUTO_INCREMENT PRIMARY KEY,
    -- Project_id: unique key, in case we revisit the same source later
    source_id VARCHAR(20) NOT NULL,
    -- source_id: every source we want to improve must already exist
    -- in water_source -- this is enforced by the FOREIGN KEY below
    Address VARCHAR(50),        -- Street address
    Town VARCHAR(30),
    Province VARCHAR(30),
    Source_type VARCHAR(50),
    Improvement VARCHAR(50),    -- What the engineers should do at that place
    Source_status VARCHAR(50) DEFAULT 'Backlog'
        CHECK (Source_status IN ('Backlog', 'In progress', 'Complete')),
    -- Source_status: by DEFAULT all projects start in the "Backlog"
    -- (a TODO list); CHECK() restricts input to these three values,
    -- keeping the data clean.
    Date_of_completion DATE,    -- Engineers fill this in once repaired
    Comments TEXT,              -- Free-form notes, no character limit
    FOREIGN KEY (source_id) REFERENCES water_source(source_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- ---------------------------------------------------------------------
-- 5. Build the query that decides WHICH sources need improving, and HOW
-- ---------------------------------------------------------------------
-- Filtering logic (combined in the WHERE clause):
--   1. visit_count = 1 (always required, avoids duplicate visit rows)
--   2. AND at least one of:
--        a. the well is NOT clean (chemically or biologically contaminated)
--        b. the source is a broken home tap or a river (always improve these)
--        c. the source is a shared tap with a queue of 30+ minutes
SELECT
    location.address,
    location.town_name,
    location.province_name,
    water_source.source_id,
    water_source.type_of_water_source,
    CASE
        WHEN well_pollution.results = 'Contaminated: Chemical' THEN 'Install RO filter'
        WHEN well_pollution.results = 'Contaminated: Biological' THEN 'Install UV and RO filter'
        WHEN type_of_water_source = 'river' THEN 'Drill well'
        WHEN type_of_water_source = 'shared_tap' AND visits.time_in_queue >= 30
            THEN CONCAT('Install ', FLOOR(visits.time_in_queue / 30), ' taps nearby')
        WHEN type_of_water_source = 'tap_in_home_broken' THEN 'Diagnose local infrastructure'
        ELSE NULL
    END AS Improvement
FROM
    water_source
LEFT JOIN
    well_pollution ON water_source.source_id = well_pollution.source_id
INNER JOIN
    visits ON water_source.source_id = visits.source_id
INNER JOIN
    location ON location.location_id = visits.location_id
WHERE
    visits.visit_count = 1
    AND (
        well_pollution.results != 'Clean'
        OR type_of_water_source IN ('tap_in_home_broken', 'river')
        OR (type_of_water_source = 'shared_tap' AND visits.time_in_queue >= 30)
    );

-- Returns 25,398 rows, each with a specific, actionable Improvement --
-- no NULL values remain.

-- ---------------------------------------------------------------------
-- 6. Populate Project_progress with the final action plan
-- ---------------------------------------------------------------------
INSERT INTO Project_progress (source_id, Address, Town, Province, Source_type, Improvement)
SELECT
    water_source.source_id,
    location.address,
    location.town_name,
    location.province_name,
    water_source.type_of_water_source,
    CASE
        WHEN well_pollution.results = 'Contaminated: Chemical' THEN 'Install RO filter'
        WHEN well_pollution.results = 'Contaminated: Biological' THEN 'Install UV and RO filter'
        WHEN type_of_water_source = 'river' THEN 'Drill well'
        WHEN type_of_water_source = 'shared_tap' AND visits.time_in_queue >= 30
            THEN CONCAT('Install ', FLOOR(visits.time_in_queue / 30), ' taps nearby')
        WHEN type_of_water_source = 'tap_in_home_broken' THEN 'Diagnose local infrastructure'
        ELSE NULL
    END AS Improvement
FROM
    water_source
LEFT JOIN
    well_pollution ON water_source.source_id = well_pollution.source_id
INNER JOIN
    visits ON water_source.source_id = visits.source_id
INNER JOIN
    location ON location.location_id = visits.location_id
WHERE
    visits.visit_count = 1
    AND (
        well_pollution.results != 'Clean'
        OR type_of_water_source IN ('tap_in_home_broken', 'river')
        OR (type_of_water_source = 'shared_tap' AND visits.time_in_queue >= 30)
    );

-- Project_progress now holds a prioritised, data-backed repair list --
-- ready for engineering teams to pick up and start executing.
