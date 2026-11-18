# Part 2: CD4017 CMOS Decade Counter (T-SQL & Streamlit)

> **Companion Article:** *[Read the full deep-dive article here](#)*  
> **Key Features:** Chained NE555 Clock Driver, 10-Stage Johnson Counter (`Q0–Q9`), Carry Out (`CO`), Clock Inhibit (`CE`), and Asynchronous Master Reset (`MR`)

This module models the **CD4017 Decade Counter / Divider IC** inside a multi-stage T-SQL pipeline (`dbo.SimulateCD4017Counter`), demonstrating how SQL window functions (`LAG()`) and modulo arithmetic replicate sequential digital logic—complete with an interactive 10-LED chaser and 14-channel logic analyzer in Streamlit.

---

## 1. CD4017 Pinout & Architecture (DIP-16)

```text
               +-----U-----+
        Q5  1 -|           |- 16  Vdd (+3V to +15V)
        Q1  2 -|           |- 15  Master Reset (MR)
        Q0  3 -|           |- 14  Clock In (CLK)
        Q2  4 -|  CD4017   |- 13  Clock Inhibit (CE)
        Q6  5 -|  Decade   |- 12  Carry Out (CO)
        Q7  6 -|  Counter  |- 11  Q9
        Q3  7 -|           |- 10  Q4
       GND  8 -|           |-  9  Q8
               +-----------+
```

### How the T-SQL Pipeline Models the Hardware
Unlike the analog RC physics of Part 1, the CD4017 is a **synchronous 5-stage Johnson counter** with built-in decoding logic. The stored procedure chains four Common Table Expressions (CTEs) together:

1. **Clock Generation (`ClockCTE`):** Generates the incoming pulse stream on **Pin 14 (`CLK`)** using either the **NE555 RC oscillator model** from Part 1 or an ideal square-wave generator.
2. **Schmitt-Trigger Edge Detection (`SignalAnalysis`):** Uses T-SQL's `LAG()` window function to detect rising clock edges (`0V → Vcc`):
   ```sql
   CASE 
       WHEN Clk_State = 1 AND ISNULL(LAG(Clk_State) OVER (ORDER BY StepNum), 0) = 0 THEN 1 
       ELSE 0 
   END AS Is_Rising_Edge
   ```
3. **Johnson Counter State Machine (`CounterCTE`):**
   * **Master Reset (Pin 15):** Active-high **asynchronous** override—immediately forces the counter back to `Q0` (`Count_State = 0`) regardless of the clock state.
   * **Clock Inhibit (Pin 13):** Active-high **synchronous** gate—freezes the counter on its current output pin even when rising clock edges arrive.
   * **Decade Rollover:** On each uninhibited rising edge, increments the state via `(Count_State + 1) % 10`.
4. **Output Pin Decoder:** Maps `Count_State` (`0–9`) to the 10 individual output pins (`Q0–Q9`) and drives **Carry Out (Pin 12)** HIGH for counts `0–4` and LOW for counts `5–9` (a divide-by-10 square wave used for cascading multiple CD4017 chips).

---

## 2. Running This Simulation

### Step 1: Deploy the Stored Procedure
Execute `schema.sql` against your `IC_Simulations` database:

```sql
-- Quick verification query in SSMS:
EXEC dbo.SimulateCD4017Counter 
    @ClockSource = 'NE555',
    @Vcc = 5.0,
    @R1 = 1000,
    @R2 = 10000,
    @C_uF = 5.0,
    @ResetEvents_ms = '320',
    @InhibitEvents_ms = '180',
    @TimeStep_ms = 1.0,
    @TotalSteps = 500;
```

### Step 2: Launch the Streamlit Chaser & Logic Analyzer
From the **root directory** of the repository, run:

```bash
streamlit run 02-cd4017-decade-counter/app.py
```

---

## 3. Key SQL Engineering Notes
* **Strict Type Safety in Recursive CTEs:** SQL Server requires exact data-type matching between the anchor and recursive members of a CTE (`CAST(0.0 AS FLOAT)`), and `FLOOR()` returns a `FLOAT` that must be cast to `BIGINT` or `INT` before applying the modulo (`%`) operator.
* **Chaining ICs in SQL:** Because T-SQL is declarative, chaining an analog timer (`NE555`) into a digital counter (`CD4017`) requires zero external glue code—the output columns of the first CTE flow directly into the window function of the second.

---

## Series Navigation
* **Previous:** [Part 1: NE555 Precision Timer IC](../01-ne555-timer)
* **Next:** *Part 3: 74HC595 8-Bit Shift Register (Coming Soon)*
