-- ====================================================================
-- YouTube : @MatuData (https://www.youtube.com/@MatuData)
-- 🔔 Don't forget to subscribe to the channel!
-- ====================================================================
-- ZERO TO PIPELINE: VIDEO 2 - DATA INGESTION
-- Purpose: Ingest raw E-commerce sales & reviews CSV into Snowflake
-- ====================================================================

-- Step 1: Set up the Worksheet Context (Role & Compute Warehouse)
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- Step 2: Create our Project Database and Ingestion Schema
CREATE DATABASE IF NOT EXISTS ECOMMERCE_DB;
USE DATABASE ECOMMERCE_DB;

CREATE SCHEMA IF NOT EXISTS RAW_DATA;
USE SCHEMA RAW_DATA;

-- Step 3: Create the Destination Raw Table
-- Notice: We use VARCHAR for date and flexible types to accept raw incoming data
CREATE OR REPLACE TABLE RAW_REVIEWS (
    order_id         VARCHAR(50),
    customer_id      VARCHAR(50),
    product_category VARCHAR(100),
    order_date       VARCHAR(50),
    order_amount     FLOAT,
    rating           NUMBER(38,0),
    review_text      VARCHAR(2000),
    country          VARCHAR(50)
);

-- Step 4: Create a Reusable File Format for CSVs
CREATE OR REPLACE FILE FORMAT CSV_WITH_HEADER
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null');

-- Step 5: Create an Internal Named Stage to hold raw files
CREATE OR REPLACE STAGE RAW_STAGE
    FILE_FORMAT = CSV_WITH_HEADER;

-- Step 6: Verify Stage Contents (After uploading raw_ecom_reviews.csv via Snowsight UI or SnowSQL)
LIST @RAW_STAGE;

-- Step 7: The Core Ingestion Command (COPY INTO)
COPY INTO RAW_REVIEWS
FROM @RAW_STAGE/raw_ecom_reviews.csv
FILE_FORMAT = (FORMAT_NAME = 'CSV_WITH_HEADER')
ON_ERROR = 'CONTINUE';

-- Step 8: Verify Ingestion & Inspect Raw Data
SELECT COUNT(*) AS total_records_ingested FROM RAW_REVIEWS;

SELECT * 
FROM RAW_REVIEWS;

-- Step 9: Quick Sanity Check: Identify Messy Data (To be cleaned in Video 3)
-- Notice inconsistent date formats, null order amounts, and missing ratings
SELECT 
    order_id,
    order_date,
    order_amount,
    rating,
    review_text
FROM RAW_REVIEWS
WHERE order_amount IS NULL 
   OR rating IS NULL
   OR order_date LIKE '%/%';
