import sys
from pathlib import Path
import streamlit as st
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# Import shared database helper from repository root
sys.path.append(str(Path(__file__).resolve().parent.parent))
from shared.db_connection import execute_stored_procedure

st.set_page_config(page_title="ADC0804 8-Bit SAR ADC Simulator", layout="wide")
st.title("ADC0804 8-Bit Successive Approximation ADC (Powered by T-SQL)")

# --- Sidebar Controls ---
st.sidebar.header("Reference & Sampling Clock")
vcc = st.sidebar.slider("Reference / Supply Vcc (V)", 2.5, 5.5, 5.0, 0.5)
sample_rate = st.sidebar.slider("Sampling Rate (Samples/sec)", 100, 5000, 1000, 100)
total_samples = st.sidebar.slider("Conversions to Capture", 10, 100, 35, 5)

st.sidebar.header("Analog Input Signal (Pin 6: Vin+)")
waveform = st.sidebar.radio("Input Waveform", ["SINE", "TRIANGLE", "RAMP"], horizontal=True)
sig_freq = st.sidebar.slider("Input Signal Frequency (Hz)", 10, 1000, 50, 10)
vin_amp = st.sidebar.slider("Peak Amplitude (V)", 0.2, 2.5, 2.2, 0.1)
vin_offset = st.sidebar.slider("DC Offset (V)", 0.0, 5.0, 2.5, 0.1)


# --- Execute T-SQL Simulation ---
@st.cache_data(ttl=60)
def run_adc0804(params: dict):
    return execute_stored_procedure("dbo.SimulateADC0804", params)


sim_params = {
    "Vcc": vcc,
    "Waveform": waveform,
    "Vin_Amplitude_V": vin_amp,
    "Vin_Offset_V": vin_offset,
    "SignalFreq_Hz": sig_freq,
    "SampleRate_Hz": sample_rate,
    "TotalSamples": total_samples,
}

df = run_adc0804(sim_params)

# --- Nyquist & Resolution Metrics ---
lsb_mv = (vcc / 256.0) * 1000.0
nyquist_hz = sample_rate / 2.0
rms_quant_err_mv = df[df["BitStep"] == 7]["Quantization_Error_V"].abs().mean() * 1000.0

m1, m2, m3, m4 = st.columns(4)
m1.metric("Resolution (1 LSB)", f"{lsb_mv:.2f} mV", "8-Bit (256 levels)")
m2.metric("Nyquist Limit (fs / 2)", f"{nyquist_hz:.0f} Hz")
m3.metric("Mean Quantization Error", f"{rms_quant_err_mv:.2f} mV")
m4.metric("Internal SAR Clock", f"{(sample_rate * 8) / 1000:.1f} kHz")

if sig_freq >= nyquist_hz:
    st.error(
        f"**Nyquist Aliasing Warning:** Input frequency ({sig_freq} Hz) meets or exceeds the Nyquist limit "
        f"({nyquist_hz:.0f} Hz). Increase the sampling rate or lower the signal frequency to avoid aliasing!"
    )

# --- Chart 1: Analog Input vs. Reconstructed Digital Staircase ---
st.subheader("1. Analog Input vs. Reconstructed Digital Output Staircase")

fig_main = make_subplots(
    rows=2,
    cols=1,
    shared_xaxes=True,
    vertical_spacing=0.08,
    row_heights=[0.75, 0.25],
)

# Continuous Analog Signal
fig_main.add_trace(
    go.Scatter(
        x=df["Time_ms"],
        y=df["Vin_Analog_V"],
        name="Pin 6: Analog Vin (V)",
        line=dict(color="#636EFA", width=2),
    ),
    row=1,
    col=1,
)

# Reconstructed Digital Staircase (Latched at end of each conversion)
fig_main.add_trace(
    go.Scatter(
        x=df["Time_ms"],
        y=df["Reconstructed_V"],
        name="ADC Reconstructed Staircase (V)",
        line=dict(color="#00CC96", width=2.5, shape="hv"),
    ),
    row=1,
    col=1,
)

