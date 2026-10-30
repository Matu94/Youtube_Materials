-- ====================================================================
-- YouTube : @MatuData (https://www.youtube.com/@MatuData)
-- 🔔 Don't forget to subscribe to the channel!
-- ====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;


-- Switch to our database and schema
USE DATABASE ECOMMERCE_DB;
USE SCHEMA RAW_DATA;

-- Step 1: Let's see the messy data first
SELECT * FROM RAW_REVIEWS LIMIT 10;

-- Step 2: Write the transformation logic and wrap it in a View
CREATE OR REPLACE VIEW CLEAN_REVIEWS AS
SELECT
    -- Rename ID column for clarity
    order_id AS ID,
    
    -- Handle missing order amounts
    COALESCE(order_amount, 0) AS ORDER_AMOUNT,
    
    -- Ensure the rating is handled (assume 3 as neutral default)
    COALESCE(rating, 3) AS STAR_RATING,
    
    -- Standardize the date format (it was ingested as VARCHAR)
    TO_DATE(order_date) AS REVIEW_DATE

FROM RAW_REVIEWS
WHERE order_id IS NOT NULL;

-- Step 3: Verify the clean view
SELECT * FROM CLEAN_REVIEWS LIMIT 10;
