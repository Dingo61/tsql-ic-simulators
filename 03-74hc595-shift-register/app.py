import sys
from pathlib import Path
import streamlit as st
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# Import shared database helper from repository root
sys.path.append(str(Path(__file__).resolve().parent.parent))
from shared.db_connection import execute_stored_procedure

st.set_page_config(page_title="74HC595 Shift Register Simulator", layout="wide")
st.title("74HC595 8-Bit Shift Register Simulator (Powered by T-SQL)")

# --- Sidebar Controls ---
st.sidebar.header("Serial Input Stream (Pin 14)")
raw_bits = st.sidebar.text_input("Binary Bit Stream (MSB shifted first)", "10110101")
bit_stream = "".join(c for c in raw_bits if c in ("0", "1")) or "10110101"
st.sidebar.caption(f"Active stream ({len(bit_stream)} bits, repeats continuously): `{bit_stream}`")

vcc = st.sidebar.slider("Supply Voltage Vcc (V)", 2.0, 6.0, 5.0, 0.5)
clk_freq = st.sidebar.slider("Shift Clock SHCP Frequency (Hz)", 2.0, 50.0, 10.0, 1.0)

st.sidebar.header("Storage Latch Mode (Pin 12)")
latch_mode = st.sidebar.radio("Latch Trigger (STCP)", ["AUTO_BYTE (Every 8 Clocks)", "MANUAL (Timestamp Pulses)"])
latch_code = "AUTO_BYTE" if "AUTO" in latch_mode else "MANUAL"
manual_latch = ""
if latch_code == "MANUAL":
    manual_latch = st.sidebar.text_input("Manual Latch Timestamps (ms)", "420, 820")

st.sidebar.header("Control Pins")
reset_events = st.sidebar.text_input("Pin 10: Master Reset (Active-Low) (ms)", "")
disable_events = st.sidebar.text_input("Pin 13: Output Disable / Hi-Z (ms)", "")
control_pulse = st.sidebar.slider("Control Pulse Width (ms)", 10.0, 150.0, 40.0, 10.0)

st.sidebar.header("Simulation Resolution")
time_step = st.sidebar.slider("Time Step Δt (ms)", 1.0, 10.0, 2.0, 1.0)
total_steps = st.sidebar.slider("Total Steps", 100, 2000, 500, 100)


# --- Execute T-SQL Simulation ---
@st.cache_data(ttl=60)
def run_74hc595(params: dict):
    return execute_stored_procedure("dbo.Simulate74HC595ShiftRegister", params)


sim_params = {
    "Vcc": vcc,
    "BitStream": bit_stream,
    "ClockFreq_Hz": clk_freq,
    "LatchMode": latch_code,
    "ManualLatch_ms": manual_latch,
    "ResetEvents_ms": reset_events,
    "DisableEvents_ms": disable_events,
    "ControlPulse_ms": control_pulse,
    "TimeStep_ms": time_step,
    "TotalSteps": total_steps,
}

df = run_74hc595(sim_params)

# --- Interactive Dual-Register Inspector ---
st.subheader("Interactive Dual-Register Inspector")
selected_step = st.slider(
    "Scrub Simulation Timeline (Step)",
    min_value=0,
    max_value=int(df["StepNum"].max()),
    value=min(160, int(df["StepNum"].max())),
    step=1,
)

row = df.iloc[selected_step]
shift_val = int(row["Internal_Shift_Dec"])
latch_val = int(row["Latched_Output_Dec"])
is_hiz = row["OE_Pin13_V"] > 0

col_left, col_right = st.columns(2)

