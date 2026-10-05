-- =====================================================================
-- MAJI NDOGO WATER CRISIS PROJECT
-- Part 3: Auditing the data -- comparing field records to an
-- independent auditor's report
-- =====================================================================
-- An independent auditor re-visited 1,620 sites and scored them again.
-- We want to know: (1) do the scores match our original records, and
-- (2) if not, is there a pattern suggesting data errors or corruption?
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Load the auditor's report into the database
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS `auditor_report`;

CREATE TABLE `auditor_report` (
    `location_id` VARCHAR(32),
    `type_of_water_source` VARCHAR(64),
    `true_water_source_score` INT DEFAULT NULL,
    `statements` VARCHAR(255)
);
-- (auditor_report.csv then imported via Table Data Import Wizard)

-- ---------------------------------------------------------------------
-- 2. Link the auditor's report to our water_quality scores
-- ---------------------------------------------------------------------
-- auditor_report uses location_id; water_quality only has record_id.
-- The visits table bridges the two.
SELECT
    visits.location_id AS location_id,
    visits.record_id,
    auditor_report.true_water_source_score AS auditor_score,
    water_quality.subjective_quality_score AS employee_score
FROM
    auditor_report
JOIN
    visits
    ON auditor_report.location_id = visits.location_id
JOIN
    water_quality
    ON visits.record_id = water_quality.record_id
WHERE
    visits.visit_count = 1;   -- avoid duplicate records from re-visited sites

-- ---------------------------------------------------------------------
-- 3. Check how many records AGREE vs. DISAGREE
-- ---------------------------------------------------------------------
-- Agreement check (1,518 / 1,620 = 94% match)
SELECT
    visits.location_id AS location_id,
    visits.record_id,
    auditor_report.true_water_source_score AS auditor_score,
    water_quality.subjective_quality_score AS employee_score
FROM
    auditor_report
JOIN
    visits
    ON auditor_report.location_id = visits.location_id
JOIN
    water_quality
    ON visits.record_id = water_quality.record_id
WHERE
    visits.visit_count = 1
    AND auditor_report.true_water_source_score = water_quality.subjective_quality_score;

-- Disagreement check (the 102 records to investigate further)
SELECT
    visits.location_id AS location_id,
    visits.record_id,
    auditor_report.true_water_source_score AS auditor_score,
    water_quality.subjective_quality_score AS employee_score
FROM
    auditor_report
JOIN
    visits
    ON auditor_report.location_id = visits.location_id
JOIN
    water_quality
    ON visits.record_id = water_quality.record_id
WHERE
    visits.visit_count = 1
    AND auditor_report.true_water_source_score != water_quality.subjective_quality_score;

-- ---------------------------------------------------------------------
-- 4. Sanity check: is the TYPE of water source data still trustworthy?
-- ---------------------------------------------------------------------
-- Even though scores were wrong for 102 records, we relied heavily on
-- type_of_water_source in earlier analysis -- confirm it wasn't affected.
SELECT
    visits.location_id AS location_id,
    auditor_report.type_of_water_source AS auditor_source,
    water_source.type_of_water_source AS survey_source,
    visits.record_id,
    auditor_report.true_water_source_score AS auditor_score,
    water_quality.subjective_quality_score AS employee_score
FROM
    auditor_report
JOIN
    visits
    ON auditor_report.location_id = visits.location_id
JOIN
    water_quality
    ON visits.record_id = water_quality.record_id
JOIN
    water_source
    ON visits.source_id = water_source.source_id
WHERE
    visits.visit_count = 1
    AND auditor_report.true_water_source_score != water_quality.subjective_quality_score;

-- Result: auditor_source and survey_source matched on every row --
-- the type_of_water_source data is reliable, only the scores were wrong.

-- ---------------------------------------------------------------------
-- 5. Save the discrepancies as a reusable VIEW
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS Incorrect_records;

CREATE VIEW Incorrect_records AS (
    SELECT
        auditor_report.location_id,
        visits.record_id,
        employee.employee_name,
        auditor_report.true_water_source_score AS auditor_score,
        water_quality.subjective_quality_score AS employee_score,
        auditor_report.statements AS statements
    FROM
        auditor_report
    JOIN
        visits
        ON auditor_report.location_id = visits.location_id
    JOIN
        water_quality
        ON visits.record_id = water_quality.record_id
    JOIN
        employee
        ON employee.assigned_employee_id = visits.assigned_employee_id
    WHERE
        visits.visit_count = 1
        AND auditor_report.true_water_source_score != water_quality.subjective_quality_score
);

-- ---------------------------------------------------------------------
-- 6. Identify employees with an above-average number of mistakes
-- ---------------------------------------------------------------------
WITH error_count AS ( -- This CTE calculates the number of mistakes each employee made
    SELECT
        employee_name,
        COUNT(employee_name) AS number_of_mistakes
    FROM
        Incorrect_records
    /* Incorrect_records is a view that joins the audit report to the
       database for records where the auditor and employee scores
       are different */
    GROUP BY
        employee_name
),
suspect_list AS ( -- This CTE selects the employees with above-average mistakes
    SELECT
        employee_name,
        number_of_mistakes
    FROM
        error_count
    WHERE
        number_of_mistakes > (SELECT AVG(number_of_mistakes) FROM error_count)
)
-- This query filters all of the records where the "corrupt" employees gathered data.
SELECT
    employee_name,
    location_id,
    statements
FROM
    Incorrect_records
WHERE
    employee_name IN (SELECT employee_name FROM suspect_list);

-- Four suspects identified: Zuriel Matembo, Malachi Mavuso,
-- Bello Azibo, and Lalitha Kaburi

-- ---------------------------------------------------------------------
-- 7. Gathering evidence: look for mentions of "cash" in statements
-- ---------------------------------------------------------------------
WITH error_count AS (
    SELECT
        employee_name,
        COUNT(employee_name) AS number_of_mistakes
    FROM
        Incorrect_records
    GROUP BY
        employee_name
),
suspect_list AS (
    SELECT
        employee_name,
        number_of_mistakes
    FROM
        error_count
    WHERE
        number_of_mistakes > (SELECT AVG(number_of_mistakes) FROM error_count)
)
-- Records from our 4 suspects that specifically mention "cash"
SELECT
    employee_name,
    location_id,
    statements
FROM
    Incorrect_records
WHERE
    employee_name IN (SELECT employee_name FROM suspect_list)
    AND statements LIKE '%cash%';

-- Final sanity check: does ANYONE outside the suspect list also have
-- "cash" mentioned against them? (Should return 0 rows.)
WITH error_count AS (
    SELECT
        employee_name,
        COUNT(employee_name) AS number_of_mistakes
    FROM
        Incorrect_records
    GROUP BY
        employee_name
),
suspect_list AS (
    SELECT
        employee_name,
        number_of_mistakes
    FROM
        error_count
    WHERE
        number_of_mistakes > (SELECT AVG(number_of_mistakes) FROM error_count)
)
SELECT
    employee_name,
    location_id,
    statements
FROM
    Incorrect_records
WHERE
    employee_name NOT IN (SELECT employee_name FROM suspect_list)
    AND statements LIKE '%cash%';

-- Result: empty -- only the four suspects have "cash" mentioned against
-- them, strengthening the case that this is not a coincidence.
