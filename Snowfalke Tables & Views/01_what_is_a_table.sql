/* ============================================================================
   YouTube : @MatuData (https://www.youtube.com/@MatuData)
   🔔 Don't forget to subscribe to the channel for more Snowflake tutorials!
   ============================================================================
   Lesson 1 – What a Snowflake table really is
   Course : Snowflake Tables & Views – The Complete Guide
   Needs  : setup/00_setup_snowbite.sql already run

   Story  : Day 1 at SnowBite. Your manager asks two questions:
            1) "Why is this query instant, and that one slow – same table?"
            2) "Can you test changes on ORDERS without touching production?"
   ============================================================================ */

USE ROLE SYSADMIN;
USE WAREHOUSE SNOWBITE_WH;
USE SCHEMA SNOWBITE_DB.CORE;

-- Turn OFF the result cache so every demo query really hits storage
-- (otherwise the 2nd run returns instantly from cache and ruins the demo)
ALTER SESSION SET USE_CACHED_RESULT = FALSE;


/* ----------------------------------------------------------------------------
   PART 1 – Meet the table
   ---------------------------------------------------------------------------- */
-- Metadata only – no warehouse needed, returns instantly
SELECT TABLE_NAME,
       TABLE_TYPE,
       IS_TRANSIENT,
       ROW_COUNT,
       ROUND(BYTES / POWER(1024, 2), 1) AS SIZE_MB,
       RETENTION_TIME                   AS TIME_TRAVEL_DAYS
FROM SNOWBITE_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CORE'
ORDER BY ROW_COUNT DESC;

-- 20M rows... but COUNT(*) is instant. Why? Snowflake keeps row counts
-- in micro-partition METADATA – it doesn't read a single row.
SELECT COUNT(*) FROM ORDERS;

-- Same trick for MIN/MAX: answered from metadata
SELECT MIN(ORDER_DATE), MAX(ORDER_DATE) FROM ORDERS;


/* ----------------------------------------------------------------------------
   PART 2 – Pruning: the fast query vs the slow query
   EXPLAIN shows the plan WITHOUT running the query (free, compile-time):
     partitionsTotal    = micro-partitions in the table
     partitionsAssigned = what's left after pruning (what will be scanned)
   ---------------------------------------------------------------------------- */

-- Query A – filter on ORDER_DATE (data was loaded in time order)
EXPLAIN USING TABULAR
SELECT COUNT(*), SUM(TOTAL_AMOUNT)
FROM ORDERS
WHERE ORDER_DATE = DATEADD(DAY, -7, CURRENT_DATE());
-- Look at the TableScan row: partitionsAssigned is tiny vs partitionsTotal

-- Query B – filter on CUSTOMER_ID (values spread across ALL partitions)
EXPLAIN USING TABULAR
SELECT COUNT(*), SUM(TOTAL_AMOUNT)
FROM ORDERS
WHERE CUSTOMER_ID = 4242;
-- partitionsAssigned ≈ partitionsTotal → full scan

-- Now actually run both and compare in Query Profile
-- (Query Profile → TableScan → "Partitions scanned" / "Partitions total")
SELECT COUNT(*), SUM(TOTAL_AMOUNT)
FROM ORDERS
WHERE ORDER_DATE = DATEADD(DAY, -7, CURRENT_DATE());

SELECT COUNT(*), SUM(TOTAL_AMOUNT)
FROM ORDERS
WHERE CUSTOMER_ID = 4242;

-- Same numbers in SQL instead of clicking through Query Profile
SELECT OPERATOR_TYPE,
       OPERATOR_STATISTICS:pruning:partitions_scanned::INT AS PARTITIONS_SCANNED,
       OPERATOR_STATISTICS:pruning:partitions_total::INT   AS PARTITIONS_TOTAL
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID()))
WHERE OPERATOR_TYPE = 'TableScan';


