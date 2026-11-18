# Part 6: ADC0804 8-Bit Successive Approximation ADC (T-SQL & Streamlit)

> **Companion Article:** *[Read the full deep-dive article here](#)*  
> **Key Features:** Sample-and-Hold Analog Latching, 8-Step Recursive Binary Search (SAR), Internal R-2R Ladder DAC Comparison, End-of-Conversion Interrupt (`INTR`), and Live Nyquist Aliasing Simulation

This module models the classic **ADC0804 8-Bit Analog-to-Digital Converter** inside a T-SQL stored procedure (`dbo.SimulateADC0804`), demonstrating how a recursive Common Table Expression (CTE) implements hardware **Successive Approximation (SAR)** binary search to digitize continuous analog waveforms alongside an interactive Streamlit staircase oscilloscope and bit-level SAR microscope.

---

## 1. ADC0804 Pinout & Architecture (DIP-20)

```text
               +-----U-----+
       /CS  1 -|           |- 20  Vcc (+5V)
       /RD  2 -|           |- 19  CLK R
       /WR  3 -|           |- 18  DB0 (LSB)
    CLK IN  4 -|           |- 17  DB1
     /INTR  5 -|  ADC0804  |- 16  DB2
      Vin+  6 -|  8-Bit    |- 15  DB3
      Vin-  7 -| SAR ADC   |- 14  DB4
     A GND  8 -|           |- 13  DB5
    Vref/2  9 -|           |- 12  DB6
     D GND 10 -|           |- 11  DB7 (MSB)
               +-----------+
```

### How the T-SQL Pipeline Models the Hardware
Converting a continuous voltage into an 8-bit integer (`0–255`) requires freezing the analog signal and running an 8-clock binary search:

1. **Sample-and-Hold (`SampleHold` CTE):** Uses T-SQL's `FIRST_VALUE() OVER (PARTITION BY SampleIdx ORDER BY BitStep)` window function to freeze `Vin_Analog_V` at the start (`BitStep = 0`) of each 8-tick conversion window so the target voltage remains stable while bits are tested.
2. **8-Step SAR Binary Search (`SAR_CTE`):** Tests one bit per clock tick from MSB (`Bit 7`, weight `128`) down to LSB (`Bit 0`, weight `1`):
   * Sets the candidate bit in `Trial_Code` and computes the internal R-2R ladder voltage (`Trial_Code * (Vcc / 256)`).
   * Compares `Vin_Held_V >= Trial_DAC_V`: if true, keeps the bit in `SAR_Accum_Code`; otherwise discards it.
3. **Output Latch & Interrupt (`LatchedOutput` CTE):** At `BitStep = 7`, drives active-low **`/INTR` (Pin 5)** to `0V` to signal End-of-Conversion and latches the final 8-bit result onto **`DB7–DB0`**.

---

## 2. Running This Simulation

### Step 1: Deploy the Stored Procedure
Execute `schema.sql` against your `IC_Simulations` database:

```sql
-- Quick verification query in SSMS:
EXEC dbo.SimulateADC0804 
    @Vcc = 5.0,
    @Waveform = 'SINE',
    @Vin_Amplitude_V = 2.2,
    @Vin_Offset_V = 2.5,
    @SignalFreq_Hz = 50.0,
    @SampleRate_Hz = 1000.0,
    @TotalSamples = 35;
```

### Step 2: Launch the Streamlit Staircase & SAR Microscope
From the **root directory** of the repository, run:

```bash
streamlit run 06-adc0804-sar-adc/app.py
```

---

## 3. Recommended Experiment: Exceeding the Nyquist Limit
To observe **Nyquist-Shannon aliasing** live:
1. Keep **Sampling Rate** at `1,000 Samples/sec` (Nyquist limit $f_N = \frac{f_s}{2} = 500\text{ Hz}$).
2. Slowly increase **Input Signal Frequency** from `50 Hz` up past `500 Hz` (for example, `950 Hz`).
3. Watch the green reconstructed staircase fold back into a slow, false `50 Hz` beat wave—demonstrating why hardware ADCs require analog anti-aliasing low-pass filters ahead of `Vin+`.

---

## Series Navigation
* **Previous:** [Part 5: 74LS181 4-Bit Arithmetic Logic Unit](../05-74ls181-4bit-alu)
* **Series Home:** [Repository Overview](../README.md)
