/* ============================================================================
   SnowBite – Course setup script
   Course : Snowflake Tables & Views – The Complete Guide
   Purpose: Creates the SnowBite food-delivery dataset used in every lesson.

   What you get (all synthetic, generated inside Snowflake – no downloads):
     CORE.CITIES        8 rows
     CORE.RESTAURANTS   1,000 rows
     CORE.CUSTOMERS     100,000 rows
     CORE.COURIERS      5,000 rows
     CORE.ORDERS        20,000,000 rows  (last ~2 years, growing business)

   Runtime: ~1–3 min. Cost: a few cents of credits.
   Re-runnable: yes (everything is CREATE OR REPLACE).

   Lesson-specific objects (staging tables, views, dynamic tables, S3 data,
   hybrid tables...) are created in each lesson's own script.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   1. Context: role, warehouse, database, schema
   ---------------------------------------------------------------------------- */
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS SNOWBITE_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60          -- seconds idle before suspending (saves credits)
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'SnowBite course warehouse';

USE WAREHOUSE SNOWBITE_WH;

CREATE DATABASE IF NOT EXISTS SNOWBITE_DB
    COMMENT = 'SnowBite food-delivery demo – Snowflake Tables & Views course';

CREATE SCHEMA IF NOT EXISTS SNOWBITE_DB.CORE
    COMMENT = 'Core business tables shared by all lessons';

USE SCHEMA SNOWBITE_DB.CORE;