/* ----------------------------------------------------------------------------
   PART 3 – Immutability → Zero-copy clone
   Micro-partitions are never changed in place. A clone just points to the
   same partitions → instant, and no extra storage until you change something.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE ORDERS_DEV CLONE ORDERS;   -- 20M rows in ~1 second

SELECT COUNT(*) FROM ORDERS_DEV;

-- Break things in DEV – production stays untouched
UPDATE ORDERS_DEV
SET    TIP = TIP * 2
WHERE  ORDER_DATE = DATEADD(DAY, -1, CURRENT_DATE());

SELECT 'PROD' AS ENV, SUM(TIP) AS TIPS_YESTERDAY
FROM ORDERS
WHERE ORDER_DATE = DATEADD(DAY, -1, CURRENT_DATE())
UNION ALL
SELECT 'DEV', SUM(TIP)
FROM ORDERS_DEV
WHERE ORDER_DATE = DATEADD(DAY, -1, CURRENT_DATE());


/* ----------------------------------------------------------------------------
   PART 4 – Immutability → Time Travel
   The UPDATE didn't overwrite partitions; it wrote NEW ones and kept the
   old ones for the retention period. So we can query the past.
   ---------------------------------------------------------------------------- */
-- "Oops" moment: delete all Zurich orders in DEV
DELETE FROM ORDERS_DEV WHERE CITY_ID = 1;
SET DELETE_QID = LAST_QUERY_ID();

SELECT COUNT(*) AS ZURICH_NOW
FROM ORDERS_DEV WHERE CITY_ID = 1;                                  -- 0

SELECT COUNT(*) AS ZURICH_BEFORE_DELETE
FROM ORDERS_DEV BEFORE (STATEMENT => $DELETE_QID) WHERE CITY_ID = 1;  -- all back

-- Restore: put the deleted rows back from the past version
INSERT INTO ORDERS_DEV
SELECT * FROM ORDERS_DEV BEFORE (STATEMENT => $DELETE_QID) WHERE CITY_ID = 1;

-- Even a dropped table can come back (within the retention period)
DROP TABLE ORDERS_DEV;
UNDROP TABLE ORDERS_DEV;
SELECT COUNT(*) FROM ORDERS_DEV;


/* ----------------------------------------------------------------------------
   ENGINEER'S CORNER
   ---------------------------------------------------------------------------- */

-- 1) How well is the table clustered on a column?
--    average_depth close to 1 = great pruning; high = overlapping partitions
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS', '(ORDER_DATE)');
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS', '(CUSTOMER_ID)');

-- 2) Clustering keys: Snowflake re-sorts in the background (costs credits!)
--    Only worth it for large (multi-TB), frequently filtered tables.
--    For CUSTOMER_ID point lookups, Search Optimization is usually the better tool.
-- ALTER TABLE ORDERS CLUSTER BY (ORDER_DATE);
-- ALTER TABLE ORDERS ADD SEARCH OPTIMIZATION ON EQUALITY(CUSTOMER_ID);

-- 3) Every change creates new partitions → the old ones are kept for
--    Time Travel (+ Fail-safe for permanent tables) → storage you pay for.
--    That's the cliffhanger for Lesson 2.
--    (INFORMATION_SCHEMA.TABLE_STORAGE_METRICS can lag a bit behind.)
SELECT TABLE_NAME,
       IS_TRANSIENT,
       ROUND(ACTIVE_BYTES      / POWER(1024, 2), 1) AS ACTIVE_MB,
       ROUND(TIME_TRAVEL_BYTES / POWER(1024, 2), 1) AS TIME_TRAVEL_MB,
       ROUND(FAILSAFE_BYTES    / POWER(1024, 2), 1) AS FAILSAFE_MB,
       CLONE_GROUP_ID
FROM SNOWBITE_DB.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE TABLE_SCHEMA = 'CORE'
  AND TABLE_NAME IN ('ORDERS', 'ORDERS_DEV');


/* ----------------------------------------------------------------------------
   Cleanup
   ---------------------------------------------------------------------------- */
DROP TABLE IF EXISTS ORDERS_DEV;
ALTER SESSION UNSET USE_CACHED_RESULT;
