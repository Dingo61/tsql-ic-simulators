# Part 1: NE555 Precision Timer IC (T-SQL & Streamlit)

> **Companion Article:** *[Read the full deep-dive article here](#)*  
> **Operating Modes Covered:** Astable (Free-Running Oscillator) & Bistable (SR Flip-Flop)

This module models the internal analog-to-digital architecture of the classic **NE555 Timer IC** inside a single T-SQL stored procedure (`dbo.Simulate555Timer`) using a recursive Common Table Expression (CTE), paired with an interactive Streamlit oscilloscope.

---

## 1. NE555 Pinout & Internal Architecture

```text
               +----U----+
      GND   1 -|         |- 8  Vcc (+3V to +15V)
  Trigger   2 -|  NE555  |- 7  Discharge
   Output   3 -|  Timer  |- 6  Threshold
    Reset   4 -|         |- 5  Control Voltage
               +---------+
```

### How the T-SQL Engine Models the Hardware
Inside a physical 555 chip, three identical 5 kΩ resistors form a voltage divider establishing two reference thresholds: **\(\frac{1}{3}V_{cc}\)** and **\(\frac{2}{3}V_{cc}\)**. Our T-SQL recursive CTE replicates the internal feedback loop at each discrete time step ($\Delta t$):

1. **RC Charging / Discharging (Analog):** Computes capacitor voltage using the exact exponential step equation:
   $$V_c(t + \Delta t) = V_c(t) + (V_{\text{target}} - V_c(t)) \cdot \left(1 - e^{-\Delta t / \tau}\right)$$
   * **Charging ($\tau_1 = (R_1 + R_2)C$):** Occurs when Pin 7 (Discharge transistor) is open (`Discharge_On = 0`).
   * **Discharging ($\tau_2 = R_2 C$):** Occurs when Pin 7 is grounded (`Discharge_On = 1`).
2. **Dual Comparators & SR Flip-Flop (Digital):**
   * **Threshold Comparator (Pin 6):** When $V_c \ge \frac{2}{3}V_{cc}$, resets the latch (`Q_Out = 0`) and turns on the discharge transistor.
   * **Trigger Comparator (Pin 2):** When $V_c \le \frac{1}{3}V_{cc}$, sets the latch (`Q_Out = 1`) and releases the discharge transistor.
   * **Active-Low Reset (Pin 4):** Overrides both comparators and forces `Q_Out = 0` whenever pulled LOW.

---

## 2. Operating Modes Included

### Astable Mode (Square-Wave Oscillator)
Connects Pins 2 and 6 together across timing capacitor $C$, creating a self-triggering RC relaxation oscillator.
* **Theoretical Frequency:** $f = \frac{1.44}{(R_1 + 2R_2)C}$
* **Duty Cycle:** $D = \frac{R_1 + R_2}{R_1 + 2R_2} \times 100\%$

### Bistable Mode (Manual SR Latch)
Bypasses the RC timing network entirely. Momentary active-low pulses on **Pin 2 (Trigger)** latch the output HIGH, while active-low pulses on **Pin 4 (Reset)** latch the output LOW.

---

## 3. Running This Simulation

### Step 1: Deploy the Stored Procedure
Open `schema.sql` in SQL Server Management Studio (SSMS), Azure Data Studio, or `sqlcmd` and execute it against your `IC_Simulations` database:

```sql
-- Quick verification query in SSMS:
EXEC dbo.Simulate555Timer 
    @Mode = 'ASTABLE',
    @Vcc = 5.0,
    @R1 = 1000,
    @R2 = 10000,
    @C_uF = 10.0,
    @TimeStep_ms = 1.0,
    @TotalSteps = 500;
```

### Step 2: Launch the Streamlit Oscilloscope
From the **root directory** of the repository, run:

```bash
streamlit run 01-ne555-timer/app.py
```

---

## 4. Key SQL Engineering Notes
* **Numerical Stability vs. Step Size:** Keep `@TimeStep_ms` at least $10\times$ smaller than your shortest RC time constant ($\tau_2 = R_2 C$). Large time steps cause discrete threshold overshoots, slightly lowering simulated frequency compared to the continuous-time formula.
* **Recursion Ceiling:** The stored procedure uses `OPTION (MAXRECURSION 32767)` to support up to 32,767 time steps in a single set-based execution without temporary tables or procedural `WHILE` loops.

---

## Next in the Series
* **[Part 2: CD4017 Decade Counter](../02-cd4017-decade-counter)** — *Chaining the NE555 clock output into a 10-stage Johnson counter using T-SQL window functions (`LAG()`).*
