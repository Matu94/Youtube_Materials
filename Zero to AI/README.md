<div align="center">

  <a href="https://www.youtube.com/@MatuData?sub_confirmation=1">
    <img src="https://img.shields.io/badge/YouTube-%40MatuData-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="YouTube @MatuData" height="42" />
    <img src="https://img.shields.io/badge/SUBSCRIBE-%F0%9F%94%94%20Don't%20Forget%20to%20Subscribe!-CC0000?style=for-the-badge" alt="Subscribe to @MatuData" height="42" />
  </a>

  <p><b>🎥 Watch the full tutorials on <a href="https://www.youtube.com/@MatuData">@MatuData</a> — and don't forget to subscribe! 🔔</b></p>

</div>

---

# Zero to AI in Snowflake 🚀

Welcome to the companion materials for the **Zero to AI** series. Below you'll find direct links to all the SQL scripts and supporting files for each step of the project.

## 📜 SQL Scripts & Course Files

- **01 – Getting Started**
  - [`01_Getting started/query.sql`](./01_Getting%20started/query.sql) — Initial query exploring Snowflake sample data.
- **02 – Data Ingestion**
  - [`02_Ingestion/queries.sql`](./02_Ingestion/queries.sql) — Setting up the database, schema, file format, stage, and ingesting raw e-commerce reviews (`COPY INTO`).
  - [`02_Ingestion/raw_ecom_reviews.csv`](./02_Ingestion/raw_ecom_reviews.csv) — Raw dataset used for ingestion.
- **03 – Data Transformation**
  - [`03_Transformation/queries.sql`](./03_Transformation/queries.sql) — Cleaning and standardizing the raw reviews using a Snowflake View (`CLEAN_REVIEWS`).
- **04 – Visualisation**
  - [`04_Visualisation/streamlitapp.py`](./04_Visualisation/streamlitapp.py) — Streamlit in Snowflake dashboard app.
- **05 – AI with Snowflake Cortex**
  - [`05_AI/query.sql`](./05_AI/query.sql) — Summarizing e-commerce review complaints using `SNOWFLAKE.CORTEX.AI_COMPLETE`.
