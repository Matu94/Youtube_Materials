import streamlit as st
from snowflake.snowpark.context import get_active_session

st.title("E-Commerce Dashboard 📊")
st.write("This dashboard connects directly to our clean data view.")

# Get the active Snowflake session
session = get_active_session()

# Query the clean data
sql_query = """
    SELECT STAR_RATING, COUNT(*) as COUNT
    FROM ECOMMERCE_DB.RAW_DATA.CLEAN_REVIEWS
    GROUP BY STAR_RATING
    ORDER BY STAR_RATING DESC
"""

# Load data into a Pandas dataframe
data = session.sql(sql_query).to_pandas()

# Display the interactive Bar Chart
st.subheader("Reviews by Star Rating")
st.bar_chart(data=data, x="STAR_RATING", y="COUNT")