/* ----------------------------------------------------------------------------
   2. CITIES – small lookup table (lat/lon reused for GPS pings in Lesson 5)
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE CITIES (
    CITY_ID    INT          NOT NULL,
    CITY_NAME  VARCHAR(50)  NOT NULL,
    COUNTRY    VARCHAR(50)  NOT NULL,
    LAT        FLOAT,
    LON        FLOAT
);

INSERT INTO CITIES (CITY_ID, CITY_NAME, COUNTRY, LAT, LON) VALUES
    (1, 'Zurich',    'Switzerland',    47.3769,  8.5417),
    (2, 'Berlin',    'Germany',        52.5200, 13.4050),
    (3, 'Vienna',    'Austria',        48.2082, 16.3738),
    (4, 'Budapest',  'Hungary',        47.4979, 19.0402),
    (5, 'Prague',    'Czech Republic', 50.0755, 14.4378),
    (6, 'Amsterdam', 'Netherlands',    52.3676,  4.9041),
    (7, 'Milan',     'Italy',          45.4642,  9.1900),
    (8, 'Paris',     'France',         48.8566,  2.3522);


/* ----------------------------------------------------------------------------
   3. RESTAURANTS – 1,000 rows
      Cities are weighted (Zurich is SnowBite's biggest market).
      ROW_NUMBER() instead of SEQ4() guarantees gap-free IDs 1..1000.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE RESTAURANTS AS
WITH gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4())                                   AS RESTAURANT_ID,
        -- 21-element weighted array: city 1 = 4x, cities 2/3/6 = 3x, others = 2x
        GET(ARRAY_CONSTRUCT(1,1,1,1,2,2,2,3,3,4,4,5,5,6,6,7,7,8,8,3,6),
            UNIFORM(0, 20, RANDOM()))::INT                                    AS CITY_ID,
        UNIFORM(0, 11, RANDOM())                                              AS PREFIX_IDX,
        UNIFORM(0, 11, RANDOM())                                              AS CUISINE_IDX,
        UNIFORM(0, 7,  RANDOM())                                              AS NOUN_IDX
    FROM TABLE(GENERATOR(ROWCOUNT => 1000))
),
named AS (
    SELECT
        g.RESTAURANT_ID,
        g.CITY_ID,
        GET(ARRAY_CONSTRUCT('Golden','Little','Urban','Happy','Royal','Green',
                            'Spicy','Lucky','Blue','Rustic','Hungry','Sunny'),
            g.PREFIX_IDX)::VARCHAR                                            AS PREFIX,
        GET(ARRAY_CONSTRUCT('Pizza','Burger','Sushi','Thai','Indian','Mexican',
                            'Vegan','Kebab','Chinese','Italian','Poke','Breakfast'),
            g.CUISINE_IDX)::VARCHAR                                           AS CUISINE,
        GET(ARRAY_CONSTRUCT('Kitchen','Bistro','Grill','House','Corner',
                            'Garden','Express','Spot'),
            g.NOUN_IDX)::VARCHAR                                              AS NOUN
    FROM gen g
)
SELECT
    n.RESTAURANT_ID::INT                                                      AS RESTAURANT_ID,
    (n.PREFIX || ' ' || n.CUISINE || ' ' || n.NOUN)::VARCHAR(100)             AS RESTAURANT_NAME,
    n.CUISINE::VARCHAR(30)                                                    AS CUISINE,
    n.CITY_ID::INT                                                            AS CITY_ID,
    c.CITY_NAME                                                               AS CITY_NAME,
    ROUND(c.LAT + UNIFORM(-0.04::FLOAT, 0.04::FLOAT, RANDOM()), 6)            AS LAT,
    ROUND(c.LON + UNIFORM(-0.06::FLOAT, 0.06::FLOAT, RANDOM()), 6)            AS LON,
    ROUND(UNIFORM(3.2::FLOAT, 4.9::FLOAT, RANDOM()), 1)::NUMBER(2,1)          AS AVG_RATING,
    DATEADD(DAY, -UNIFORM(800, 2500, RANDOM()), CURRENT_DATE())               AS ONBOARDED_DATE,
    (UNIFORM(1, 100, RANDOM()) <= 95)                                         AS IS_ACTIVE
FROM named n
JOIN CITIES c ON c.CITY_ID = n.CITY_ID;


/* ----------------------------------------------------------------------------
   4. CUSTOMERS – 100,000 rows
      12,500 customers per city: CITY_ID = FLOOR((CUSTOMER_ID - 1) / 12500) + 1
      (lets ORDERS pick a customer from the restaurant's city)
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE CUSTOMERS AS
WITH gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4())                                   AS CUSTOMER_ID,
        GET(ARRAY_CONSTRUCT('Anna','Ben','Clara','David','Emma','Felix','Greta',
                            'Hugo','Ines','Jonas','Lena','Marco','Nina','Oscar',
                            'Paula','Quentin','Rita','Sam','Tina','Viktor'),
            UNIFORM(0, 19, RANDOM()))::VARCHAR                                AS FIRST_NAME,
        GET(ARRAY_CONSTRUCT('Muller','Schmidt','Nagy','Rossi','Novak','Bauer',
                            'Dubois','Jansen','Kovacs','Fischer','Weber','Bianchi',
                            'Horvath','Martin','Wagner','Bakker','Moreau','Ricci',
                            'Svoboda','Huber'),
            UNIFORM(0, 19, RANDOM()))::VARCHAR                                AS LAST_NAME
    FROM TABLE(GENERATOR(ROWCOUNT => 100000))
)
SELECT
    g.CUSTOMER_ID::INT                                                        AS CUSTOMER_ID,
    g.FIRST_NAME::VARCHAR(50)                                                 AS FIRST_NAME,
    g.LAST_NAME::VARCHAR(50)                                                  AS LAST_NAME,
    LOWER(g.FIRST_NAME || '.' || g.LAST_NAME || g.CUSTOMER_ID
          || '@example.com')::VARCHAR(120)                                    AS EMAIL,
    (FLOOR((g.CUSTOMER_ID - 1) / 12500) + 1)::INT                             AS CITY_ID,
    DATEADD(DAY, -UNIFORM(1, 1100, RANDOM()), CURRENT_DATE())                 AS SIGNUP_DATE,
    (UNIFORM(1, 100, RANDOM()) <= 15)                                         AS IS_PREMIUM
FROM gen g;


/* ----------------------------------------------------------------------------
   5. COURIERS – 5,000 rows
      625 couriers per city: CITY_ID = FLOOR((COURIER_ID - 1) / 625) + 1
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE COURIERS AS
WITH gen AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4())                                   AS COURIER_ID,
        UNIFORM(1, 100, RANDOM())                                             AS VEHICLE_ROLL
    FROM TABLE(GENERATOR(ROWCOUNT => 5000))
)
SELECT
    g.COURIER_ID::INT                                                         AS COURIER_ID,
    ('Courier #' || LPAD(g.COURIER_ID, 4, '0'))::VARCHAR(30)                  AS COURIER_NAME,
    (FLOOR((g.COURIER_ID - 1) / 625) + 1)::INT                                AS CITY_ID,
    (CASE
        WHEN g.VEHICLE_ROLL <= 35 THEN 'BIKE'
        WHEN g.VEHICLE_ROLL <= 75 THEN 'E_BIKE'
        WHEN g.VEHICLE_ROLL <= 90 THEN 'SCOOTER'
        ELSE 'CAR'
     END)::VARCHAR(20)                                                        AS VEHICLE_TYPE,
    DATEADD(DAY, -UNIFORM(30, 1000, RANDOM()), CURRENT_DATE())                AS HIRED_DATE
FROM gen g;


/* ----------------------------------------------------------------------------
   6. ORDERS – 20,000,000 rows (the big fact table)

   Realism built in:
     - Business growth: more orders in recent months (sqrt-skewed day offset)
     - Lunch & dinner peaks (weighted hour array)
     - Customer and courier always from the restaurant's city
     - 94% delivered / 4% cancelled / 2% refunded
     - ~45% of delivered orders get a rating, skewed positive
     - Data covers yesterday back ~2 years (no "today" rows – Lesson 4 inserts those)

   Lesson 1 teaser: the final ORDER BY ORDER_TS writes rows in time order,
   so micro-partitions end up naturally clustered by date → great pruning
   on date filters, almost none on CUSTOMER_ID filters.

   Temporarily scaling up the warehouse makes this ~1 min instead of several.
   ---------------------------------------------------------------------------- */
