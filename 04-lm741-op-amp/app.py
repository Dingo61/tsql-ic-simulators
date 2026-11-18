import sys
import math
from pathlib import Path
import streamlit as st
import plotly.graph_objects as go

# Import shared database helper from repository root
sys.path.append(str(Path(__file__).resolve().parent.parent))
from shared.db_connection import execute_stored_procedure

st.set_page_config(page_title="LM741 Op-Amp T-SQL Simulator", layout="wide")
st.title("LM741 Operational Amplifier Simulator (Powered by T-SQL)")

# --- Sidebar Controls ---
st.sidebar.header("Op-Amp Circuit Topology")
topology = st.sidebar.selectbox(
    "Configuration",
    ["NON_INVERTING", "INVERTING", "FOLLOWER", "COMPARATOR"],
)

vcc = st.sidebar.slider("Positive Rail +Vcc (V)", 5.0, 18.0, 15.0, 1.0)
vee = st.sidebar.slider("Negative Rail -Vee (V)", -18.0, -5.0, -15.0, 1.0)

rin, rf, vref = 1000.0, 4700.0, 0.0
if topology in ("NON_INVERTING", "INVERTING"):
    rin = st.sidebar.number_input("Input Resistor Rin (Ohms)", 100, 100000, 1000, 100)
    rf = st.sidebar.number_input("Feedback Resistor Rf (Ohms)", 100, 1000000, 4700, 500)
elif topology == "COMPARATOR":
    vref = st.sidebar.slider("Reference Voltage Vref (V)", -10.0, 10.0, 0.0, 0.5)

st.sidebar.header("Input Signal Generator")
waveform = st.sidebar.radio("Waveform", ["SINE", "TRIANGLE", "SQUARE"], horizontal=True)
vin_amp = st.sidebar.slider("Input Peak Amplitude (V)", 0.1, 10.0, 2.0, 0.1)
vin_offset = st.sidebar.slider("DC Offset (V)", -5.0, 5.0, 0.0, 0.5)
sig_freq = st.sidebar.slider("Signal Frequency (Hz)", 100, 50000, 2000, 100)

st.sidebar.header("LM741 Slew-Rate Physics")
enable_slew = st.sidebar.checkbox("Enable Slew-Rate Limiting", value=True)
slew_rate = st.sidebar.slider("Slew Rate (V/µs) [LM741 ≈ 0.5]", 0.1, 10.0, 0.5, 0.1)

st.sidebar.header("Oscilloscope Timebase")
time_step_us = st.sidebar.slider("Time Step Δt (µs)", 0.5, 20.0, 2.0, 0.5)
total_steps = st.sidebar.slider("Total Samples", 200, 2000, 800, 100)


# --- Execute T-SQL Simulation ---
@st.cache_data(ttl=60)
def run_lm741(params: dict):
    return execute_stored_procedure("dbo.SimulateLM741OpAmp", params)


sim_params = {
    "Topology": topology,
    "Vcc": vcc,
    "Vee": vee,
    "Rin_Ohms": rin,
    "Rf_Ohms": rf,
    "Vref_V": vref,
    "Waveform": waveform,
    "Vin_Amplitude_V": vin_amp,
    "Vin_Offset_V": vin_offset,
    "SignalFreq_Hz": sig_freq,
    "SlewRate_V_us": slew_rate,
    "EnableSlewLimit": 1 if enable_slew else 0,
    "TimeStep_us": time_step_us,
    "TotalSteps": total_steps,
}

df = run_lm741(sim_params)

# --- Engineering Metrics ---
if topology == "NON_INVERTING":
    gain = 1.0 + (rf / rin)
elif topology == "INVERTING":
    gain = -(rf / rin)
elif topology == "FOLLOWER":
    gain = 1.0
else:
    gain = float("inf")

peak_out = min(abs(gain) * vin_amp, vcc - 1.5) if gain != float("inf") else (vcc - 1.5)
# Full-Power Bandwidth: f_max = SlewRate / (2 * pi * V_peak)
fpbw_khz = (slew_rate * 1e6) / (2 * math.pi * max(peak_out, 0.1)) / 1000.0

clipped_pct = (df["Is_Clipped"].sum() / len(df)) * 100
slewed_pct = (df["Is_Slew_Limited"].sum() / len(df)) * 100

c1, c2, c3, c4 = st.columns(4)
c1.metric("Closed-Loop Gain (Av)", "Open-Loop" if topology == "COMPARATOR" else f"{gain:.2f} V/V")
c2.metric("Full-Power Bandwidth", f"{fpbw_khz:.1f} kHz")
c3.metric("Rail Clipping", f"{clipped_pct:.1f}% of samples")
c4.metric("Slew-Rate Distortion", f"{slewed_pct:.1f}% of samples")

if slewed_pct > 5.0:
    st.warning(
        f"**Slew-Rate Distortion Detected:** At {sig_freq:,} Hz and {peak_out:.1f}V peak output, "
        f"the required slope exceeds the LM741's **{slew_rate} V/µs** slew rate—turning sine peaks into triangular ramps!"
    )

# --- Oscilloscope Plot ---
fig = go.Figure()

# Input Signal Vin
fig.add_trace(go.Scatter(
    x=df["Time_us"], y=df["Vin_V"],
    name="Pin 2/3: Input Vin (V)",
    line=dict(color="#636EFA", width=2, dash="dot"),
))

# Ideal Output (No Slew Limit)
if enable_slew:
    fig.add_trace(go.Scatter(
        x=df["Time_us"], y=df["Vout_Ideal_V"],
        name="Ideal Output (Infinite Slew)",
        line=dict(color="#FFA15A", width=1.5, dash="dash"),
    ))

# Actual LM741 Output
fig.add_trace(go.Scatter(
    x=df["Time_us"], y=df["Vout_Actual_V"],
    name="Pin 6: LM741 Output Vout (V)",
    line=dict(color="#00CC96", width=3),
))

# Saturation Rails
fig.add_hline(y=vcc - 1.5, line_dash="dash", line_color="#EF553B", annotation_text=f"+Sat ({vcc-1.5:.1f}V)")
fig.add_hline(y=vee + 1.5, line_dash="dash", line_color="#EF553B", annotation_text=f"-Sat ({vee+1.5:.1f}V)")

if topology == "COMPARATOR":
    fig.add_hline(y=vref, line_dash="dot", line_color="white", annotation_text=f"Vref ({vref:.1f}V)")

fig.update_layout(
    title=f"LM741 Dual-Supply Oscilloscope ({topology.replace('_', ' ').title()})",
    xaxis_title="Time (µs)",
    yaxis_title="Voltage (V)",
    hovermode="x unified",
    height=520,
)

st.plotly_chart(fig, use_container_width=True)

with st.expander("View Raw T-SQL Simulation Data"):
    st.dataframe(df, use_container_width=True)
