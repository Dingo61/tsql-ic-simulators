# Simulate a 555 timer using T-SQL

To model a 555 timer IC using T-SQL as the simulation engine and Streamlit as the visualisation front end, you can treat T-SQL as a discrete-time physics solver. Using a recursive Common Table Expression (CTE), SQL Server can iteratively calculate the capacitor charging/discharging curve, comparator states, flip-flop latch logic, and output voltage across thousands of microsecond steps in a single query.

Below is the complete architecture, the T-SQL stored procedure for astable mode, and the Python/Streamlit dashboard to drive and plot it.

## 1. System Architecture

• T-SQL (Backend Engine): Uses a recursive CTE to step through time (Δ t). At each tick, it evaluates the RC circuit differential equation (\(V_c(t + \Delta t) = V_c(t) + (V_{target} - V_c(t)) \cdot (1 - e^{-\Delta t / \tau})\)), checks the \(\frac{1}{3}V_{cc}\) (Trigger) and \(\frac{2}{3}V_{cc}\) (Threshold) comparators, updates the SR flip-flop state, and controls the Discharge transistor (Pin 7).

• Streamlit (Frontend UI): Provides sliders for R₁, R₂, C, and \(V_{cc}\), executes the stored procedure via pyodbc, and renders the analog capacitor voltage alongside the digital output square wave.

## 2. T-SQL Simulation Engine

Run this script in your SQL Server database to create the simulation stored procedure.

```sql
CREATE OR ALTER PROCEDURE dbo.Simulate555Astable
    @Vcc FLOAT = 5.0,           -- Supply Voltage (Volts)
    @R1 FLOAT = 1000.0,         -- Resistor 1 (Ohms)
    @R2 FLOAT = 10000.0,        -- Resistor 2 (Ohms)
    @C_uF FLOAT = 10.0,         -- Capacitor (Microfarads)
    @TimeStep_ms FLOAT = 1.0,   -- Simulation resolution (Milliseconds)
    @TotalSteps INT = 500       -- Number of steps to simulate
AS
BEGIN
    SET NOCOUNT ON;

    -- Convert units to base SI (Farads and Seconds)
    DECLARE @C FLOAT = @C_uF / 1000000.0;
    DECLARE @dt FLOAT = @TimeStep_ms / 1000.0;

    -- 555 Internal Voltage Divider Thresholds
    DECLARE @V_upper FLOAT = (2.0 / 3.0) * @Vcc; -- Threshold pin (Pin 6)
    DECLARE @V_lower FLOAT = (1.0 / 3.0) * @Vcc; -- Trigger pin (Pin 2)

    -- RC Time Constants
    DECLARE @Tau_Charge FLOAT = (@R1 + @R2) * @C;
    DECLARE @Tau_Discharge FLOAT = @R2 * @C;

    -- Precalculate exponential decay factors for performance
    DECLARE @Alpha_Charge FLOAT = 1.0 - EXP(-@dt / @Tau_Charge);
    DECLARE @Alpha_Discharge FLOAT = 1.0 - EXP(-@dt / @Tau_Discharge);

    WITH TimerCTE AS (
        -- Anchor Member (t = 0, Capacitor starts empty, Output HIGH)
        SELECT 
            0 AS StepNum,
            CAST(0.0 AS FLOAT) AS Time_ms,
            CAST(0.0 AS FLOAT) AS V_cap,
            1 AS Q_Out,          -- Pin 3 Output (1 = HIGH, 0 = LOW)
            0 AS Discharge_On    -- Pin 7 Transistor (0 = Open/Charging, 1 = Grounded/Discharging)

        UNION ALL

        -- Recursive Member (Step t + dt)
        SELECT 
            StepNum + 1,
            Time_ms + @TimeStep_ms,
            
            -- 1. Calculate new Capacitor Voltage based on current Discharge state
            CASE 
                WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge
                ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge
            END AS V_cap,

            -- 2. Evaluate Comparators & SR Flip-Flop for NEXT state
            CASE 
                -- Threshold comparator trips: V_cap >= 2/3 Vcc -> Reset Flip-Flop (Output LOW)
                WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) >= @V_upper THEN 0
                -- Trigger comparator trips: V_cap <= 1/3 Vcc -> Set Flip-Flop (Output HIGH)
                WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) <= @V_lower THEN 1
                -- Hold previous latch state
                ELSE Q_Out
            END AS Q_Out,

            -- 3. Discharge pin (Pin 7) is the inverse of Output (Q_bar)
            CASE 
                WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) >= @V_upper THEN 1
                WHEN (CASE WHEN Discharge_On = 0 THEN V_cap + (@Vcc - V_cap) * @Alpha_Charge ELSE V_cap + (0.0 - V_cap) * @Alpha_Discharge END) <= @V_lower THEN 0
                ELSE Discharge_On
            END AS Discharge_On

        FROM TimerCTE
        WHERE StepNum < @TotalSteps
    )
    SELECT 
        StepNum,
        ROUND(Time_ms, 3) AS Time_ms,
        ROUND(V_cap, 4) AS Capacitor_V,
        Q_Out * @Vcc AS Output_V,
        Discharge_On AS Discharge_Pin_Active
    FROM TimerCTE
    OPTION (MAXRECURSION 32767); -- Allows up to 32,767 time steps
END;
GO

```



