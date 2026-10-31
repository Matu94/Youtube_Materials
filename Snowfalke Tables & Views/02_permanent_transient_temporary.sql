/* ============================================================================
   YouTube : @MatuData (https://www.youtube.com/@MatuData)
   🔔 Don't forget to subscribe to the channel for more Snowflake tutorials!
   ============================================================================
   Lesson 2 – Permanent vs Transient vs Temporary Tables
   Course : Snowflake Tables & Views – The Complete Guide
   Needs  : setup/00_setup_snowbite.sql already run

   Story  : Every night, SnowBite reloads a 500,000-row menu price feed from
            partner restaurants into MENU_PRICES_STAGING. After a week, the
            table still has 500k rows – yet Snowflake bills for 8x the storage!
   ============================================================================ */

USE ROLE SYSADMIN;
USE WAREHOUSE SNOWBITE_WH;
USE SCHEMA SNOWBITE_DB.CORE;


/* ----------------------------------------------------------------------------
   PART 1 – The Mystery: Why did our storage bill multiply?
   By default, CREATE TABLE creates a PERMANENT table:
     - Time Travel: 1 day by default (up to 90 days on Enterprise Edition)
     - Fail-safe  : 7 extra days (non-configurable, paid storage!)
   ---------------------------------------------------------------------------- */

-- Let's create a Permanent staging table with 7 days of Time Travel
CREATE OR REPLACE TABLE MENU_PRICES_STAGING
    DATA_RETENTION_TIME_IN_DAYS = 7
AS
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4())::INT                     AS ITEM_ID,
    UNIFORM(1, 1000, RANDOM())::INT                              AS RESTAURANT_ID,
    ('Item #' || SEQ4())::VARCHAR(60)                            AS ITEM_NAME,
    ROUND(UNIFORM(4.50::FLOAT, 29.90::FLOAT, RANDOM()), 2)       AS PRICE_EUR,
    CURRENT_TIMESTAMP()                                          AS LOADED_AT
FROM TABLE(GENERATOR(ROWCOUNT => 500000));

-- Simulate 3 nightly full reloads (TRUNCATE + INSERT writes brand-new partitions
-- every run, while the old partitions stay in Time Travel + 7-day Fail-safe!)
TRUNCATE TABLE MENU_PRICES_STAGING;

INSERT INTO MENU_PRICES_STAGING
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4())::INT,
    UNIFORM(1, 1000, RANDOM())::INT,
    ('Item #' || SEQ4())::VARCHAR(60),
    ROUND(UNIFORM(4.50::FLOAT, 29.90::FLOAT, RANDOM()), 2),
    CURRENT_TIMESTAMP()
FROM TABLE(GENERATOR(ROWCOUNT => 500000));

TRUNCATE TABLE MENU_PRICES_STAGING;

INSERT INTO MENU_PRICES_STAGING
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4())::INT,
    UNIFORM(1, 1000, RANDOM())::INT,
    ('Item #' || SEQ4())::VARCHAR(60),
    ROUND(UNIFORM(4.50::FLOAT, 29.90::FLOAT, RANDOM()), 2),
    CURRENT_TIMESTAMP()
FROM TABLE(GENERATOR(ROWCOUNT => 500000));

-- Check table properties right away (kind = TABLE means PERMANENT)
SHOW TABLES LIKE 'MENU_PRICES_STAGING' IN SCHEMA SNOWBITE_DB.CORE;

-- Inspect Active vs Time Travel vs Fail-safe storage
-- (Note: TABLE_STORAGE_METRICS is a metadata view that refreshes every ~30–60 min,
--  so recently truncated bytes may take a short while to appear in TIME_TRAVEL_MB)
SELECT TABLE_NAME,
       IS_TRANSIENT,
       ROUND(ACTIVE_BYTES      / POWER(1024, 2), 2) AS ACTIVE_MB,
       ROUND(TIME_TRAVEL_BYTES / POWER(1024, 2), 2) AS TIME_TRAVEL_MB,
       ROUND(FAILSAFE_BYTES    / POWER(1024, 2), 2) AS FAILSAFE_MB
FROM SNOWBITE_DB.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE TABLE_SCHEMA = 'CORE'
  AND TABLE_NAME = 'MENU_PRICES_STAGING';


/* ----------------------------------------------------------------------------
   PART 2 – The Fix: TRANSIENT Tables (for staging & reloadable data)
   - Survives across sessions until explicitly dropped (just like Permanent)
   - Time Travel: 0 or 1 day MAX
   - Fail-safe  : 0 days (NO 7-day Fail-safe tax!)
   ---------------------------------------------------------------------------- */

CREATE OR REPLACE TRANSIENT TABLE MENU_PRICES_STAGING
    DATA_RETENTION_TIME_IN_DAYS = 1
AS
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4())::INT                     AS ITEM_ID,
    UNIFORM(1, 1000, RANDOM())::INT                              AS RESTAURANT_ID,
    ('Item #' || SEQ4())::VARCHAR(60)                            AS ITEM_NAME,
    ROUND(UNIFORM(4.50::FLOAT, 29.90::FLOAT, RANDOM()), 2)       AS PRICE_EUR,
    CURRENT_TIMESTAMP()                                          AS LOADED_AT
FROM TABLE(GENERATOR(ROWCOUNT => 500000));

-- Notice: kind = TRANSIENT, retention_time = 1
SHOW TABLES LIKE 'MENU_PRICES_STAGING' IN SCHEMA SNOWBITE_DB.CORE;

-- Can we give a Transient table 7 days of Time Travel?
-- Fails ON PURPOSE: max retention for a Transient table is 1 day
--    (expected error – if you use "Run All", continue from the next statement)
ALTER TABLE MENU_PRICES_STAGING SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- For pure staging tables that can always be reloaded from source, set retention to 0:
ALTER TABLE MENU_PRICES_STAGING SET DATA_RETENTION_TIME_IN_DAYS = 0;

