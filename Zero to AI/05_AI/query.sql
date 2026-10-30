-- ====================================================================
-- YouTube : @MatuData (https://www.youtube.com/@MatuData)
-- 🔔 Don't forget to subscribe to the channel!
-- ====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

USE DATABASE ECOMMERCE_DB;
USE SCHEMA RAW_DATA;


SELECT 
    ID,
    REVIEW_TEXT,
    SNOWFLAKE.CORTEX.AI_COMPLETE(
    'llama3.1-8b',
    'Read this e-commerce review and summarize the main complaint in less than 5 words. If there is no complaint, write "Positive". Review: ' || REVIEW_TEXT
    ) AS AI_ANALISYS
FROM CLEAN_REVIEWS
WHERE STAR_RATING < 4;
