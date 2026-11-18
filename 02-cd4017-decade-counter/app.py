import sys
from pathlib import Path
import streamlit as st
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# Import shared database helper from repository root
sys.path.append(str(Path(__file__).resolve().parent.parent))
from shared.db_connection import execute_stored_procedure

st.set_page_config(page_title="CD4017 Decade Counter Simulator", layout="wide")
st.title("CD4017 Decade Counter IC Simulator (Powered by T-SQL)")

# --- Sidebar Controls ---
st.sidebar.header("Clock Source (Pin 14)")
clock_source = st.sidebar.radio("Select Clock Driver", ["NE555 (Chained)", "Ideal Square Wave"])
src_code = "NE555" if "NE555" in clock_source else "SQUARE"
vcc = st.sidebar.slider("Supply Voltage Vcc (V)", 3.0, 15.0, 5.0, 0.5)

r1, r2, c_uf, clk_freq = 1000.0, 10000.0, 5.0, 10.0

if src_code == "NE555":
    st.sidebar.subheader("NE555 Astable Clock Parameters")
    r1 = st.sidebar.number_input("NE555 R1 (Ohms)", 100, 1000000, 1000, 100)
    r2 = st.sidebar.number_input("NE555 R2 (Ohms)", 100, 1000000, 10000, 500)
    c_uf = st.sidebar.number_input("NE555 C (µF)", 0.1, 1000.0, 5.0, 0.5)
    est_freq = 1.44 / ((r1 + 2 * r2) * (c_uf * 1e-6))
    st.sidebar.caption(f"Estimated NE555 Clock Frequency: **{est_freq:.2f} Hz**")
else:
    st.sidebar.subheader("Square Wave Generator")
    clk_freq = st.sidebar.slider("Clock Frequency (Hz)", 1.0, 50.0, 10.0, 1.0)

st.sidebar.header("Control Pins (Active-High)")
reset_events = st.sidebar.text_input("Pin 15: Master Reset Pulses (ms)", "320")
inhibit_events = st.sidebar.text_input("Pin 13: Clock Inhibit Pulses (ms)", "180")
control_pulse = st.sidebar.slider("Control Pulse Width (ms)", 5.0, 100.0, 30.0, 5.0)

st.sidebar.header("Simulation Resolution")
time_step = st.sidebar.slider("Time Step Δt (ms)", 0.5, 10.0, 1.0, 0.5)
total_steps = st.sidebar.slider("Total Steps", 100, 2000, 500, 100)


# --- Execute T-SQL Simulation ---
@st.cache_data(ttl=60)
def run_cd4017(params: dict):
    return execute_stored_procedure("dbo.SimulateCD4017Counter", params)


sim_params = {
    "ClockSource": src_code,
    "Vcc": vcc,
    "R1": r1,
    "R2": r2,
    "C_uF": c_uf,
    "ClockFreq_Hz": clk_freq,
    "ResetEvents_ms": reset_events,
    "InhibitEvents_ms": inhibit_events,
    "ControlPulse_ms": control_pulse,
    "TimeStep_ms": time_step,
    "TotalSteps": total_steps,
}

df = run_cd4017(sim_params)

# --- Interactive 10-LED Chaser Visualizer ---
st.subheader("Interactive 10-LED Decade Chaser")
selected_step = st.slider(
    "Scrub Simulation Timeline (Step)",
    min_value=0,
    max_value=int(df["StepNum"].max()),
    value=0,
    step=1,
)

row = df.iloc[selected_step]
active_pin = int(row["Active_Pin_Index"])

# Render 10 LED indicators across columns
led_cols = st.columns(10)
pin_numbers = [3, 2, 4, 7, 10, 1, 5, 6, 9, 11]  # Physical DIP-16 pin mapping for Q0..Q9

for idx, col in enumerate(led_cols):
    is_on = (idx == active_pin)
    led_color = "#FF4B4B" if is_on else "#262730"
    glow = "0 0 15px #FF4B4B" if is_on else "none"
    col.markdown(
        f"""
        <div style="text-align:center; padding:8px; border-radius:8px; background:#1E1E1E;">
            <div style="width:28px; height:28px; margin:0 auto 6px auto; border-radius:50%;
                        background:{led_color}; box-shadow:{glow}; border:2px solid #555;"></div>
            <div style="font-weight:bold; font-size:14px;">Q{idx}</div>
            <div style="font-size:11px; color:#888;">Pin {pin_numbers[idx]}</div>
        </div>
        """,
        unsafe_allow_html=True,
    )

m1, m2, m3, m4 = st.columns(4)
m1.metric("Current Time", f"{row['Time_ms']:.1f} ms")
m2.metric("Active Output", f"Q{active_pin} (Pin {pin_numbers[active_pin]})")
m3.metric("Carry Out (Pin 12)", f"{row['Carry_Out_V']:.1f} V")
m4.metric(
    "Control Status",
    "RESET" if row["Reset_Pin15_V"] > 0 else ("INHIBITED" if row["Inhibit_Pin13_V"] > 0 else "RUNNING"),
)

# --- Multi-Channel Logic Analyzer Plot ---
st.subheader("Logic Analyzer Timing Diagram")

channels = [
    ("Clock_In_V", "Pin 14: Clock In", "#00CC96"),
    ("Reset_Pin15_V", "Pin 15: Reset", "#EF553B"),
    ("Inhibit_Pin13_V", "Pin 13: Inhibit", "#FFA15A"),
    ("Q0_V", "Q0 (Pin 3)", "#636EFA"),
    ("Q1_V", "Q1 (Pin 2)", "#636EFA"),
    ("Q2_V", "Q2 (Pin 4)", "#636EFA"),
    ("Q3_V", "Q3 (Pin 7)", "#636EFA"),
    ("Q4_V", "Q4 (Pin 10)", "#636EFA"),
    ("Q5_V", "Q5 (Pin 1)", "#636EFA"),
    ("Q6_V", "Q6 (Pin 5)", "#636EFA"),
    ("Q7_V", "Q7 (Pin 6)", "#636EFA"),
    ("Q8_V", "Q8 (Pin 9)", "#636EFA"),
    ("Q9_V", "Q9 (Pin 11)", "#636EFA"),
    ("Carry_Out_V", "Pin 12: Carry Out", "#AB63FA"),
]

fig = make_subplots(
    rows=len(channels),
    cols=1,
    shared_xaxes=True,
    vertical_spacing=0.015,
)

for i, (col_name, label, color) in enumerate(channels, start=1):
    fig.add_trace(
        go.Scatter(
            x=df["Time_ms"],
            y=df[col_name],
            name=label,
            line=dict(color=color, width=2, shape="hv"),
            showlegend=False,
        ),
        row=i,
        col=1,
    )
    fig.update_yaxes(
        title_text=label,
        title_font=dict(size=10),
        range=[-0.5, vcc + 0.5],
        showticklabels=False,
        row=i,
        col=1,
    )

# Vertical marker synced with the LED scrubber slider
fig.add_vline(x=row["Time_ms"], line_width=1.5, line_dash="dash", line_color="white")

fig.update_layout(
    height=750,
    xaxis_title="Time (ms)",
    hovermode="x unified",
    margin=dict(l=110, r=20, t=20, b=40),
)

st.plotly_chart(fig, use_container_width=True)

with st.expander("View Raw T-SQL Simulation Data"):
    st.dataframe(df, use_container_width=True)