## 3. Streamlit Front End (app.py)

Install the required libraries (pip install streamlit pyodbc pandas plotly) and save the following script as app.py. Update the connection string to point to your SQL Server instance.

```python
import streamlit as st
import pyodbc
import pandas as pd
import plotly.graph_objects as go

st.set_page_config(page_title="555 Timer T-SQL Simulator", layout="wide")
st.title("555 Timer IC Simulator (Powered by T-SQL)")

# --- Sidebar Controls ---
st.sidebar.header("Circuit Parameters")
vcc = st.sidebar.slider("Supply Voltage Vcc (V)", 3.0, 15.0, 5.0, 0.5)
r1 = st.sidebar.number_input(
    "Resistor R1 (Ohms)", min_value=100, max_value=1000000, value=1000, step=100
)
r2 = st.sidebar.number_input(
    "Resistor R2 (Ohms)", min_value=100, max_value=1000000, value=10000, step=500
)
c_uf = st.sidebar.number_input(
    "Capacitor C (µF)", min_value=0.1, max_value=1000.0, value=10.0, step=0.5
)

st.sidebar.header("Simulation Resolution")
time_step = st.sidebar.slider("Time Step Δt (ms)", 0.1, 10.0, 1.0, 0.1)
total_steps = st.sidebar.slider("Total Steps", 100, 5000, 600, 100)

# --- Theoretical Calculations ---
c_farads = c_uf * 1e-6
t_high = 0.693 * (r1 + r2) * c_farads
t_low = 0.693 * r2 * c_farads
freq = 1.0 / (t_high + t_low)
duty_cycle = (t_high / (t_high + t_low)) * 100

col1, col2, col3, col4 = st.columns(4)
col1.metric("Frequency", f"{freq:.2f} Hz")
col2.metric("Duty Cycle", f"{duty_cycle:.1f} %")
col3.metric("Time High (T1)", f"{t_high * 1000:.1f} ms")
col4.metric("Time Low (T2)", f"{t_low * 1000:.1f} ms")


# --- Database Execution ---
@st.cache_data(ttl=60)
def run_sql_simulation(vcc, r1, r2, c_uf, time_step, total_steps):
    # Update SERVER and DATABASE to match your local SQL Server setup
    conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=localhost;"
        "DATABASE=YourDatabaseName;"
        "Trusted_Connection=yes;"
    )
    query = "EXEC dbo.Simulate555Astable @Vcc=?, @R1=?, @R2=?, @C_uF=?, @TimeStep_ms=?, @TotalSteps=?"
    with pyodbc.connect(conn_str) as conn:
        df = pd.read_sql(
            query, conn, params=[vcc, r1, r2, c_uf, time_step, total_steps]
        )
    return df


try:
    df = run_sql_simulation(vcc, r1, r2, c_uf, time_step, total_steps)

    # --- Plotting ---
    fig = go.Figure()

    # Output Square Wave (Pin 3)
    fig.add_trace(
        go.Scatter(
            x=df["Time_ms"],
            y=df["Output_V"],
            name="Pin 3: Output (V)",
            line=dict(color="#00CC96", width=2, shape="hv"),
        )
    )

    # Capacitor Voltage (Pins 2 & 6)
    fig.add_trace(
        go.Scatter(
            x=df["Time_ms"],
            y=df["Capacitor_V"],
            name="Pins 2 & 6: Capacitor (V)",
            line=dict(color="#636EFA", width=2.5),
        )
    )

    # Reference Threshold Lines
    fig.add_hline(
        y=(2 / 3) * vcc,
        line_dash="dash",
        line_color="red",
        annotation_text="2/3 Vcc (Threshold)",
    )
    fig.add_hline(
        y=(1 / 3) * vcc,
        line_dash="dash",
        line_color="orange",
        annotation_text="1/3 Vcc (Trigger)",
    )

    fig.update_layout(
        title="555 Timer Oscilloscope View",
        xaxis_title="Time (ms)",
        yaxis_title="Voltage (V)",
        hovermode="x unified",
        height=500,
    )

    st.plotly_chart(fig, use_container_width=True)

    with st.expander("View Raw T-SQL Simulation Data"):
        st.dataframe(df, use_container_width=True)

except Exception as e:
    st.error(f"Database Connection Error: {e}")
    st.info("Ensure SQL Server is running and update the connection string in app.py.")
```


