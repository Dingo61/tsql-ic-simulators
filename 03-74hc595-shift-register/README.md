# Part 3: 74HC595 8-Bit Shift Register (T-SQL & Streamlit)

> **Companion Article:** *[Read the full deep-dive article here](#)*  
> **Key Features:** Serial-In Parallel-Out (SIPO) Bitwise Shifting, Dual-Register Storage Latch (`STCP`), Daisy-Chain Overflow (`Q7'`), Master Reset (`MR`), and Tri-State (`Hi-Z`) Output Enable (`OE`)

This module models the classic **74HC595 8-Bit Shift Register** inside a T-SQL stored procedure (`dbo.Simulate74HC595ShiftRegister`), showcasing how T-SQL bitwise operators (`&`, `|`) and `NULL`-based tri-state modeling replicate dual-register digital hardware alongside an interactive dual-register inspector in Streamlit.

---

## 1. 74HC595 Pinout & Architecture (DIP-16)

```text
               +-----U-----+
        Q1  1 -|           |- 16  Vcc (+2V to +6V)
        Q2  2 -|           |- 15  Q0
        Q3  3 -|           |- 14  Serial Data In (DS)
        Q4  4 -|  74HC595  |- 13  Output Enable (OE - Active Low)
        Q5  5 -|   Shift   |- 12  Storage Latch Clock (STCP)
        Q6  6 -|  Register |- 11  Shift Register Clock (SHCP)
        Q7  7 -|           |- 10  Master Reset (MR - Active Low)
       GND  8 -|           |-  9  Serial Out / Cascade (Q7')
               +-----------+
```

### How the T-SQL Pipeline Models the Hardware
Inside a physical 74HC595, two separate 8-bit registers prevent output pins from flickering while new bits are being shifted in. Our T-SQL recursive CTE tracks both registers simultaneously:

1. **Shift Clock Generation & Edge Detection (`ClockGen` → `SignalAnalysis`):** Generates the `SHCP` (Pin 11) clock stream and detects rising transitions (`0 → 1`) via `LAG()`.
2. **Bitwise Left-Shift (`RegisterCTE`):** Because T-SQL does not include a `<<` bit-shift operator, shifting an 8-bit integer left by one position and injecting the incoming `DS` bit (Pin 14) is expressed using multiplication, bitwise `AND` masking (`& 255`), and bitwise `OR` (`|`):
   ```sql
   ((r.Shift_Reg * 2) & 255) | r.DS_Bit
   ```
3. **Storage Register Latch (`STCP` / Pin 12):** Holds `Storage_Reg` steady until a latch trigger occurs (either automatically on every 8th clock edge in `AUTO_BYTE` mode, or on user-defined `MANUAL` timestamps), copying `Shift_Reg` to the output pins (`Q0–Q7`).
4. **Cascade & Control Pins:**
   * **Serial Cascade (`Q7'` / Pin 9):** Continuously mirrors Bit 7 (`Shift_Reg & 128`) of the *internal* shift register, enabling multiple 74HC595 chips to be daisy-chained.
   * **Master Reset (`MR` / Pin 10):** Active-low asynchronous clear that zeros the internal shift register (`Shift_Reg = 0`).
   * **Output Enable (`OE` / Pin 13):** Active-low tri-state buffer control. When pulled HIGH, outputs enter a high-impedance (`Hi-Z`) disconnected state.

---

## 2. Running This Simulation

### Step 1: Deploy the Stored Procedure
Execute `schema.sql` against your `IC_Simulations` database:

```sql
-- Quick verification query in SSMS:
EXEC dbo.Simulate74HC595ShiftRegister 
    @Vcc = 5.0,
    @BitStream = '10110101',
    @ClockFreq_Hz = 10.0,
    @LatchMode = 'AUTO_BYTE',
    @TimeStep_ms = 2.0,
    @TotalSteps = 500;
```

### Step 2: Launch the Streamlit Inspector & Logic Analyzer
From the **root directory** of the repository, run:

```bash
streamlit run 03-74hc595-shift-register/app.py
```

---

## 3. Key SQL Engineering Notes
* **SQL `NULL` as Hardware `Hi-Z` (Tri-State):** In digital electronics, a high-impedance (`Hi-Z`) pin is neither `0V` (LOW) nor `Vcc` (HIGH)—it is electrically floating. Returning `NULL` from T-SQL when `OE` is HIGH and setting `connectgaps=False` in Plotly renders accurate floating breaks on the logic analyzer traces.
* **Parallel Pin Decoding via Bitmasks:** Individual output voltages (`Q0–Q7`) are extracted cleanly in the final `SELECT` using powers-of-two bitmasks (`Storage_Reg & 1`, `Storage_Reg & 2`, ..., `Storage_Reg & 128`).

---

## Series Navigation
* **Previous:** [Part 2: CD4017 CMOS Decade Counter](../02-cd4017-decade-counter)
* **Next:** *Part 4: LM741 Operational Amplifier (Coming Soon)*