# Active-Low Interrupt Pin (INTR / Pin 5) pulsing LOW on conversion complete
fig_main.add_trace(
    go.Scatter(
        x=df["Time_ms"],
        y=df["INTR_Pin5_V"],
        name="Pin 5: INTR (End of Conversion)",
        line=dict(color="#FFA15A", width=1.8, shape="hv"),
    ),
    row=2,
    col=1,
)

fig_main.update_yaxes(title_text="Voltage (V)", row=1, col=1)
fig_main.update_yaxes(title_text="INTR (V)", range=[-0.5, vcc + 0.5], row=2, col=1)
fig_main.update_xaxes(title_text="Time (ms)", row=2, col=1)
fig_main.update_layout(height=480, hovermode="x unified")

st.plotly_chart(fig_main, use_container_width=True)

# --- Chart 2: SAR 8-Step Binary Search Microscope ---
st.subheader("2. Inside a Single Conversion: 8-Step SAR Binary Search Microscope")

inspect_idx = st.slider(
    "Select Conversion Sample Index to Inspect",
    min_value=0,
    max_value=int(df["SampleIdx"].max()),
    value=min(3, int(df["SampleIdx"].max())),
    step=1,
)

sample_df = df[df["SampleIdx"] == inspect_idx].copy()
final_row = sample_df.iloc[-1]
final_code = int(final_row["Output_Byte_Dec"])

col_chart, col_bits = st.columns([2, 1])

with col_chart:
    fig_sar = go.Figure()

    # Held Analog Voltage Line
    fig_sar.add_hline(
        y=float(final_row["Vin_SampleHold_V"]),
        line_dash="dash",
        line_color="#636EFA",
        annotation_text=f"Sample & Hold Vin = {final_row['Vin_SampleHold_V']:.3f} V",
    )

    # Trial DAC Voltage steps
    fig_sar.add_trace(
        go.Scatter(
            x=[f"Bit {int(b)}" for b in sample_df["Testing_Bit"]],
            y=sample_df["Internal_DAC_V"],
            mode="lines+markers",
            name="Internal R-2R DAC Trial Voltage (V)",
            line=dict(color="#FF4B4B", width=3, shape="hv"),
            marker=dict(size=10),
        )
    )

    fig_sar.update_layout(
        title=f"SAR Binary Search Convergence (Sample #{inspect_idx} → Code {final_code} / 0x{final_code:02X})",
        xaxis_title="Successive Approximation Clock Step (MSB → LSB)",
        yaxis_title="Voltage (V)",
        yaxis=dict(range=[0, vcc + 0.3]),
        height=380,
    )
    st.plotly_chart(fig_sar, use_container_width=True)

with col_bits:
    st.markdown(f"**Latched Data Bus (`DB7–DB0`)**")
    st.markdown(f"Decimal: **`{final_code}`** | Hex: **`0x{final_code:02X}`** | Binary: **`{final_code:08b}`**")
    st.markdown(f"Reconstructed: **`{final_row['Reconstructed_V']:.4f} V`** (Error: `{final_row['Quantization_Error_V']*1000:+.2f} mV`)")

    # Render 8 Output Pins DB7..DB0
    b_cols = st.columns(8)
    for idx, bit_pos in enumerate(range(7, -1, -1)):
        bit_val = int(final_row[f"DB{bit_pos}"])
        bg = "#00CC96" if bit_val == 1 else "#262730"
        b_cols[idx].markdown(
            f"""
            <div style="text-align:center; padding:4px; border-radius:4px; background:{bg}; border:1px solid #555;">
                <div style="font-size:10px; color:#DDD;">DB{bit_pos}</div>
                <div style="font-weight:bold; font-size:14px;">{bit_val}</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

    st.markdown("**Step-by-Step Comparator Decisions:**")
    summary_table = sample_df[["Testing_Bit", "Internal_DAC_V", "Comp_Keep_Bit", "SAR_Register_Dec"]].rename(
        columns={
            "Testing_Bit": "Bit",
            "Internal_DAC_V": "DAC (V)",
            "Comp_Keep_Bit": "Keep?",
            "SAR_Register_Dec": "SAR",
        }
    )

    st.dataframe(summary_table, hide_index=True, use_container_width=True)

with st.expander("View Raw T-SQL Simulation Data"):
    st.dataframe(df, use_container_width=True)
