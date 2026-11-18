import runpy
from pathlib import Path
import streamlit as st
from shared.db_connection import get_connection_string
import pyodbc

# Must be called first and only once in the unified launcher
st.set_page_config(
    page_title="T-SQL Classic IC Simulator Lab",
    page_icon="🔌",
    layout="wide",
    initial_sidebar_state="expanded",
)

ROOT_DIR = Path(__file__).resolve().parent

SIMULATORS = {
    "🏠 Lab Home & Setup Check": {
        "path": None,
        "category": "Overview",
        "proc": None,
        "summary": "Overview of the 6-part T-SQL hardware simulation series and live SQL Server health check.",
    },
    "01 · NE555 Precision Timer": {
        "path": ROOT_DIR / "01-ne555-timer" / "app.py",
        "category": "Mixed-Signal Timer",
        "proc": "dbo.Simulate555Timer",
        "summary": "Astable RC oscillator and Bistable SR flip-flop modeled with exponential decay in a recursive CTE.",
    },
    "02 · CD4017 Decade Counter": {
        "path": ROOT_DIR / "02-cd4017-decade-counter" / "app.py",
        "category": "Sequential Logic",
        "proc": "dbo.SimulateCD4017Counter",
        "summary": "10-stage Johnson counter chained to an NE555 clock using LAG() rising-edge detection.",
    },
    "03 · 74HC595 Shift Register": {
        "path": ROOT_DIR / "03-74hc595-shift-register" / "app.py",
        "category": "Serial-to-Parallel",
        "proc": "dbo.Simulate74HC595ShiftRegister",
        "summary": "8-bit SIPO dual-register state machine with bitwise shifting and NULL tri-state (Hi-Z) outputs.",
    },
    "04 · LM741 Operational Amplifier": {
        "path": ROOT_DIR / "04-lm741-op-amp" / "app.py",
        "category": "Analog Amplifier",
        "proc": "dbo.SimulateLM741OpAmp",
        "summary": "Continuous analog amplifier modeling supply-rail saturation clipping and 0.5 V/µs slew-rate distortion.",
    },
    "05 · 74LS181 4-Bit ALU": {
        "path": ROOT_DIR / "05-74ls181-4bit-alu" / "app.py",
        "category": "Combinational CPU",
        "proc": "dbo.Simulate74LS181ALU",
        "summary": "32-function vintage CPU ALU evaluating all 256 4-bit input pairs via a set-based CROSS JOIN.",
    },
    "06 · ADC0804 8-Bit SAR ADC": {
        "path": ROOT_DIR / "06-adc0804-sar-adc" / "app.py",
        "category": "Mixed-Signal Converter",
        "proc": "dbo.SimulateADC0804",
        "summary": "8-bit Successive Approximation binary search ADC with Sample-and-Hold and Nyquist aliasing detection.",
    },
}

# --- Top-Level Workbench Selector ---
st.sidebar.title("🔌 T-SQL IC Lab")
selected_chip = st.sidebar.selectbox(
    "Select Integrated Circuit",
    options=list(SIMULATORS.keys()),
)
st.sidebar.markdown("---")

meta = SIMULATORS[selected_chip]

if meta["path"] is None:
    # --- Landing / Health-Check Page ---
    st.title("Classic Integrated Circuits Simulated in T-SQL & Streamlit")
    st.markdown(
        "Welcome to the interactive **T-SQL Hardware Simulation Workbench**. "
        "Select any Integrated Circuit from the **sidebar dropdown** to load its T-SQL physics/logic engine and oscilloscope."
    )

    # Live SQL Server & Stored Procedure Verification
    st.subheader("SQL Server Connection & Stored Procedure Check")
    try:
        with pyodbc.connect(get_connection_string(), timeout=5) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT @@SERVERNAME, DB_NAME(), @@VERSION")
            srv_name, db_name, version_str = cursor.fetchone()
            st.success(f"Connected to SQL Server **`{srv_name}`** · Database: **`{db_name}`**")

            # Check which of the 6 stored procedures are deployed
            cursor.execute("""
                SELECT SCHEMA_NAME(schema_id) + '.' + name 
                FROM sys.objects 
                WHERE type = 'P'
            """)
            deployed_procs = {row[0] for row in cursor.fetchall()}

        cols = st.columns(3)
        ic_items = [k for k in SIMULATORS.keys() if SIMULATORS[k]["path"] is not None]

        for idx, title in enumerate(ic_items):
            info = SIMULATORS[title]
            is_ready = info["proc"] in deployed_procs
            status_badge = "✅ Deployed" if is_ready else "⚠️ Missing `schema.sql`"

            with cols[idx % 3]:
                st.markdown(
                    f"""
                    <div style="padding:14px; border-radius:8px; border:1px solid #444; background:#1E1E1E; margin-bottom:12px;">
                        <div style="font-size:12px; color:#AAA;">{info['category']} · {status_badge}</div>
                        <div style="font-weight:bold; font-size:16px; margin:4px 0;">{title}</div>
                        <div style="font-size:13px; color:#CCC; margin-bottom:8px;">{info['summary']}</div>
                        <code style="font-size:11px;">{info['proc']}</code>
                    </div>
                    """,
                    unsafe_allow_html=True,
                )

    except Exception as ex:
        st.error(f"Could not connect to SQL Server: `{ex}`")
        st.info("Check your `.env` file in the repository root and ensure SQL Server is running.")

else:
    # --- Dynamically Run the Selected Standalone IC App ---
    # Temporarily silence st.set_page_config inside child scripts so Streamlit doesn't raise a duplicate call error
    original_set_page_config = st.set_page_config
    st.set_page_config = lambda *args, **kwargs: None
    try:
        runpy.run_path(str(meta["path"]), run_name="__main__")
    finally:
        st.set_page_config = original_set_page_config
