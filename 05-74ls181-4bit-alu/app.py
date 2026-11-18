import sys
from pathlib import Path
import streamlit as st
import plotly.express as px

# Import shared database helper from repository root
sys.path.append(str(Path(__file__).resolve().parent.parent))
from shared.db_connection import execute_stored_procedure

st.set_page_config(page_title="74LS181 4-Bit ALU Simulator", layout="wide")
st.title("74LS181 4-Bit Arithmetic Logic Unit (Powered by T-SQL)")

# --- Sidebar Controls ---
st.sidebar.header("Control Bus (Mode & Opcode)")
mode_label = st.sidebar.radio("Mode Select (Pin 8: M)", ["Arithmetic Mode (M = 0)", "Logic Mode (M = 1)"])
mode_m = 0 if "Arithmetic" in mode_label else 1

opcode_names = {
    0: "0000 (0): NOT A / A",
    1: "0001 (1): NOR / A OR B",
    2: "0010 (2): (~A) AND B / A OR (~B)",
    3: "0011 (3): Logic 0 / Minus 1",
    4: "0100 (4): NAND / A + (A & ~B)",
    5: "0101 (5): NOT B / (A|B) + (A&~B)",
    6: "0110 (6): XOR / Subtract (A - B)",
    7: "0111 (7): A AND (~B) / (A&~B) - 1",
    8: "1000 (8): (~A) OR B / A + (A&B)",
    9: "1001 (9): XNOR / Add (A + B)",
    10: "1010 (10): Pass B / (A|~B) + (A&B)",
    11: "1011 (11): A AND B / (A&B) - 1",
    12: "1100 (12): Logic 1 / Shift Left (A + A)",
    13: "1101 (13): A OR (~B) / (A|B) + A",
    14: "1110 (14): A OR B / (A|~B) + A",
    15: "1111 (15): Pass A / Decrement (A - 1)",
}
select_s = st.sidebar.selectbox(
    "Function Select S3..S0",
    options=list(opcode_names.keys()),
    format_func=lambda k: opcode_names[k],
    index=9,  # Default to 1001 (ADD / XNOR)
)

carry_in = 0
if mode_m == 0:
    carry_in = 1 if st.sidebar.checkbox("Carry In (Cn = 1)", value=False) else 0
else:
    st.sidebar.caption("Carry In (Cn) is ignored in Logic Mode (M = 1).")

st.sidebar.header("4-Bit Data Buses (0–15)")
input_a = st.sidebar.slider("Operand A (A3..A0)", 0, 15, 9, 1)
input_b = st.sidebar.slider("Operand B (B3..B0)", 0, 15, 5, 1)


# --- Execute T-SQL Set-Based Query ---
@st.cache_data(ttl=60)
def run_alu(params: dict):
    return execute_stored_procedure("dbo.Simulate74LS181ALU", params)


sim_params = {
    "Input_A": input_a,
    "Input_B": input_b,
    "Select_S": select_s,
    "Mode_M": mode_m,
    "Carry_In": carry_in,
}

df = run_alu(sim_params)
selected_row = df[df["Is_Selected_Row"] == 1].iloc[0]

# --- Active Operation Banner ---
st.info(f"**Active ALU Instruction (`S = {selected_row['Select_Binary']}`, `M = {mode_m}`, `Cn = {carry_in}`):** `{selected_row['Active_Operation']}`")

# --- 4-Bit LED Register Visualizer ---
def render_nibble(title: str, value: int, color: str):
    st.markdown(f"**{title}:** `{value:04b}` (Dec: `{value}`, Hex: `0x{value:X}`)")
    cols = st.columns(4)
    for idx, bit_pos in enumerate([3, 2, 1, 0]):
        is_on = (value & (1 << bit_pos)) > 0
        bg = color if is_on else "#262730"
        glow = f"0 0 12px {color}" if is_on else "none"
        cols[idx].markdown(
            f"""
            <div style="text-align:center; padding:8px; border-radius:8px; background:#1E1E1E; border:1px solid #444;">
                <div style="width:22px; height:22px; margin:0 auto 4px auto; border-radius:50%;
                            background:{bg}; box-shadow:{glow}; border:1px solid #666;"></div>
                <div style="font-size:11px; color:#AAA;">Bit {bit_pos}</div>
                <div style="font-weight:bold; font-size:15px;">{1 if is_on else 0}</div>
            </div>
            """,
            unsafe_allow_html=True,
        )

c_a, c_b, c_f = st.columns(3)
with c_a:
    render_nibble("Operand A Bus", int(selected_row["Operand_A"]), "#636EFA")
with c_b:
    render_nibble("Operand B Bus", int(selected_row["Operand_B"]), "#FFA15A")
with c_f:
    render_nibble("ALU Output Bus (F3..F0)", int(selected_row["Output_F"]), "#00CC96")

st.markdown("---")
f1, f2, f3, f4 = st.columns(4)
f1.metric("Output F (Decimal)", f"{int(selected_row['Output_F'])}")
f2.metric("Carry Out (Cn+4)", f"{int(selected_row['Carry_Out'])}")
f3.metric("Comparator (A = B Pin)", "HIGH (1)" if selected_row["A_Equals_B_Pin"] == 1 else "LOW (0)")
f4.metric("Full 5-Bit Result", f"{(int(selected_row['Carry_Out']) << 4) + int(selected_row['Output_F'])}")

# --- 16x16 Relational Truth Matrix Heatmap ---
st.subheader("Full 16×16 Opcode Output Matrix (256 Input Combinations)")
st.caption("Computed in a single set-based T-SQL CROSS JOIN without loops.")

pivot_df = df.pivot(index="Operand_A", columns="Operand_B", values="Output_F")
fig = px.imshow(
    pivot_df,
    labels=dict(x="Operand B (0–15)", y="Operand A (0–15)", color="Output F"),
    x=list(range(16)),
    y=list(range(16)),
    text_auto=True,
    color_continuous_scale="Viridis",
    aspect="auto",
)

# Highlight the currently selected (A, B) cell with a bright red border
fig.add_shape(
    type="rect",
    x0=input_b - 0.5,
    x1=input_b + 0.5,
    y0=input_a - 0.5,
    y1=input_a + 0.5,
    line=dict(color="#FF4B4B", width=4),
)

fig.update_layout(height=550, xaxis=dict(dtick=1), yaxis=dict(dtick=1))
st.plotly_chart(fig, use_container_width=True)

with st.expander("View Full 256-Row T-SQL Truth Table"):
    st.dataframe(df, use_container_width=True)
