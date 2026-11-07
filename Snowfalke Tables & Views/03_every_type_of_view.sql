/* ============================================================================
   YouTube : @MatuData (https://www.youtube.com/@MatuData)
   🔔 Don't forget to subscribe to the channel for more Snowflake tutorials!
   ============================================================================
   SnowBite – Lesson 3: Every Type of View Explained
   Course : Snowflake Tables & Views – The Complete Guide
   Prereq : Run setup/00_setup_snowbite.sql first.

   The SnowBite scenario today:
     1. Analysts keep copy-pasting the same 3-table join & payout formula.
     2. Restaurant partners want a portal to see ONLY their own orders —
        and must never see our SQL logic or probe competitor rows.
     3. The exec dashboard runs a daily revenue aggregation across 20M orders
        hundreds of times a day and feels sluggish.
     4. The app team has a parent/child menu category tree to flatten.
     5. BI & Cortex AI keep defining "Gross Revenue" and "Avg Delivery Time"
        differently across reports.
   ============================================================================ */

/* ----------------------------------------------------------------------------
   0. Setup context & disable result cache so timing comparisons are real
   ---------------------------------------------------------------------------- */
USE ROLE SYSADMIN;
USE WAREHOUSE SNOWBITE_WH;
USE SCHEMA SNOWBITE_DB.CORE;

ALTER SESSION SET USE_CACHED_RESULT = FALSE;


/* ============================================================================
   PART 1: STANDARD VIEW ("The Window")
   Saved SQL query. Stores 0 bytes. Computed on the fly every time you query it.
   ============================================================================ */

-- Instead of every analyst rewriting the join + 18% commission formula:
CREATE OR REPLACE VIEW V_DELIVERED_ORDERS AS
SELECT
    o.ORDER_ID,
    o.ORDER_TS,
    o.ORDER_DATE,
    o.RESTAURANT_ID,
    r.RESTAURANT_NAME,
    r.CUISINE,
    c.CITY_NAME,
    c.COUNTRY,
    o.ITEMS_COUNT,
    o.SUBTOTAL,
    o.DELIVERY_FEE,
    o.TIP,
    o.TOTAL_AMOUNT,
    ROUND(o.SUBTOTAL * 0.82, 2) AS RESTAURANT_PAYOUT_EUR,  -- 82% to restaurant
    ROUND(o.SUBTOTAL * 0.18, 2) AS SNOWBITE_COMMISSION_EUR, -- 18% platform fee
    o.DELIVERY_MINUTES,
    o.CUSTOMER_RATING
FROM ORDERS o
JOIN RESTAURANTS r ON r.RESTAURANT_ID = o.RESTAURANT_ID
JOIN CITIES c      ON c.CITY_ID       = o.CITY_ID
WHERE o.STATUS = 'DELIVERED';

-- Query the view just like a table (Snowflake pushes the filter down to ORDERS)
SELECT
    CITY_NAME,
    COUNT(*)                        AS DELIVERED_ORDERS,
    ROUND(SUM(TOTAL_AMOUNT), 0)     AS GROSS_REVENUE_EUR,
    ROUND(SUM(SNOWBITE_COMMISSION_EUR), 0) AS PLATFORM_REVENUE_EUR
FROM V_DELIVERED_ORDERS
WHERE ORDER_DATE >= DATEADD(DAY, -30, CURRENT_DATE())
GROUP BY CITY_NAME
ORDER BY DELIVERED_ORDERS DESC;

-- Check metadata: bytes = NULL / 0, is_secure = N, text = full SQL definition
SHOW VIEWS LIKE 'V_DELIVERED_ORDERS';

-- Anyone with SELECT privilege on a Standard View can inspect its SQL logic:
SELECT GET_DDL('VIEW', 'V_DELIVERED_ORDERS');


/* ============================================================================
   PART 2: SECURE VIEW ("The Frosted-Glass Window")
   Why Standard Views aren't enough for external partners / multi-tenant RLS:
     1. Standard Views expose their underlying SQL definition.
     2. The query optimizer can reorder filters (evaluating a user's tricky
        WHERE division-by-zero expression BEFORE the row-level security filter!).
   ============================================================================ */

-- Step 1: Create a mapping table that links a Snowflake Role (or User) to a Restaurant
CREATE OR REPLACE TRANSIENT TABLE PARTNER_ROLE_MAP (
    ROLE_NAME      VARCHAR(50),
    RESTAURANT_ID  INT
);

-- Map SYSADMIN to Restaurant #1 so we can test right here in our worksheet
-- (in production this row would be a dedicated partner role, e.g. 'PARTNER_ROLE_R001'):
INSERT INTO PARTNER_ROLE_MAP (ROLE_NAME, RESTAURANT_ID) VALUES
    ('SYSADMIN',          1),
    ('PARTNER_ROLE_R002', 2),
    ('PARTNER_ROLE_R003', 3);