## Key Engineering Considerations

• Time-Step Aliasing: Ensure @TimeStep_ms is significantly smaller than your RC time constants (τ = R₂ C). If Δ t is too large relative to the pulse width, the discrete simulation will overshoot the \(\frac{1}{3}V_{cc}\) and \(\frac{2}{3}V_{cc}\) thresholds, causing artificial frequency drift.
• Recursion Limits: SQL Server caps recursive CTEs at 32,767 iterations (OPTION (MAXRECURSION 32767)). If you need longer simulation windows without lowering temporal resolution, replace the recursive CTE with a WHILE loop inserting into a #TempTable or use a tally/numbers table with an iterative cursor.
If you'd like to expand this simulator, let me know if you want to:
• Add monostable (one-shot) or bistable operating modes with a manual trigger button in Streamlit
• Model Control Voltage (Pin 5) modulation to simulate frequency shifting or PWM
• Switch the T-SQL backend to a #TempTable loop to bypass the 32,767-step recursion limit.


## Bistable

To support bistable (flip-flop) mode, the 555 timer bypasses the RC timing network entirely. Instead, it acts as a pure SR latch controlled by two external digital inputs: Pin 2 (Trigger) sets the output HIGH when pulled below \(\frac{1}{3}V_{cc}\), and Pin 4 (Reset) forces the output LOW when pulled below its active-low threshold (~0.7 V).
Below are the updated T-SQL stored procedure and Streamlit front end with a mode selector and interactive pulse buttons.

## 1. Updated T-SQL Simulation Engine

