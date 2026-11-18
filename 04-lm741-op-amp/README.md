# Part 4: LM741 Operational Amplifier (T-SQL & Streamlit)

> **Companion Article:** *[Read the full deep-dive article here](#)*  
> **Topologies Covered:** Non-Inverting Amplifier, Inverting Amplifier, Voltage Follower (Buffer), and Open-Loop Comparator  
> **Analog Non-Linearities Modeled:** Supply-Rail Saturation Clipping (`+Vcc - 1.5V` / `-Vee + 1.5V`) & Slew-Rate Limiting (`0.5 V/µs`)

This module models the legendary **LM741 General-Purpose Operational Amplifier** inside a T-SQL stored procedure (`dbo.SimulateLM741OpAmp`), demonstrating how T-SQL trigonometric functions (`SIN()`, `ASIN()`) and recursive slope clamping reproduce real-world analog saturation and slew-rate distortion alongside a dual-rail Streamlit oscilloscope.

---

## 1. LM741 Pinout & Analog Transfer Model (DIP-8)

```text
               +----U----+
Offset Null 1 -|         |- 8  NC (No Connection)
Inverting - 2 -|  LM741  |- 7  +Vcc (+5V to +18V)
Non-Inv   + 3 -| Op-Amp  |- 6  Output (Vout)
       -Vee 4 -|         |- 5  Offset Null
               +---------+
```

### How the T-SQL Pipeline Models the Hardware
Unlike the discrete digital states of Parts 2 and 3, an operational amplifier processes continuous analog voltages bounded by physical power-supply limits and internal compensation capacitance:

1. **Waveform Synthesis (`IdealTransfer`):** Generates continuous `SINE`, `SQUARE`, and `TRIANGLE` input test signals (`Vin`) at microsecond resolution using T-SQL `SIN()` and `ASIN(SIN(...))` identities.
2. **Closed-Loop Gain & Rail Clipping (`ClampedTransfer` → `TargetOutput`):**
   * **Non-Inverting:** $A_v = 1 + \frac{R_f}{R_{in}}$
   * **Inverting:** $A_v = -\frac{R_f}{R_{in}}$
   * **Voltage Follower:** $A_v = 1$
   * **Comparator:** Open-loop differential gain ($A_{OL} \approx 100,000\text{ V/V}$) around $V_{\text{ref}}$.
   * **Saturation Headroom:** Because the LM741 uses a classic bipolar output stage rather than rail-to-rail transistors, output voltage is clamped ~`1.5V` inside the `+Vcc` and `-Vee` rails.
3. **Slew-Rate Clamping (`SlewCTE`):** Inside a real LM741, a `30 pF` internal Miller compensation capacitor limits how fast the output voltage can change (`SR ≈ 0.5 V/µs`). The recursive CTE enforces $\left|\frac{\Delta V_{\text{out}}}{\Delta t}\right| \le \text{SR}$ between consecutive rows:
   ```sql
   CASE 
       WHEN (t.Vout_Ideal_Clipped - s.Vout_Actual) > @Max_DeltaV THEN s.Vout_Actual + @Max_DeltaV
       WHEN (t.Vout_Ideal_Clipped - s.Vout_Actual) < -@Max_DeltaV THEN s.Vout_Actual - @Max_DeltaV
       ELSE t.Vout_Ideal_Clipped
   END
   ```

---

## 2. Running This Simulation

### Step 1: Deploy the Stored Procedure
Execute `schema.sql` against your `IC_Simulations` database:

```sql
-- Quick verification query in SSMS:
EXEC dbo.SimulateLM741OpAmp 
    @Topology = 'NON_INVERTING',
    @Vcc = 15.0,
    @Vee = -15.0,
    @Rin_Ohms = 1000,
    @Rf_Ohms = 4700,
    @Waveform = 'SINE',
    @Vin_Amplitude_V = 2.0,
    @SignalFreq_Hz = 15000,
    @SlewRate_V_us = 0.5,
    @EnableSlewLimit = 1,
    @TimeStep_us = 2.0,
    @TotalSteps = 800;
```

### Step 2: Launch the Streamlit Oscilloscope
From the **root directory** of the repository, run:

```bash
streamlit run 04-lm741-op-amp/app.py
```

---

## 3. Recommended Experiment: Slew-Rate Triangle Distortion
To see why engineers pay close attention to **Full-Power Bandwidth** ($f_{\max} = \frac{\text{SR}}{2\pi V_{\text{peak}}}$):
1. Set **Topology** to `NON_INVERTING` with `Rin = 1000 Ω` and `Rf = 4700 Ω` (`Gain = 5.7x`).
2. Set **Input Amplitude** to `2.0 V` (`11.4 V` expected output peak) and **Slew Rate** to `0.5 V/µs` (Full-Power Bandwidth ≈ `7.0 kHz`).
3. Sweep **Signal Frequency** from `2,000 Hz` up to `15,000 Hz`.
4. Watch the green `Vout` trace lag behind the dashed orange ideal sine wave and morph into a lower-amplitude **triangle wave** once the required slope exceeds `0.5 V/µs`.

---

## Series Navigation
* **Previous:** [Part 3: 74HC595 8-Bit Shift Register](../03-74hc595-shift-register)
* **Next:** *Part 5: 74LS181 4-Bit Arithmetic Logic Unit (Coming Soon)*