-- Step 2: Create a SECURE VIEW that filters rows by CURRENT_ROLE()
CREATE OR REPLACE SECURE VIEW SV_PARTNER_ORDERS AS
SELECT
    o.ORDER_ID,
    o.ORDER_TS,
    o.ORDER_DATE,
    o.RESTAURANT_ID,
    r.RESTAURANT_NAME,
    o.ITEMS_COUNT,
    o.SUBTOTAL,
    ROUND(o.SUBTOTAL * 0.82, 2) AS RESTAURANT_PAYOUT_EUR,
    o.DELIVERY_MINUTES,
    o.CUSTOMER_RATING
FROM ORDERS o
JOIN RESTAURANTS r      ON r.RESTAURANT_ID = o.RESTAURANT_ID
JOIN PARTNER_ROLE_MAP m ON m.RESTAURANT_ID = o.RESTAURANT_ID
WHERE m.ROLE_NAME = CURRENT_ROLE();

-- Step 3: Query the Secure View — we ONLY see Restaurant #1's orders!
SELECT
    RESTAURANT_ID,
    RESTAURANT_NAME,
    COUNT(*)                            AS MY_ORDERS,
    ROUND(SUM(RESTAURANT_PAYOUT_EUR), 2) AS MY_TOTAL_PAYOUT_EUR
FROM SV_PARTNER_ORDERS
GROUP BY RESTAURANT_ID, RESTAURANT_NAME;

-- Step 4: Verify is_secure = 'Y'
SHOW VIEWS LIKE 'SV_PARTNER_ORDERS';