This procedure accepts a @Mode parameter ('ASTABLE' or 'BISTABLE') along with comma-separated timestamp lists for manual Trigger and Reset button presses.
```sql
CREATE OR ALTER PROCEDURE dbo.Simulate555Timer
    @Mode VARCHAR(20) = 'ASTABLE',         -- 'ASTABLE' or 'BISTABLE'
    @Vcc FLOAT = 5.0,                      -- Supply Voltage (Volts)
    @R1 FLOAT = 1000.0,                    -- Resistor 1 (Ohms - Astable only)
    @R2 FLOAT = 10000.0,                   -- Resistor 2 (Ohms - Astable only)
    @C_uF FLOAT = 10.0,                    -- Capacitor (Microfarads - Astable only)
    @TimeStep_ms FLOAT = 1.0,              -- Simulation resolution (Milliseconds)
    @TotalSteps INT = 500,                 -- Number of steps to simulate
    @TriggerEvents_ms VARCHAR(MAX) = '',   -- CSV timestamps for Pin 2 low pulses (Bistable)
    @ResetEvents_ms VARCHAR(MAX) = '',     -- CSV timestamps for Pin 4 low pulses (Bistable)
    @PulseWidth_ms FLOAT = 20.0            -- Duration of button press (Milliseconds)
AS
BEGIN
    SET NOCOUNT ON;

    -- Parse Bistable button press events into table variables
    DECLARE @Triggers TABLE (Start_ms FLOAT);
    DECLARE @Resets TABLE (Start_ms FLOAT);

    IF @Mode = 'BISTABLE'
    BEGIN
        INSERT INTO @Triggers (Start_ms)
        SELECT TRY_CAST(value AS FLOAT) 
        FROM STRING_SPLIT(@TriggerEvents_ms, ',') 
        WHERE TRY_CAST(value AS FLOAT) IS NOT NULL;

        INSERT INTO @Resets (Start_ms)
        SELECT TRY_CAST(value AS FLOAT) 
        FROM STRING_SPLIT(@ResetEvents_ms, ',') 
        WHERE TRY_CAST(value AS FLOAT) IS NOT NULL;
    END

    -- Base SI Conversions & Thresholds
    DECLARE @C FLOAT = @C_uF / 1000000.0;
    DECLARE @dt FLOAT = @TimeStep_ms / 1000.0;
    DECLARE @V_upper FLOAT = (2.0 / 3.0) * @Vcc;
    DECLARE @V_lower FLOAT = (1.0 / 3.0) * @Vcc;

    -- RC Constants (Astable)
    DECLARE @Alpha_Charge FLOAT = 1.0 - EXP(-@dt / ((@R1 + @R2) * @C));
    DECLARE @Alpha_Discharge FLOAT = 1.0 - EXP(-@dt / (@R2 * @C));

    WITH TimerCTE AS (
        -- Anchor Member (t = 0)
        SELECT 
            0 AS StepNum,
            CAST(0.0 AS FLOAT) AS Time_ms,
            CAST(0.0 AS FLOAT) AS V_cap,
            CASE WHEN @Mode = 'ASTABLE' THEN 1 ELSE 0 END AS Q_Out,
            0 AS Discharge_On,
            @Vcc AS Pin2_Trigger_V,
            @Vcc AS Pin4_Reset_V

        UNION ALL

        -- Recursive Member
        SELECT 
            c.StepNum + 1,
            c.Time_ms + @TimeStep_ms,

            -- Capacitor Voltage (Active in Astable, 0V in Bistable)
            CASE 
                WHEN @Mode = 'BISTABLE' THEN 0.0
                WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge
                ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge
            END AS V_cap,

            -- Output State (Pin 3)
            CASE 
                WHEN @Mode = 'ASTABLE' THEN
                    CASE 
                        WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) >= @V_upper THEN 0
                        WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) <= @V_lower THEN 1
                        ELSE c.Q_Out
                    END
                ELSE -- BISTABLE LOGIC (Pin 4 Reset overrides Pin 2 Trigger)
                    CASE 
                        WHEN EXISTS (SELECT 1 FROM @Resets r WHERE (c.Time_ms + @TimeStep_ms) BETWEEN r.Start_ms AND (r.Start_ms + @PulseWidth_ms)) THEN 0
                        WHEN EXISTS (SELECT 1 FROM @Triggers t WHERE (c.Time_ms + @TimeStep_ms) BETWEEN t.Start_ms AND (t.Start_ms + @PulseWidth_ms)) THEN 1
                        ELSE c.Q_Out
                    END
            END AS Q_Out,

            -- Discharge Pin (Pin 7)
            CASE 
                WHEN @Mode = 'BISTABLE' THEN 0
                WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) >= @V_upper THEN 1
                WHEN (CASE WHEN c.Discharge_On = 0 THEN c.V_cap + (@Vcc - c.V_cap) * @Alpha_Charge ELSE c.V_cap + (0.0 - c.V_cap) * @Alpha_Discharge END) <= @V_lower THEN 0
                ELSE c.Discharge_On
            END AS Discharge_On,

            -- Track Pin 2 Voltage for plotting (Pulled to 0V when pressed)
            CASE 
                WHEN @Mode = 'BISTABLE' AND EXISTS (SELECT 1 FROM @Triggers t WHERE (c.Time_ms + @TimeStep_ms) BETWEEN t.Start_ms AND (t.Start_ms + @PulseWidth_ms)) THEN 0.0
                ELSE @Vcc 
            END AS Pin2_Trigger_V,

            -- Track Pin 4 Voltage for plotting (Pulled to 0V when pressed)
            CASE 
                WHEN @Mode = 'BISTABLE' AND EXISTS (SELECT 1 FROM @Resets r WHERE (c.Time_ms + @TimeStep_ms) BETWEEN r.Start_ms AND (r.Start_ms + @PulseWidth_ms)) THEN 0.0
                ELSE @Vcc 
            END AS Pin4_Reset_V

        FROM TimerCTE c
        WHERE c.StepNum < @TotalSteps
    )
    SELECT 
        StepNum,
        ROUND(Time_ms, 3) AS Time_ms,
        ROUND(V_cap, 4) AS Capacitor_V,
        Q_Out * @Vcc AS Output_V,
        Pin2_Trigger_V,
        Pin4_Reset_V,
        Discharge_On AS Discharge_Pin_Active
    FROM TimerCTE
    OPTION (MAXRECURSION 32767);
END;
GO

```


