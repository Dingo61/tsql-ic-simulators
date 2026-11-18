import sys
from pathlib import Path
import streamlit as st
import plotly.graph_objects as go

# Add repository root to Python path so 'shared' can be imported cleanly
sys.path.append(str(Path(__file__).resolve().parent.parent))
from shared.db_connection import execute_stored_procedure

st.set_page_config(page_title="555 Timer T-SQL Simulator", layout="wide")
st.title("555 Timer IC Simulator (Powered by T-SQL)")

# --- Sidebar Controls ---
st.sidebar.header("Operating Mode")
mode = st.sidebar.radio("Select 555 Configuration", ["ASTABLE", "BISTABLE"])
vcc = st.sidebar.slider("Supply Voltage Vcc (V)", 3.0, 15.0, 5.0, 0.5)

# Mode-specific inputs
r1, r2, c_uf = 1000.0, 10000.0, 10.0
trigger_events, reset_events, pulse_width = "", "", 20.0

if mode == "ASTABLE":
    st.sidebar.header("RC Timing Network")
    r1 = st.sidebar.number_input("Resistor R1 (Ohms)", 100, 1000000, 1000, 100)
    r2 = st.sidebar.number_input("Resistor R2 (Ohms)", 100, 1000000, 10000, 500)
    c_uf = st.sidebar.number_input("Capacitor C (µF)", 0.1, 1000.0, 10.0, 0.5)

    c_farads = c_uf * 1e-6
    t_high = 0.693 * (r1 + r2) * c_farads
    t_low = 0.693 * r2 * c_farads
    freq = 1.0 / (t_high + t_low)
    duty_cycle = (t_high / (t_high + t_low)) * 100

    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Frequency", f"{freq:.2f} Hz")
    col2.metric("Duty Cycle", f"{duty_cycle:.1f} %")
    col3.metric("Time High (T1)", f"{t_high*1000:.1f} ms")
    col4.metric("Time Low (T2)", f"{t_low*1000:.1f} ms")

else:
    st.sidebar.header("Bistable Switch Events (Active-Low)")
    st.sidebar.caption("Enter comma-separated timestamps (ms) when buttons are pressed to GND.")
    trigger_events = st.sidebar.text_input("Pin 2 (Trigger / SET) Pulses (ms)", "100, 350")
    reset_events = st.sidebar.text_input("Pin 4 (Reset / CLEAR) Pulses (ms)", "220, 480")
    pulse_width = st.sidebar.slider("Button Press Duration (ms)", 5.0, 100.0, 25.0, 5.0)

    st.info(
        "**Bistable Operation:** Pulling **Pin 2 (Trigger)** to 0V latches Pin 3 HIGH. "
        "Pulling **Pin 4 (Reset)** to 0V latches Pin 3 LOW. If both are pressed simultaneously, Reset takes priority."
    )

st.sidebar.header("Simulation Resolution")
time_step = st.sidebar.slider("Time Step Δt (ms)", 0.5, 10.0, 1.0, 0.5)
total_steps = st.sidebar.slider("Total Steps", 100, 2000, 600, 100)


# --- Database Execution via Shared Helper ---
@st.cache_data(ttl=60)
def run_sql_simulation(params: dict):
    return execute_stored_procedure("dbo.Simulate555Timer", params)


sim_params = {
    "Mode": mode,
    "Vcc": vcc,
    "R1": r1,
    "R2": r2,
    "C_uF": c_uf,
    "TimeStep_ms": time_step,
    "TotalSteps": total_steps,
    "TriggerEvents_ms": trigger_events,
    "ResetEvents_ms": reset_events,
    "PulseWidth_ms": pulse_width,
}

df = run_sql_simulation(sim_params)

# --- Plotting ---
fig = go.Figure()

fig.add_trace(go.Scatter(
    x=df["Time_ms"], y=df["Output_V"],
    name="Pin 3: Output (V)",
    line=dict(color="#00CC96", width=3, shape="hv")
))

if mode == "ASTABLE":
    fig.add_trace(go.Scatter(
        x=df["Time_ms"], y=df["Capacitor_V"],
        name="Pins 2 & 6: Capacitor (V)",
        line=dict(color="#636EFA", width=2.5)
    ))
    fig.add_hline(y=(2/3)*vcc, line_dash="dash", line_color="red", annotation_text="2/3 Vcc (Threshold)")
    fig.add_hline(y=(1/3)*vcc, line_dash="dash", line_color="orange", annotation_text="1/3 Vcc (Trigger)")
else:
    fig.add_trace(go.Scatter(
        x=df["Time_ms"], y=df["Pin2_Trigger_V"],
        name="Pin 2: Trigger (Active-Low)",
        line=dict(color="#636EFA", width=2, dash="dot", shape="hv")
    ))
    fig.add_trace(go.Scatter(
        x=df["Time_ms"], y=df["Pin4_Reset_V"],
        name="Pin 4: Reset (Active-Low)",
        line=dict(color="#EF553B", width=2, dash="dash", shape="hv")
    ))

fig.update_layout(
    title=f"555 Timer Oscilloscope ({mode} Mode)",
    xaxis_title="Time (ms)",
    yaxis_title="Voltage (V)",
    hovermode="x unified",
    height=500
)

st.plotly_chart(fig, use_container_width=True)

with st.expander("View Raw T-SQL Simulation Data"):
    st.dataframe(df, use_container_width=True)