-- Wait: if retention is 1 day, does UNDROP still work on a Transient table? YES!
ALTER TABLE MENU_PRICES_STAGING SET DATA_RETENTION_TIME_IN_DAYS = 1;
DROP TABLE MENU_PRICES_STAGING;
UNDROP TABLE MENU_PRICES_STAGING;
SELECT COUNT(*) FROM MENU_PRICES_STAGING;


/* ----------------------------------------------------------------------------
   PART 3 – TEMPORARY Tables (for scratch work inside a single session)
   - Lives ONLY in your current session (worksheet / script connection)
   - Invisible to every other user and worksheet
   - Automatically dropped when the session ends
   - No Fail-safe (0 days); Time Travel 0–1 day within the session
   ---------------------------------------------------------------------------- */

-- Scenario: Marketing asks for a quick scratch list of Zurich VIP customers
CREATE OR REPLACE TEMPORARY TABLE TOP_ZURICH_VIPS AS
SELECT
    CUSTOMER_ID,
    COUNT(*)           AS TOTAL_ORDERS,
    SUM(TOTAL_AMOUNT)  AS LIFETIME_SPEND_EUR
FROM ORDERS
WHERE CITY_ID = 1
GROUP BY CUSTOMER_ID
HAVING COUNT(*) >= 15;

SELECT * FROM TOP_ZURICH_VIPS ORDER BY LIFETIME_SPEND_EUR DESC LIMIT 10;

-- Notice: kind = TEMPORARY
SHOW TABLES LIKE 'TOP_ZURICH_VIPS' IN SCHEMA SNOWBITE_DB.CORE;

-- Try opening a SECOND worksheet (a separate session) and running:
--    SELECT * FROM SNOWBITE_DB.CORE.TOP_ZURICH_VIPS;
--    Result: "Object 'TOP_ZURICH_VIPS' does not exist or not authorized."


/* ----------------------------------------------------------------------------
   PART 4 – The Classic Gotcha: Temporary Table Name Shadowing
   If you create a TEMPORARY table with the SAME NAME as a permanent table,
   the temporary table silently hides ("shadows") the permanent table in
   your current session!
   ---------------------------------------------------------------------------- */

-- Right now, CITIES has 8 rows
SELECT COUNT(*) AS CITIES_COUNT FROM CITIES;

-- Create a TEMPORARY table with the exact same name: CITIES
CREATE TEMPORARY TABLE CITIES AS
SELECT 99 AS CITY_ID, 'TestLab' AS CITY_NAME;

-- Now SELECT * FROM CITIES only returns 1 row in this session!
-- (Production is safe, but every query in this session now hits the temp table)
SELECT * FROM CITIES;

-- Drop the temporary table to reveal the permanent CITIES table again
DROP TABLE CITIES;
SELECT COUNT(*) AS CITIES_COUNT FROM CITIES;   -- Back to 8 rows!


/* ----------------------------------------------------------------------------
   ENGINEER'S CORNER
   ---------------------------------------------------------------------------- */

-- 1) You CANNOT change a table's type in place with ALTER TABLE.
--    Instead, use CREATE OR REPLACE TRANSIENT TABLE ... CLONE (zero-copy!)
--    One-way rule: Permanent → Transient/Temporary clone works;
--    Transient/Temporary → Permanent does NOT.
CREATE OR REPLACE TRANSIENT TABLE ORDERS_STAGE CLONE ORDERS;
SHOW TABLES LIKE 'ORDERS_STAGE' IN SCHEMA SNOWBITE_DB.CORE;
DROP TABLE IF EXISTS ORDERS_STAGE;

-- 2) Pro tip: Create a TRANSIENT SCHEMA for your staging layer!
--    Every table created inside a TRANSIENT schema is automatically TRANSIENT
--    — even if a developer forgets to write the word TRANSIENT.
CREATE OR REPLACE TRANSIENT SCHEMA SNOWBITE_DB.STAGING
    DATA_RETENTION_TIME_IN_DAYS = 0
    COMMENT = 'Transient staging layer – zero Time Travel, zero Fail-safe';

CREATE OR REPLACE TABLE SNOWBITE_DB.STAGING.RAW_COURIER_FEED (
    COURIER_ID INT,
    STATUS     VARCHAR(20)
);

-- Even though we wrote "CREATE TABLE", kind is automatically TRANSIENT!
SHOW TABLES IN SCHEMA SNOWBITE_DB.STAGING;

-- 3) Compare all table types across SNOWBITE_DB
SELECT TABLE_SCHEMA,
       TABLE_NAME,
       IS_TRANSIENT,
       RETENTION_TIME AS TIME_TRAVEL_DAYS
FROM SNOWBITE_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('CORE', 'STAGING')
ORDER BY TABLE_SCHEMA, TABLE_NAME;


/* ----------------------------------------------------------------------------
   Cleanup
   TOP_ZURICH_VIPS is temporary and disappears with the session anyway.
   MENU_PRICES_STAGING (transient) and the STAGING schema are KEPT on purpose:
   the Lesson 7 capstone audits them as part of the SnowBite architecture.
   ---------------------------------------------------------------------------- */
DROP TABLE IF EXISTS SNOWBITE_DB.CORE.TOP_ZURICH_VIPS;
-- DROP TABLE IF EXISTS SNOWBITE_DB.CORE.MENU_PRICES_STAGING;   -- keep for Lesson 7
-- DROP SCHEMA IF EXISTS SNOWBITE_DB.STAGING;                   -- keep for Lesson 7