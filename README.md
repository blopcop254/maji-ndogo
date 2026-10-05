# maji-ndogo
# Maji Ndogo Water Crisis: A Data-Driven Investigation (SQL)

## Overview

Maji Ndogo is a fictional country facing a nationwide water crisis. This project uses **MySQL** to analyze a ~60,000-record survey database — covering water sources, field visits, queue times, water quality, and employee records — to understand the scale of the problem, uncover data integrity issues (including evidence of employee corruption), and turn the findings into a concrete, data-driven repair plan.

The project was completed in four stages, each building on the last:

1. **Data Exploration** — understanding the database structure and the story the raw tables tell
2. **Data Cleaning & Aggregation** — fixing inconsistent records, string formatting, and building summary views (window functions, pivot tables with `CASE`)
3. **Data Integrity Audit** — cross-referencing an independent auditor's report against the original survey data using multi-table `JOIN`s, `CTE`s, and `VIEW`s to flag discrepancies
4. **Action Plan** — combining all tables into a unified analysis view and generating a prioritized, engineer-ready repair list

## Database Structure

The database (`md_water_services`) contains 8 interconnected tables:

| Table | Description |
|---|---|
| `location` | Address, town, province, and urban/rural status for each surveyed site |
| `water_source` | Type of source (tap, well, shared tap, river) and population served |
| `visits` | Log of each field visit, including queue time and timestamp |
| `water_quality` | Surveyor-assigned quality score for each visit |
| `well_pollution` | Chemical and biological contamination test results for wells |
| `employee` | Field surveyor details (name, contact info, assigned role) |
| `auditor_report` | An independent auditor's re-scored results, used to validate the original survey (Part 3) |
| `Project_progress` | The final deliverable — a prioritized, engineer-ready repair action plan |

`visits` is the central table: `location_id`, `source_id`, and `assigned_employee_id` are primary keys in their respective tables, but appear as foreign keys in `visits`, linking everything together.

## Key Findings

- **60% of water sources surveyed are in rural communities**, and every province/town is well-represented in the data — confirming the survey's coverage is reliable.
- **43% of citizens rely on shared taps**, with an average of ~2,000 people sharing a single tap — the single biggest point of strain in the system.
- **31% of the population has in-home tap infrastructure, but 45% of those taps are broken** due to failed pumps, pipes, and reservoirs — meaning a single infrastructure fix can restore water to thousands of people at once.
- **18% of citizens rely on wells, but only 28% of those wells are clean** — the rest show chemical or biological contamination.
- **Average queue time exceeds 120 minutes**, with Saturdays, mornings, and evenings being the worst — directly impacting work and school attendance.
- **Data integrity audit**: cross-checking field survey scores against an independent auditor's report revealed a 94% agreement rate. Of the ~6% of records that disagreed, four employees accounted for a disproportionate share of errors — and were the *only* employees whose field notes contained unprompted references to "cash" from local informants, a pattern consistent with bribery.

## Tools & Techniques

| Area | Techniques used |
|---|---|
| Data exploration | `SELECT`, `DISTINCT`, `LIKE`, filtering |
| Data cleaning | `REPLACE`, `LOWER`, `CONCAT`, `TRIM`, `UPDATE` |
| Aggregation | `GROUP BY`, `HAVING`, `RANK()`, `DENSE_RANK()`, `ROW_NUMBER()` |
| Time analysis | `DATEDIFF`, `DAYNAME`, `TIME_FORMAT`, `NULLIF` |
| Pivoting | `CASE` statements for pivot-table-style summaries |
| Multi-table analysis | `INNER JOIN`, `LEFT JOIN`, `CTE`s (`WITH`), `VIEW`s |
| Data integrity | Subqueries, `IN`/`NOT IN`, cross-table validation |
| Action planning | `CREATE TABLE` with `PRIMARY KEY`, `FOREIGN KEY`, `CHECK` constraints, `INSERT INTO ... SELECT` |

## Repository Structure

```
maji-ndogo-sql-project/
├── README.md
└── sql/
    ├── 01_data_exploration.sql      # Initial table exploration, SELECT/LIKE basics
    ├── 02_data_cleaning.sql         # String cleaning, UPDATE, GROUP BY, window functions
    ├── 03_audit_analysis.sql        # JOINs, CTEs, VIEWs — integrity audit & corruption flagging
    └── 04_action_plan.sql           # combined_analysis_table, pivot tables, Project_progress
```

## Project Background

This project is based on the **Maji Ndogo** case study from ALX's Data Analytics program — a realistic, narrative-driven dataset designed to simulate a real-world data analysis engagement, from first exploration through to an actionable business deliverable.