ALTER WAREHOUSE SNOWBITE_WH SET WAREHOUSE_SIZE = 'MEDIUM';

CREATE OR REPLACE TABLE ORDERS AS
WITH gen AS (
    SELECT
        UNIFORM(1, 1000, RANDOM())                                            AS RESTAURANT_ID,
        -- 0..730 days ago, skewed towards recent dates (growing business)
        FLOOR(730 * (1 - SQRT(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()))))        AS DAY_OFFSET,
        -- 27-element weighted array: peaks at 12:00 and 19:00
        GET(ARRAY_CONSTRUCT(10,11,11,12,12,12,12,13,13,13,14,15,16,17,
                            18,18,19,19,19,19,20,20,20,21,21,22,23),
            UNIFORM(0, 26, RANDOM()))::INT                                    AS ORDER_HOUR,
        UNIFORM(0, 3599, RANDOM())                                            AS SECOND_IN_HOUR,
        UNIFORM(1, 12500, RANDOM())                                           AS CUSTOMER_SLOT,
        UNIFORM(1, 625, RANDOM())                                             AS COURIER_SLOT,
        UNIFORM(1, 6, RANDOM())                                               AS ITEMS_COUNT,
        UNIFORM(7.5::FLOAT, 24::FLOAT, RANDOM())                              AS AVG_ITEM_PRICE,
        UNIFORM(0, 3, RANDOM())                                               AS FEE_IDX,
        UNIFORM(0.5::FLOAT, 6::FLOAT, RANDOM())                               AS TIP_RAW,
        UNIFORM(12, 55, RANDOM())                                             AS DELIVERY_MINUTES_RAW,
        UNIFORM(1, 100, RANDOM())                                             AS STATUS_ROLL,
        UNIFORM(1, 100, RANDOM())                                             AS PAYMENT_ROLL,
        UNIFORM(1, 100, RANDOM())                                             AS TIP_ROLL,
        UNIFORM(1, 100, RANDOM())                                             AS RATING_ROLL
    FROM TABLE(GENERATOR(ROWCOUNT => 20000000))   -- change to scale the dataset
),
shaped AS (
    SELECT
        DATEADD(SECOND,
                g.ORDER_HOUR * 3600 + g.SECOND_IN_HOUR,
                DATEADD(DAY, -(g.DAY_OFFSET + 1), CURRENT_DATE())::TIMESTAMP_NTZ) AS ORDER_TS,
        (r.CITY_ID - 1) * 12500 + g.CUSTOMER_SLOT                             AS CUSTOMER_ID,
        g.RESTAURANT_ID,
        (r.CITY_ID - 1) * 625 + g.COURIER_SLOT                                AS COURIER_ID,
        r.CITY_ID,
        g.ITEMS_COUNT,
        ROUND(g.ITEMS_COUNT * g.AVG_ITEM_PRICE, 2)                            AS SUBTOTAL,
        GET(ARRAY_CONSTRUCT(0, 1.99, 2.99, 3.99), g.FEE_IDX)::NUMBER(6,2)     AS DELIVERY_FEE,
        IFF(g.TIP_ROLL <= 40, 0, ROUND(g.TIP_RAW, 2))                         AS TIP,
        CASE
            WHEN g.PAYMENT_ROLL <= 55 THEN 'CARD'
            WHEN g.PAYMENT_ROLL <= 85 THEN 'MOBILE_WALLET'
            WHEN g.PAYMENT_ROLL <= 95 THEN 'CASH'
            ELSE 'VOUCHER'
        END                                                                   AS PAYMENT_METHOD,
        CASE
            WHEN g.STATUS_ROLL <= 94 THEN 'DELIVERED'
            WHEN g.STATUS_ROLL <= 98 THEN 'CANCELLED'
            ELSE 'REFUNDED'
        END                                                                   AS STATUS,
        g.DELIVERY_MINUTES_RAW
            + GET(ARRAY_CONSTRUCT(-4, 2, -2, 1, -1, -5, 4, 6), r.CITY_ID - 1)::INT AS DELIVERY_MINUTES_RAW,   -- city speed offset (Amsterdam/Zurich fastest, Milan/Paris slowest)
        g.RATING_ROLL
    FROM gen g
    JOIN RESTAURANTS r ON r.RESTAURANT_ID = g.RESTAURANT_ID
)
SELECT
    ROW_NUMBER() OVER (ORDER BY s.ORDER_TS)::NUMBER(12,0)                     AS ORDER_ID,
    s.ORDER_TS                                                                AS ORDER_TS,
    s.ORDER_TS::DATE                                                          AS ORDER_DATE,
    s.CUSTOMER_ID::INT                                                        AS CUSTOMER_ID,
    s.RESTAURANT_ID::INT                                                      AS RESTAURANT_ID,
    s.COURIER_ID::INT                                                         AS COURIER_ID,
    s.CITY_ID::INT                                                            AS CITY_ID,
    s.ITEMS_COUNT::INT                                                        AS ITEMS_COUNT,
    s.SUBTOTAL::NUMBER(10,2)                                                  AS SUBTOTAL,
    s.DELIVERY_FEE::NUMBER(10,2)                                              AS DELIVERY_FEE,
    s.TIP::NUMBER(10,2)                                                       AS TIP,
    (s.SUBTOTAL + s.DELIVERY_FEE + s.TIP)::NUMBER(10,2)                       AS TOTAL_AMOUNT,   -- EUR
    s.PAYMENT_METHOD::VARCHAR(20)                                             AS PAYMENT_METHOD,
    s.STATUS::VARCHAR(20)                                                     AS STATUS,
    IFF(s.STATUS = 'CANCELLED', NULL, s.DELIVERY_MINUTES_RAW)::INT            AS DELIVERY_MINUTES,
    (CASE
        WHEN s.STATUS <> 'DELIVERED' THEN NULL
        WHEN s.RATING_ROLL <= 55     THEN NULL   -- most people don't rate
        WHEN s.RATING_ROLL <= 59     THEN 1
        WHEN s.RATING_ROLL <= 64     THEN 2
        WHEN s.RATING_ROLL <= 74     THEN 3
        WHEN s.RATING_ROLL <= 88     THEN 4
        ELSE 5
     END)::INT                                                                AS CUSTOMER_RATING
