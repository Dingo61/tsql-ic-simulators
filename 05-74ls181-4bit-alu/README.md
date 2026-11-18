# Part 5: 74LS181 4-Bit Arithmetic Logic Unit (T-SQL & Streamlit)

> **Companion Article:** *[Read the full deep-dive article here](#)*  
> **Key Features:** All 16 Bitwise Logic Operations (`M = 1`), All 16 Arithmetic Operations (`M = 0`), Ripple Carry In/Out (`Cn` / `Cn+4`), Open-Collector `A = B` Comparator Flag, and a Full 256-State Relational Truth Matrix

This module models the legendary **74LS181 4-Bit ALU**—the vintage CPU building block at the heart of the DEC PDP-11 and Data General Nova—inside a purely set-based T-SQL stored procedure (`dbo.Simulate74LS181ALU`), paired with a 4-bit DIP-switch workbench and 16×16 opcode heatmap in Streamlit.

---

## 1. 74LS181 Pinout & Architecture (DIP-24)

```text
               +-----U-----+
        B0  1 -|           |- 24  Vcc (+5V)
        A0  2 -|           |- 23  A1
        S3  3 -|           |- 22  B1
        S2  4 -|           |- 21  A2
        S1  5 -|  74LS181  |- 20  B2
        S0  6 -|  4-Bit    |- 19  A3
        Cn  7 -|   ALU     |- 18  B3
         M  8 -|           |- 17  G (Carry Generate)
        F0  9 -|           |- 16  Cn+4 (Carry Out)
        F1 10 -|           |- 15  P (Carry Propagate)
        F2 11 -|           |- 14  A = B (Comparator Out)
       GND 12 -|           |- 13  F3
               +-----------+
```

### How the T-SQL Engine Models the Hardware
Unlike Parts 1–4, which stepped sequentially through time, the 74LS181 is a **purely combinational circuit** with no clock pin. That makes it an ideal fit for set-based relational SQL:

1. **Full State-Space Generation (`CROSS JOIN`):** Using a 16-row `VALUES` constructor (`0..15`), T-SQL performs a `CROSS JOIN` between Operand A and Operand B to evaluate **all 256 possible 4-bit input combinations simultaneously** in a single declarative pass without loops or recursion.
2. **Mode & Function Select (`M` & `S3..S0`):**
   * **Logic Mode (`M = 1`):** Suppresses internal carries and executes 16 pure bitwise Boolean operations (`AND`, `OR`, `XOR`, `NAND`, `NOR`, `XNOR`, `NOT`, etc.) masked to 4 bits (`& 15`).
   * **Arithmetic Mode (`M = 0`):** Evaluates 16 two's-complement arithmetic functions (`A + B`, `A - B`, `A + A`, increment/decrement, and compound logic-arithmetic expressions) in wider integer precision so overflow/borrow bits can be extracted cleanly.
3. **Status Flags (`Cn+4` & `A = B`):**
   * **Carry Out (`Cn+4` / Pin 16):** Triggers whenever the unclamped arithmetic result exceeds `15` (unsigned overflow) or drops below `0` (borrow).
   * **Comparator (`A = B` / Pin 14):** Open-collector output that goes HIGH whenever all four result bits equal `1` (`Output_F = 15`).

---

## 2. Running This Simulation

### Step 1: Deploy the Stored Procedure
Execute `schema.sql` against your `IC_Simulations` database:

```sql
-- Quick verification query in SSMS (Addition: 9 + 5 = 14):
EXEC dbo.Simulate74LS181ALU 
    @Input_A = 9,
    @Input_B = 5,
    @Select_S = 9,   -- 1001 = Add (A + B)
    @Mode_M = 0,     -- Arithmetic Mode
    @Carry_In = 0;
```

### Step 2: Launch the Streamlit ALU Workbench
From the **root directory** of the repository, run:

```bash
streamlit run 05-74ls181-4bit-alu/app.py
```

---

## 3. Classic 74LS181 Experiments to Try
* **Two's Complement Subtraction (`S = 0110`, `M = 0`):** Notice that with `Carry In = 0`, opcode `0110` computes `A - B - 1`. Flip **`Carry In = 1`** to inject the `+1` needed for true two's-complement subtraction (`A + ~B + 1 = A - B`), and observe `A = B` light up when `Operand A == Operand B` (since `A - B - 1 = -1 = 1111` when `Cn = 0`).
* **ALU Left-Shift (`S = 1100`, `M = 0`):** Early minicomputers saved silicon by omitting dedicated barrel shifters and instead routing `A + A` through the ALU to perform a 1-bit left shift (`× 2`), with the shifted-out MSB landing directly on `Carry Out (Cn+4)`.

---

## Series Navigation
* **Previous:** [Part 4: LM741 Operational Amplifier](../04-lm741-op-amp)
* **Next:** *Part 6: ADC0804 8-Bit Successive Approximation ADC (Coming Soon)*