with col_left:
    st.markdown(f"**Internal 8-Bit Shift Register** (`0x{shift_val:02X}` / `{shift_val}`)")
    s_cols = st.columns(8)
    for bit_idx in range(7, -1, -1):
        bit_on = (shift_val & (1 << bit_idx)) > 0
        bg = "#636EFA" if bit_on else "#262730"
        s_cols[7 - bit_idx].markdown(
            f"""
            <div style="text-align:center; padding:6px; border-radius:6px; background:{bg}; border:1px solid #444;">
                <div style="font-size:11px; color:#CCC;">B{bit_idx}</div>
                <div style="font-weight:bold; font-size:16px;">{1 if bit_on else 0}</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

with col_right:
    status_tag = "TRI-STATE (Hi-Z)" if is_hiz else f"0x{latch_val:02X} / {latch_val}"
    st.markdown(f"**Latched Parallel Output Pins (Q7–Q0)** (`{status_tag}`)")
    o_cols = st.columns(8)
    q_pins = [7, 6, 5, 4, 3, 2, 1, 15]  # Physical DIP-16 pins for Q7..Q0
    for idx, bit_idx in enumerate(range(7, -1, -1)):
        bit_on = (latch_val & (1 << bit_idx)) > 0
        if is_hiz:
            led_color, glow, label_val = "#555555", "none", "Z"
        else:
            led_color = "#00CC96" if bit_on else "#262730"
            glow = "0 0 12px #00CC96" if bit_on else "none"
            label_val = "1" if bit_on else "0"

        o_cols[idx].markdown(
            f"""
            <div style="text-align:center; padding:6px; border-radius:6px; background:#1E1E1E; border:1px solid #444;">
                <div style="width:20px; height:20px; margin:0 auto 4px auto; border-radius:50%;
                            background:{led_color}; box-shadow:{glow}; border:1px solid #666;"></div>
                <div style="font-weight:bold; font-size:12px;">Q{bit_idx} ({label_val})</div>
                <div style="font-size:10px; color:#888;">Pin {q_pins[idx]}</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

st.markdown("---")
m1, m2, m3, m4 = st.columns(4)
m1.metric("Time", f"{row['Time_ms']:.1f} ms")
m2.metric("Serial Data In (DS)", f"{row['DS_Pin14_V']:.1f} V")
m3.metric("Cascade Out (Q7' Pin 9)", f"{row['Q7_Prime_Pin9_V']:.1f} V")
m4.metric("Output Buffer (OE Pin 13)", "Hi-Z (Disabled)" if is_hiz else "Enabled (Active)")

# --- Logic Analyzer Timing Diagram ---
st.subheader("Logic Analyzer Timing Diagram")

channels = [
    ("DS_Pin14_V", "Pin 14: Serial DS", "#FFA15A"),
    ("SHCP_Pin11_V", "Pin 11: Shift Clk", "#00CC96"),
    ("STCP_Pin12_V", "Pin 12: Latch Clk", "#AB63FA"),
    ("MR_Pin10_V", "Pin 10: Reset (L)", "#EF553B"),
    ("OE_Pin13_V", "Pin 13: Out Dis (H)", "#FF6692"),
    ("Q7_Prime_Pin9_V", "Pin 9: Cascade Q7'", "#19D3F3"),
    ("Q0_V", "Q0 (Pin 15)", "#636EFA"),
    ("Q1_V", "Q1 (Pin 1)", "#636EFA"),
    ("Q2_V", "Q2 (Pin 2)", "#636EFA"),
    ("Q3_V", "Q3 (Pin 3)", "#636EFA"),
    ("Q4_V", "Q4 (Pin 4)", "#636EFA"),
    ("Q5_V", "Q5 (Pin 5)", "#636EFA"),
    ("Q6_V", "Q6 (Pin 6)", "#636EFA"),
    ("Q7_V", "Q7 (Pin 7)", "#636EFA"),
]

fig = make_subplots(rows=len(channels), cols=1, shared_xaxes=True, vertical_spacing=0.015)

for i, (col_name, label, color) in enumerate(channels, start=1):
    fig.add_trace(
        go.Scatter(
            x=df["Time_ms"],
            y=df[col_name],
            name=label,
            line=dict(color=color, width=2, shape="hv"),
            connectgaps=False,  # Leaves visible gaps during Tri-State (Hi-Z) periods
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

fig.add_vline(x=row["Time_ms"], line_width=1.5, line_dash="dash", line_color="white")

fig.update_layout(
    height=750,
    xaxis_title="Time (ms)",
    hovermode="x unified",
    margin=dict(l=120, r=20, t=20, b=40),
)

st.plotly_chart(fig, use_container_width=True)

with st.expander("View Raw T-SQL Simulation Data"):
    st.dataframe(df, use_container_width=True)