-- Step 5: Try the Scene 3 division-by-zero probing query against SV_PARTNER_ORDERS:
-- (Restaurant #2 really has orders with SUBTOTAL > 120 – max possible is ~€144)
-- Because SV_PARTNER_ORDERS is SECURE, Snowflake filters to Restaurant #1 FIRST,
-- so Competitor Restaurant #2 rows never trigger division by zero!
SELECT
    COUNT(*) AS SAFE_ROWS_RETURNED
FROM SV_PARTNER_ORDERS
WHERE 1 / IFF(RESTAURANT_ID = 2 AND SUBTOTAL > 120, 0, 1) = 1;


/* ============================================================================
   PART 3: MATERIALIZED VIEW ("The Auto-Updated Photo")
   Requires: Enterprise Edition
   Precomputes and stores the query result on disk in micro-partitions.
   Snowflake automatically maintains it in the background when ORDERS changes.
   Rule: Single base table only (NO JOINs!).
   ============================================================================ */

-- First, feel the baseline speed of aggregating 20,000,000 rows directly:
SELECT
    ORDER_DATE,
    CITY_ID,
    COUNT(*)          AS TOTAL_ORDERS,
    SUM(TOTAL_AMOUNT) AS GROSS_REVENUE_EUR,
    SUM(SUBTOTAL)     AS FOOD_SUBTOTAL_EUR
FROM ORDERS
WHERE STATUS = 'DELIVERED'
GROUP BY ORDER_DATE, CITY_ID
ORDER BY ORDER_DATE DESC, CITY_ID
LIMIT 20;

-- Now create a MATERIALIZED VIEW on ORDERS (single base table, no joins):
CREATE OR REPLACE MATERIALIZED VIEW MV_DAILY_CITY_REVENUE AS
SELECT
    ORDER_DATE,
    CITY_ID,
    COUNT(*)          AS TOTAL_ORDERS,
    SUM(TOTAL_AMOUNT) AS GROSS_REVENUE_EUR,
    SUM(SUBTOTAL)     AS FOOD_SUBTOTAL_EUR
FROM ORDERS
WHERE STATUS = 'DELIVERED'
GROUP BY ORDER_DATE, CITY_ID;

-- Query the Materialized View — instant! (Reads ~5,800 pre-aggregated rows instead of 20M)
-- And you CAN join the Materialized View with CITIES at query time:
SELECT
    mv.ORDER_DATE,
    c.CITY_NAME,
    mv.TOTAL_ORDERS,
    mv.GROSS_REVENUE_EUR
FROM MV_DAILY_CITY_REVENUE mv
JOIN CITIES c ON c.CITY_ID = mv.CITY_ID
ORDER BY mv.ORDER_DATE DESC, mv.GROSS_REVENUE_EUR DESC
LIMIT 16;

-- Inspect the Materialized View metadata: notice 'rows', 'bytes' > 0, and 'behind_by'
SHOW MATERIALIZED VIEWS LIKE 'MV_DAILY_CITY_REVENUE';

-- Need both precomputation AND partner row security? Combine them:
-- CREATE OR REPLACE SECURE MATERIALIZED VIEW SMV_... AS ...;


/* ============================================================================
   PART 4: RECURSIVE VIEW (Hierarchies & Trees)
   Great for category trees, org charts, and bill-of-materials hierarchies so
   analysts don't have to write recursive CTEs by hand.
   ============================================================================ */

-- Create SnowBite's parent/child menu category table (small lookup table)
CREATE OR REPLACE TABLE MENU_CATEGORIES (
    CATEGORY_ID         INT,
    PARENT_CATEGORY_ID  INT,
    CATEGORY_NAME       VARCHAR(50)
);

INSERT INTO MENU_CATEGORIES (CATEGORY_ID, PARENT_CATEGORY_ID, CATEGORY_NAME) VALUES
    -- Level 1 (Root categories)
    (1,  NULL, 'Food'),
    (2,  NULL, 'Drinks'),
    (3,  NULL, 'Desserts'),
    -- Level 2 (Subcategories)
    (10, 1,    'Burgers'),
    (11, 1,    'Pizza'),
    (12, 1,    'Sushi'),
    (20, 2,    'Soft Drinks'),
    (21, 2,    'Coffee & Tea'),
    (30, 3,    'Ice Cream'),
    -- Level 3 (Leaf categories)
    (101, 10,  'Smash Burgers'),
    (102, 10,  'Plant-Based Burgers'),
    (111, 11,  'Neapolitan Pizza'),
    (211, 21,  'Iced Matcha & Latte');

-- Create a RECURSIVE VIEW that builds the full hierarchy path & depth level:
CREATE OR REPLACE RECURSIVE VIEW V_MENU_CATEGORY_TREE (
    CATEGORY_ID,
    PARENT_CATEGORY_ID,
    CATEGORY_NAME,
    DEPTH_LEVEL,
    FULL_CATEGORY_PATH
) AS
    -- Anchor member: top-level categories
    SELECT
        CATEGORY_ID,
        PARENT_CATEGORY_ID,
        CATEGORY_NAME,
        1 AS DEPTH_LEVEL,
        CATEGORY_NAME::VARCHAR AS FULL_CATEGORY_PATH
    FROM MENU_CATEGORIES
    WHERE PARENT_CATEGORY_ID IS NULL

    UNION ALL

    -- Recursive member: join children to their parents
    SELECT
        child.CATEGORY_ID,
        child.PARENT_CATEGORY_ID,
        child.CATEGORY_NAME,
        parent.DEPTH_LEVEL + 1,
        parent.FULL_CATEGORY_PATH || '  ›  ' || child.CATEGORY_NAME
    FROM MENU_CATEGORIES child
    JOIN V_MENU_CATEGORY_TREE parent
      ON child.PARENT_CATEGORY_ID = parent.CATEGORY_ID
    WHERE parent.DEPTH_LEVEL < 10;

-- Query the hierarchy like a flat table:
SELECT
    CATEGORY_ID,
    DEPTH_LEVEL,
    CATEGORY_NAME,
    FULL_CATEGORY_PATH
FROM V_MENU_CATEGORY_TREE
ORDER BY FULL_CATEGORY_PATH;


/* ============================================================================
   PART 5: SEMANTIC VIEW (Business Metrics & Dimensions for BI / Cortex AI)
   Defines relationships, dimensions, and official business KPIs once in SQL
   so dashboards and Cortex Analyst never disagree on what "Revenue" means.
   ============================================================================ */

CREATE OR REPLACE SEMANTIC VIEW SEM_SNOWBITE_ANALYTICS
  TABLES (
    orders      AS SNOWBITE_DB.CORE.ORDERS      PRIMARY KEY (ORDER_ID),
    restaurants AS SNOWBITE_DB.CORE.RESTAURANTS PRIMARY KEY (RESTAURANT_ID),
    cities      AS SNOWBITE_DB.CORE.CITIES      PRIMARY KEY (CITY_ID)
  )
  RELATIONSHIPS (
    orders_to_restaurants AS orders (RESTAURANT_ID) REFERENCES restaurants,
    orders_to_cities      AS orders (CITY_ID)       REFERENCES cities
  )
  FACTS (
    orders.TOTAL_AMOUNT     AS orders.TOTAL_AMOUNT,
    orders.DELIVERY_MINUTES AS orders.DELIVERY_MINUTES
  )
  DIMENSIONS (
    orders.ORDER_DATE          AS orders.ORDER_DATE,
    orders.STATUS              AS orders.STATUS,
    orders.PAYMENT_METHOD      AS orders.PAYMENT_METHOD,
    restaurants.CUISINE        AS restaurants.CUISINE,
    cities.CITY_NAME           AS cities.CITY_NAME,
    cities.COUNTRY             AS cities.COUNTRY
  )
  METRICS (
    orders.TOTAL_ORDERS        AS COUNT(orders.ORDER_ID),
    orders.GROSS_REVENUE_EUR   AS SUM(orders.TOTAL_AMOUNT),
    orders.AVG_DELIVERY_MIN    AS AVG(orders.DELIVERY_MINUTES)
  )
  COMMENT = 'Official SnowBite semantic layer for BI and Cortex Analyst';

-- Query the Semantic View by asking for DIMENSIONS and METRICS (no manual JOINs needed!):
SELECT *
FROM SEMANTIC_VIEW(
    SEM_SNOWBITE_ANALYTICS
    DIMENSIONS cities.CITY_NAME, restaurants.CUISINE
    METRICS orders.TOTAL_ORDERS, orders.GROSS_REVENUE_EUR, orders.AVG_DELIVERY_MIN
)
ORDER BY GROSS_REVENUE_EUR DESC
LIMIT 15;

SHOW SEMANTIC VIEWS LIKE 'SEM_SNOWBITE_ANALYTICS';


/* ============================================================================
   ENGINEER'S CORNER:
   1. The Automatic Query Rewrite Myth (Always verify with EXPLAIN!)
   2. What happens when you try a JOIN inside a Materialized View
   3. Checking MV background maintenance credits
   ============================================================================ */

-- 1. THE AUTOMATIC QUERY REWRITE TRAP (ALWAYS VERIFY WITH EXPLAIN!):
-- Snowflake's optimizer CAN transparently rewrite base-table queries to use a
-- Materialized View — but it is a COST-BASED decision, NOT a guarantee!
-- Because our 20M synthetic ORDERS rows compress into just 16 micro-partitions,
-- watch what happens if we query FROM ORDERS and check EXPLAIN:
EXPLAIN
SELECT
    ORDER_DATE,
    CITY_ID,
    COUNT(*)          AS TOTAL_ORDERS,
    SUM(TOTAL_AMOUNT) AS GROSS_REVENUE_EUR,
    SUM(SUBTOTAL)     AS FOOD_SUBTOTAL_EUR
FROM ORDERS
WHERE STATUS = 'DELIVERED'
GROUP BY ORDER_DATE, CITY_ID;
-- Look at the plan: Filter + Aggregate + TableScan on SNOWBITE_DB.CORE.ORDERS
-- (hundreds of MB in bytesAssigned across 20M rows — it did NOT rewrite to the MV)!

-- Now run EXPLAIN pointing directly at MV_DAILY_CITY_REVENUE:
EXPLAIN
SELECT
    ORDER_DATE,
    CITY_ID,
    TOTAL_ORDERS,
    GROSS_REVENUE_EUR,
    FOOD_SUBTOTAL_EUR
FROM MV_DAILY_CITY_REVENUE;
-- Look at the plan now: a single 'Materialized View Scan' on MV_DAILY_CITY_REVENUE
-- (no Filter or Aggregate step, and bytesAssigned is only ~80 KB)!
-- Senior Engineer Rule: Never assume automatic rewrite kicked in — check EXPLAIN,
-- and point dashboards (or a Standard View) directly at the MV for guaranteed speed!

-- 2. THE SINGLE-TABLE LIMITATION OF MATERIALIZED VIEWS:
-- Uncomment and run this: it FAILS because MVs cannot contain JOINs!
/*
CREATE OR REPLACE MATERIALIZED VIEW MV_WILL_FAIL AS
SELECT c.CITY_NAME, COUNT(*) AS ORDERS
FROM ORDERS o
JOIN CITIES c ON c.CITY_ID = o.CITY_ID
GROUP BY c.CITY_NAME;
*/
-- How do you precompute a result that DOES join multiple tables?
--    That's Dynamic Tables in Lesson 4!

-- 3. MONITORING MATERIALIZED VIEW BACKGROUND REFRESH COSTS (last 12 hours):
-- Note: Initial MV creation runs on your active warehouse (SNOWBITE_WH).
-- This function logs background serverless maintenance AFTER base table (ORDERS) changes:
SELECT *
FROM TABLE(INFORMATION_SCHEMA.MATERIALIZED_VIEW_REFRESH_HISTORY());


/* ----------------------------------------------------------------------------
   Optional cleanup of Lesson 3 demo objects
   (keep them – the Lesson 7 capstone audits and queries these objects)
   ---------------------------------------------------------------------------- */
-- DROP SEMANTIC VIEW IF EXISTS SEM_SNOWBITE_ANALYTICS;
-- DROP VIEW IF EXISTS V_MENU_CATEGORY_TREE;
-- DROP TABLE IF EXISTS MENU_CATEGORIES;
-- DROP MATERIALIZED VIEW IF EXISTS MV_DAILY_CITY_REVENUE;
-- DROP VIEW IF EXISTS SV_PARTNER_ORDERS;
-- DROP TABLE IF EXISTS PARTNER_ROLE_MAP;
-- DROP VIEW IF EXISTS V_DELIVERED_ORDERS;