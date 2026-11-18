import os
import pyodbc
import pandas as pd
import streamlit as st
from dotenv import load_dotenv

# Load environment variables from root .env file
load_dotenv()


def get_connection_string() -> str:
    """Builds a SQL Server ODBC connection string from environment variables."""
    driver = os.getenv("DB_DRIVER", "ODBC Driver 17 for SQL Server")
    server = os.getenv("DB_SERVER", "localhost")
    database = os.getenv("DB_NAME", "IC_Simulations")
    trusted = os.getenv("DB_TRUSTED_CONNECTION", "yes").lower() in ("yes", "true", "1")

    base_str = f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};TrustServerCertificate=yes;"

    if trusted:
        return base_str + "Trusted_Connection=yes;"

    user = os.getenv("DB_USER", "")
    password = os.getenv("DB_PASSWORD", "")
    return base_str + f"UID={user};PWD={password};"


def execute_stored_procedure(proc_name: str, params: dict) -> pd.DataFrame:
    """
    Executes a parameterized T-SQL stored procedure and returns a Pandas DataFrame.

    Args:
        proc_name: Fully qualified stored procedure name (e.g., 'dbo.Simulate555Timer')
        params: Dictionary mapping T-SQL parameter names (without '@') to Python values.
                Example: {'Mode': 'ASTABLE', 'Vcc': 5.0}
    """
    if params:
        param_placeholders = ", ".join([f"@{key}=?" for key in params.keys()])
        query = f"EXEC {proc_name} {param_placeholders}"
        values = list(params.values())
    else:
        query = f"EXEC {proc_name}"
        values = []

    conn_str = get_connection_string()

    try:
        with pyodbc.connect(conn_str, timeout=10) as conn:
            return pd.read_sql(query, conn, params=values)
    except pyodbc.Error as ex:
        st.error(f"**SQL Server Connection / Execution Error:**\n\n`{ex}`")
        st.info(
            "Verify that SQL Server is running, your `.env` credentials are correct, "
            "and you have executed `schema.sql` in your target database."
        )
        st.stop()
