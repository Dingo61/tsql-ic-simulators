# Modelling Common ICs in T-SQL

T-SQL excels at set-based bitwise operations, state transitions, and recursive time-stepping. These capabilities make it surprisingly well suited to modelling classic digital, mixed-signal, and analog integrated circuits (ICs).

This document explores five ICs that would work particularly well in a T-SQL simulation engine paired with a Streamlit dashboard. Each example highlights a different set of SQL techniques.

## At a Glance

| IC model | Domain | Core T-SQL technique | Visualisation style |
|---|---|---|---|
| **CD4017** | Sequential logic | `LAG()` edge detection and modulo (`%`) | LED chaser and logic analyser |
| **74HC595** | Serial-to-parallel logic | Bitwise shifting in a recursive CTE | 8-bit register state grid |
| **LM741 / LM358** | Analog | Slew-rate limiting and rail saturation | Dual-trace oscilloscope |
| **74LS181** | Combinational logic | Relational truth-table joins | DIP switches and opcode matrix |
| **MCP3008 / ADC0804** | Mixed-signal | Recursive binary search (SAR) | Analog-to-digital staircase overlay |

---

## 1. CD4017 Decade Counter

> **Type:** Johnson counter / sequential logic

### What it does

The CD4017 takes a stream of clock pulses and activates ten output pins—`Q0` through `Q9`—one at a time in sequence. It is often paired with a 555 timer to create an LED chaser.

### Why it fits T-SQL

This IC is a natural demonstration of modulo arithmetic (`% 10`) and bitwise shifting. The output table from a 555 timer stored procedure could feed directly into the CD4017 procedure.

A `LAG()` window function can identify each rising clock edge:

```sql
Output_V > LAG(Output_V) OVER (ORDER BY Time_Step)
```

### Streamlit dashboard concept

- Render a horizontal row of ten LEDs using Plotly indicators or HTML/CSS circles.
- Add a time-scrubber slider to step through the sequence.
- Display a multi-channel logic-analyser timing diagram alongside the LEDs.

---

## 2. 74HC595 8-Bit Shift Register

> **Type:** Serial-to-parallel logic

### What it does

The 74HC595 converts serial data (`DS`) into eight parallel outputs (`Q0`–`Q7`) using a shift clock (`SHCP`) and a latch clock (`STCP`).

### Why it fits T-SQL

The device maps neatly to bitwise operations inside a recursive common table expression (CTE). On each rising edge of `SHCP`, T-SQL can update the internal 8-bit register with logic such as:

```sql
((ShiftReg * 2) & 255) | DataBit
```

When `STCP` goes high, the current shift-register value is copied to the storage register.

### Streamlit dashboard concept

- Provide text input or toggle switches for the serial data stream.
- Show the internal shift register and latched outputs separately.
- Display each register as both an 8-bit binary grid and a hexadecimal value.

---

## 3. LM741 / LM358 Operational Amplifier

> **Type:** Analog amplifier

### What it does

An operational amplifier amplifies the voltage difference between its non-inverting (`+`) and inverting (`−`) inputs. Its output is bounded by the positive and negative supply rails (`+Vcc` and `−Vee`).

### Why it fits T-SQL

Unlike the discrete state changes of a 555 timer, an op-amp demonstrates continuous analog transfer functions. A T-SQL model can represent:

- **Rail saturation** with a `CASE` expression that clamps the output to the supply rails.
- **Slew-rate limiting** by restricting the maximum `ΔV / Δt` between successive rows in a recursive CTE.
- **Clipping** when the calculated output exceeds the available voltage range.

### Streamlit dashboard concept

- Switch between inverting, non-inverting, voltage-follower, and comparator topologies.
- Adjust the frequency and amplitude of sine or triangle-wave inputs.
- View input and output traces in real time, including clipping distortion when the gain exceeds the supply rails.

---

## 4. 74LS181 4-Bit Arithmetic Logic Unit

> **Type:** Combinational logic / CPU building block

### What it does

The 74LS181 is a classic CPU building block that performs 16 arithmetic and 16 logic operations on two 4-bit values (`A` and `B`). The operation is selected by four function-select inputs (`S0`–`S3`) and the mode input.

### Why it fits T-SQL

Rather than relying on time-stepping, this model showcases truth-table lookups and set-based evaluation. The 32 operation rules can be stored in a relational table, allowing a single query to evaluate every possible combination of 4-bit inputs (`0`–`15`).

### Streamlit dashboard concept

- Create 4-bit DIP switches for inputs `A`, `B`, and the function selector.
- Display the binary result and carry-out flag.
- Show a complete truth-table matrix for the selected operation.

---

## 5. MCP3008 / ADC0804 Analog-to-Digital Converter

> **Type:** Successive-approximation ADC / mixed-signal

### What it does

These devices convert an analog input voltage into a digital value. A successive-approximation register (SAR) performs a binary search across a range of reference voltages, resolving one bit during each clock cycle.

### Why it fits T-SQL

The SAR process is a textbook binary-search algorithm. It translates cleanly into an 8-step or 10-step recursive CTE that compares the sampled input voltage with a progressively narrowing midpoint threshold.

### Streamlit dashboard concept

- Plot an analog waveform beside its stepped digital reconstruction.
- Add a magnified view of a single conversion cycle.
- Visualise how the SAR register resolves the output one bit at a time.

---

## SQL Techniques Demonstrated

Together, these five models cover a useful range of database programming patterns:

- **Window functions** for detecting clock edges.
- **Modulo and bitwise operations** for counters and registers.
- **Recursive CTEs** for time-stepping, slew-rate limiting, and binary search.
- **`CASE` expressions** for saturation and other bounded behaviours.
- **Relational truth tables** for set-based combinational logic.

They also provide varied visualisation opportunities—from LED arrays and logic traces to oscilloscope plots and interactive truth tables—making them strong candidates for a T-SQL and Streamlit simulation suite.