## 2. Updated Streamlit Front End (app.py)

The UI dynamically switches between RC sliders (Astable) and timestamp pulse inputs (Bistable), plotting the active-low Trigger and Reset waveforms alongside the latched output.

```python
import streamlit as st
import pyodbc
import pandas as pd
import plotly.graph_objects as go

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

    st.info("**Bistable Operation:** Pulling **Pin 2 (Trigger)** to 0V latches Pin 3 HIGH. Pulling **Pin 4 (Reset)** to 0V latches Pin 3 LOW. If both are pressed simultaneously, Reset takes priority.")

st.sidebar.header("Simulation Resolution")
time_step = st.sidebar.slider("Time Step Δt (ms)", 0.5, 10.0, 1.0, 0.5)
total_steps = st.sidebar.slider("Total Steps", 100, 2000, 600, 100)

# --- Database Execution ---
@st.cache_data(ttl=60)
def run_sql_simulation(mode, vcc, r1, r2, c_uf, time_step, total_steps, trig, rst, pw):
    conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=localhost;"
        "DATABASE=YourDatabaseName;"
        "Trusted_Connection=yes;"
    )
    query = """
        EXEC dbo.Simulate555Timer 
            @Mode=?, @Vcc=?, @R1=?, @R2=?, @C_uF=?, 
            @TimeStep_ms=?, @TotalSteps=?, 
            @TriggerEvents_ms=?, @ResetEvents_ms=?, @PulseWidth_ms=?
    """
    params = [mode, vcc, r1, r2, c_uf, time_step, total_steps, trig, rst, pw]
    with pyodbc.connect(conn_str) as conn:
        return pd.read_sql(query, conn, params=params)

try:
    df = run_sql_simulation(
        mode, vcc, r1, r2, c_uf, time_step, total_steps,
        trigger_events, reset_events, pulse_width
    )

    # --- Plotting ---
    fig = go.Figure()

    # Pin 3 Output (Always shown)
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
        # Plot Active-Low Trigger & Reset lines in Bistable mode
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

except Exception as e:
    st.error(f"Database Connection Error: {e}")

```
Use code with caution.

How Bistable Mode is Modelled in T-SQL

• Active-Low Inputs: In real hardware, both Pin 2 (Trigger) and Pin 4 (Reset) are held HIGH at \(V_{cc}\) via pull-up resistors. Pressing a momentary pushbutton shorts the respective pin to ground (0V) for @PulseWidth_ms.
• Reset Dominance: Inside an actual NE555 chip, the Reset transistor directly overrides the internal SR flip-flop regardless of the comparator states. In the T-SQL CASE statement, checking @Resets before @Triggers replicates this hardware priority when both buttons are pressed at the same time.