FROM shaped s
ORDER BY s.ORDER_TS;

ALTER WAREHOUSE SNOWBITE_WH SET WAREHOUSE_SIZE = 'XSMALL';


/* ----------------------------------------------------------------------------
   7. Sanity checks
   ---------------------------------------------------------------------------- */
-- Row counts
SELECT 'CITIES'      AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM CITIES      UNION ALL
SELECT 'RESTAURANTS',               COUNT(*)              FROM RESTAURANTS UNION ALL
SELECT 'CUSTOMERS',                 COUNT(*)              FROM CUSTOMERS   UNION ALL
SELECT 'COURIERS',                  COUNT(*)              FROM COURIERS    UNION ALL
SELECT 'ORDERS',                    COUNT(*)              FROM ORDERS;

-- Date range & growth: monthly order volume should trend upwards
SELECT DATE_TRUNC('MONTH', ORDER_DATE) AS MONTH, COUNT(*) AS ORDERS
FROM ORDERS
GROUP BY 1
ORDER BY 1;

-- Lunch & dinner peaks
SELECT HOUR(ORDER_TS) AS ORDER_HOUR, COUNT(*) AS ORDERS
FROM ORDERS
GROUP BY 1
ORDER BY 1;

-- Orders & revenue per city (Zurich should lead)
SELECT c.CITY_NAME,
       COUNT(*)                     AS ORDERS,
       ROUND(SUM(o.TOTAL_AMOUNT))   AS REVENUE_EUR,
       ROUND(AVG(o.DELIVERY_MINUTES), 1) AS AVG_DELIVERY_MIN
FROM ORDERS o
JOIN CITIES c ON c.CITY_ID = o.CITY_ID
GROUP BY 1
ORDER BY ORDERS DESC;

-- Consistency check: customer & courier must be in the restaurant's city (expect 0)
SELECT COUNT(*) AS CITY_MISMATCHES
FROM ORDERS o
JOIN CUSTOMERS cu ON cu.CUSTOMER_ID = o.CUSTOMER_ID
JOIN COURIERS  co ON co.COURIER_ID  = o.COURIER_ID
WHERE cu.CITY_ID <> o.CITY_ID
   OR co.CITY_ID <> o.CITY_ID;

-- Peek at the data
SELECT * FROM ORDERS ORDER BY ORDER_TS DESC LIMIT 20;


/* ----------------------------------------------------------------------------
   8. Teardown (run only when you're done with the whole course)
   ---------------------------------------------------------------------------- */
-- DROP DATABASE IF EXISTS SNOWBITE_DB;
-- DROP WAREHOUSE IF EXISTS SNOWBITE_WH;
